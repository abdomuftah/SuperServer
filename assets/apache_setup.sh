#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

INFO_FILE="/root/SNYT/serverInfo.txt"
DOMAIN_LOG="/root/SNYT/domains.txt"
SHARED_ASSET_DIR="/usr/local/share/snyt-superserver"
error(){ echo "Error: $1" >&2; exit 1; }
[[ $EUID -eq 0 ]] || error "Run as root."
read_info_value(){ awk -F': ' -v wanted="$1" '$1==wanted{sub(/^[^:]+: /,"");print;exit}' "$INFO_FILE" 2>/dev/null; }
validate_domain(){ [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$ ]]; }

php_fpm_listen_value(){
  local version="$1" file value=""
  shopt -s nullglob
  for file in /etc/php/"$version"/fpm/pool.d/*.conf; do
    value="$(awk '
      /^[[:space:]]*;/ {next}
      /^[[:space:]]*\[/ {pool=$0}
      pool ~ /^[[:space:]]*\[www\][[:space:]]*$/ && /^[[:space:]]*listen[[:space:]]*=/ {
        sub(/^[^=]*=[[:space:]]*/,""); gsub(/[[:space:]]+$/,""); print; exit
      }
    ' "$file")"
    [[ -n "$value" ]] && break
  done
  shopt -u nullglob
  printf '%s' "$value"
}
endpoint_exists(){
  local endpoint="$1" port
  if [[ "$endpoint" == /* ]]; then [[ -S "$endpoint" ]];
  elif [[ "$endpoint" == *:* ]]; then
    port="${endpoint##*:}"
    ss -lntH 2>/dev/null | awk -v p=":$port" '$4 ~ p"$" {found=1} END{exit !found}'
  else return 1; fi
}
ensure_php_fpm(){
  local version="$1" endpoint attempt unit="php${version}-fpm.service"
  [[ -x "/usr/sbin/php-fpm${version}" ]] || error "PHP-FPM $version is not installed."
  install -d -o www-data -g www-data -m 0755 /run/php
  "/usr/sbin/php-fpm${version}" -tt >/dev/null 2>&1 || error "PHP-FPM $version configuration is invalid."
  systemctl daemon-reload
  systemctl unmask "$unit" >/dev/null 2>&1 || true
  systemctl enable "$unit" >/dev/null 2>&1 || true
  systemctl restart "$unit"
  for attempt in {1..12}; do
    endpoint="$(php_fpm_listen_value "$version")"
    if systemctl is-active --quiet "$unit" && [[ -n "$endpoint" ]] && endpoint_exists "$endpoint"; then printf '%s' "$endpoint"; return 0; fi
    sleep 1
  done
  systemctl status "$unit" --no-pager -l >&2 || true
  journalctl -u "$unit" -n 30 --no-pager >&2 || true
  error "PHP-FPM $version did not create a usable endpoint."
}
available_php_versions(){
  local dir version endpoint
  shopt -s nullglob
  for dir in /etc/php/*/fpm; do
    version="${dir#/etc/php/}"; version="${version%/fpm}"
    [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]] || continue
    endpoint="$(php_fpm_listen_value "$version")"
    if systemctl is-active --quiet "php${version}-fpm" && [[ -n "$endpoint" ]] && endpoint_exists "$endpoint"; then printf '%s\n' "$version"; fi
  done | sort -Vru
  shopt -u nullglob
}
choose_php_version(){
  local -a versions=(); local selection index
  mapfile -t versions < <(available_php_versions)
  [[ ${#versions[@]} -gt 0 ]] || error "No active PHP-FPM version was found."
  if [[ ${#versions[@]} -eq 1 ]]; then php_version="${versions[0]}"; return; fi
  echo "Available PHP-FPM versions:"
  for index in "${!versions[@]}"; do printf '  %d) PHP %s\n' "$((index+1))" "${versions[$index]}"; done
  while true; do
    read -r -p "Select PHP [1-${#versions[@]}]: " selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && ((selection>=1 && selection<=${#versions[@]})); then php_version="${versions[$((selection-1))]}"; return; fi
    echo "Invalid selection."
  done
}
usage(){ cat <<'TXT'
Usage:
  super-sdomain <domain> [php-version]
  super-sdomain --list-php

SSL uses the same email/no-email mode stored by the main installer.
TXT
}
case "${1:-}" in -h|--help) usage; exit 0;; --list-php) available_php_versions; exit 0;; esac

domain="${1:-}"; php_version="${2:-}"
[[ -n "$domain" ]] || read -r -p "Domain: " domain
validate_domain "$domain" || error "Invalid domain."
[[ -n "$php_version" ]] || choose_php_version
endpoint="$(ensure_php_fpm "$php_version")"
[[ ! -e "/var/www/html/$domain" ]] || error "Document root already exists."
primary_domain="$(read_info_value 'Primary Domain' || true)"
ssl_mode="$(read_info_value 'SSL Registration Mode' || true)"
ssl_email="$(read_info_value 'SSL Email' || true)"
[[ "$ssl_mode" == "no-email" ]] || ssl_mode="email"

mkdir -p "/var/www/html/$domain"
install -m 0644 "$SHARED_ASSET_DIR/index.php" "/var/www/html/$domain/index.php"
install -m 0644 "$SHARED_ASSET_DIR/ApacheExample.conf" "/etc/apache2/sites-available/$domain.conf"
sed -i "s/primary.example.com/${primary_domain:-$domain}/g; s/example.com/$domain/g; s/phpversion/$php_version/g" \
  "/var/www/html/$domain/index.php" "/etc/apache2/sites-available/$domain.conf"
if [[ "$endpoint" == /* ]]; then handler="proxy:unix:$endpoint|fcgi://localhost/"; else handler="proxy:fcgi://$endpoint/"; fi
sed -i -E "s#SetHandler \"[^\"]+\"#SetHandler \"$handler\"#" "/etc/apache2/sites-available/$domain.conf"
chown -R www-data:www-data "/var/www/html/$domain"
find "/var/www/html/$domain" -type d -exec chmod 755 {} +
find "/var/www/html/$domain" -type f -exec chmod 644 {} +
a2enmod proxy proxy_fcgi setenvif rewrite headers ssl http2 >/dev/null
a2ensite "$domain.conf" >/dev/null
apache2ctl configtest
systemctl reload apache2

ssl_active=false
if command -v certbot >/dev/null 2>&1; then
  certbot_args=(--apache --non-interactive --agree-tos --redirect -d "$domain")
  if [[ "$ssl_mode" == "email" && "$ssl_email" != "none" && -n "$ssl_email" ]]; then certbot_args+=(--email "$ssl_email"); else certbot_args+=(--register-unsafely-without-email); fi
  certbot "${certbot_args[@]}" && ssl_active=true || true
fi
mkdir -p /root/SNYT; chmod 700 /root/SNYT; touch "$DOMAIN_LOG"; chmod 600 "$DOMAIN_LOG"
printf '%s | apache | PHP %s | endpoint %s | SSL %s\n' "$domain" "$php_version" "$endpoint" "$ssl_active" >> "$DOMAIN_LOG"
[[ "$ssl_active" == true ]] && echo "Domain added: https://$domain (PHP $php_version)" || echo "Domain added: http://$domain (PHP $php_version, SSL pending)"
