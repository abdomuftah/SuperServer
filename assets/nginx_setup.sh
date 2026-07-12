#!/usr/bin/env bash
set -Eeuo pipefail

REPO_RAW="https://raw.githubusercontent.com/abdomuftah/SuperServer/main"
error(){ echo "Error: $1 (line ${2:-?})" >&2; exit 1; }
trap 'error "Unexpected failure" "$LINENO"' ERR
[[ $EUID -eq 0 ]] || error "Run as root" "$LINENO"

fetch_asset(){
  local asset="$1" target="$2" local_file
  local_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$asset"
  if [[ -f "$local_file" ]]; then install -m 0644 "$local_file" "$target"; else curl -fsSL "$REPO_RAW/assets/$asset" -o "$target"; fi
}
validate_domain(){ [[ "$1" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]; }

domain="${1:-}"
php_version="${2:-$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")}"
email="${3:-}"
[[ -n "$domain" ]] || read -r -p "Domain: " domain
[[ -n "$email" ]] || read -r -p "Let's Encrypt email: " email
validate_domain "$domain" || error "Invalid domain" "$LINENO"
[[ "$email" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || error "Invalid email" "$LINENO"
[[ -S "/run/php/php${php_version}-fpm.sock" ]] || error "PHP-FPM $php_version is not running" "$LINENO"

mkdir -p "/var/www/html/$domain"
fetch_asset nginxIndex.php "/var/www/html/$domain/index.php"
fetch_asset nginxExample.conf "/etc/nginx/sites-available/$domain.conf"
sed -i "s/example.com/$domain/g; s/phpversion/$php_version/g" "/var/www/html/$domain/index.php" "/etc/nginx/sites-available/$domain.conf"
ln -sfn "/etc/nginx/sites-available/$domain.conf" "/etc/nginx/sites-enabled/$domain.conf"
nginx -t
systemctl reload nginx
chown -R www-data:www-data "/var/www/html/$domain"
find "/var/www/html/$domain" -type d -exec chmod 755 {} +
find "/var/www/html/$domain" -type f -exec chmod 644 {} +

public_ip="$(curl -4fsSL --max-time 10 https://api.ipify.org || true)"
dns_ips="$(getent ahostsv4 "$domain" | awk '{print $1}' | sort -u | tr '\n' ' ')"
if [[ -n "$dns_ips" && ( -z "$public_ip" || "$dns_ips" == *"$public_ip"* ) ]]; then
  certbot --nginx --non-interactive --agree-tos --redirect --email "$email" -d "$domain"
else
  echo "DNS is not pointing to this server. SSL skipped; run later: certbot --nginx -d $domain --redirect"
fi
printf '\nDomain added: https://%s\n' "$domain"
