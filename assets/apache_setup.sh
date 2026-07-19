#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

REPO_RAW="https://raw.githubusercontent.com/abdomuftah/SuperServer/main"
INFO_FILE="/root/SNYT/serverInfo.txt"
DOMAIN_LOG="/root/SNYT/domains.txt"
SHARED_ASSET_DIR="/usr/local/share/snyt-superserver"

error() {
    echo "Error: $1 (line ${2:-?})" >&2
    exit 1
}
trap 'error "Unexpected failure" "$LINENO"' ERR

[[ $EUID -eq 0 ]] || error "Run as root" "$LINENO"

usage() {
    cat <<'EOF'
Usage:
  super-sdomain <domain> [php-version]
  super-sdomain --list-php

Examples:
  super-sdomain app.example.com
  super-sdomain app.example.com 8.3

The Let's Encrypt email is read automatically from:
  /root/SNYT/serverInfo.txt
EOF
}

read_info_value() {
    local key="$1"
    [[ -r "$INFO_FILE" ]] || return 1
    awk -F': ' -v wanted="$key" '$1 == wanted { sub(/^[^:]+: /, ""); print; exit }' "$INFO_FILE"
}

fetch_asset() {
    local asset="$1"
    local target="$2"
    local local_file

    local_file="$SHARED_ASSET_DIR/$asset"
    if [[ ! -f "$local_file" ]]; then
        local_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$asset"
    fi

    if [[ -f "$local_file" ]]; then
        install -m 0644 "$local_file" "$target"
    else
        curl -fsSL --retry 3 "$REPO_RAW/assets/$asset" -o "$target"
        chmod 0644 "$target"
    fi
}

validate_domain() {
    [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$ ]]
}

validate_email() {
    [[ "$1" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]
}

available_php_versions() {
    local socket version
    shopt -s nullglob
    for socket in /run/php/php*-fpm.sock; do
        [[ -S "$socket" ]] || continue
        version="$(basename "$socket")"
        version="${version#php}"
        version="${version%-fpm.sock}"
        systemctl is-active --quiet "php${version}-fpm" || continue
        printf '%s\n' "$version"
    done | sort -Vru
    shopt -u nullglob
}

choose_php_version() {
    local versions=()
    local selection=""
    local index

    mapfile -t versions < <(available_php_versions)
    [[ ${#versions[@]} -gt 0 ]] || error "No running PHP-FPM sockets were found" "$LINENO"

    if [[ ${#versions[@]} -eq 1 ]]; then
        php_version="${versions[0]}"
        echo "Using the only installed PHP-FPM version: PHP $php_version"
        return
    fi

    echo "Available PHP-FPM versions:"
    for index in "${!versions[@]}"; do
        printf '  %d) PHP %s\n' "$((index + 1))" "${versions[$index]}"
    done

    while true; do
        read -r -p "Select PHP [1-${#versions[@]}]: " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] \
            && (( selection >= 1 && selection <= ${#versions[@]} )); then
            php_version="${versions[$((selection - 1))]}"
            return
        fi
        echo "Invalid selection."
    done
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ "${1:-}" == "--list-php" ]]; then
    available_php_versions
    exit 0
fi

domain="${1:-}"
php_version="${2:-}"
email="$(read_info_value 'SSL Email' || true)"
primary_domain="$(read_info_value 'Primary Domain' || true)"

[[ -n "$domain" ]] || read -r -p "Domain: " domain
validate_domain "$domain" || error "Invalid domain" "$LINENO"

if [[ -z "$php_version" ]]; then
    choose_php_version
fi
[[ "$php_version" =~ ^[0-9]+\.[0-9]+$ ]] || error "Invalid PHP version" "$LINENO"
[[ -S "/run/php/php${php_version}-fpm.sock" ]] \
    || error "PHP-FPM $php_version is not installed or running" "$LINENO"

validate_email "$email" || error "SSL Email is missing or invalid in $INFO_FILE" "$LINENO"
validate_domain "$primary_domain" || primary_domain="$domain"

if [[ -e "/var/www/html/$domain" ]]; then
    error "Document root already exists: /var/www/html/$domain" "$LINENO"
fi

mkdir -p "/var/www/html/$domain"
fetch_asset index.php "/var/www/html/$domain/index.php"
fetch_asset ApacheExample.conf "/etc/apache2/sites-available/$domain.conf"
sed -i "s/primary.example.com/$primary_domain/g; s/example.com/$domain/g; s/phpversion/$php_version/g" \
    "/var/www/html/$domain/index.php" "/etc/apache2/sites-available/$domain.conf"

chown -R www-data:www-data "/var/www/html/$domain"
find "/var/www/html/$domain" -type d -exec chmod 755 {} +
find "/var/www/html/$domain" -type f -exec chmod 644 {} +

a2enmod proxy proxy_fcgi setenvif rewrite headers ssl http2 >/dev/null
a2ensite "$domain.conf" >/dev/null
apache2ctl configtest
systemctl reload apache2

ssl_active=false
if command -v certbot >/dev/null 2>&1; then
    if certbot --apache --non-interactive --agree-tos --redirect \
        --email "$email" -d "$domain"; then
        ssl_active=true
    else
        echo "SSL is pending. Run later: certbot --apache --email $email -d $domain --redirect"
    fi
fi

mkdir -p /root/SNYT
chmod 700 /root/SNYT
touch "$DOMAIN_LOG"
chmod 600 "$DOMAIN_LOG"
printf '%s | apache | PHP %s | SSL %s | email %s\n' \
    "$domain" "$php_version" "$ssl_active" "$email" >> "$DOMAIN_LOG"

if [[ "$ssl_active" == true ]]; then
    printf '\nDomain added: https://%s (PHP %s)\n' "$domain" "$php_version"
else
    printf '\nDomain added: http://%s (PHP %s, SSL pending)\n' "$domain" "$php_version"
fi
