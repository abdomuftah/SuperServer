#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

REPO_RAW="https://raw.githubusercontent.com/abdomuftah/SuperServer/main"
DOMAIN_LOG="/root/SNYT/domains.txt"

error() {
    echo "Error: $1 (line ${2:-?})" >&2
    exit 1
}
trap 'error "Unexpected failure" "$LINENO"' ERR

[[ $EUID -eq 0 ]] || error "Run as root" "$LINENO"

fetch_asset() {
    local asset="$1"
    local target="$2"
    local local_file

    local_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$asset"
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
        printf '%s\n' "$version"
    done | sort -Vr
    shopt -u nullglob
}

choose_php_version() {
    local versions=()
    local selection=""
    local index

    mapfile -t versions < <(available_php_versions)
    [[ ${#versions[@]} -gt 0 ]] || error "No running PHP-FPM sockets were found" "$LINENO"

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

domain="${1:-}"
php_version="${2:-}"
email="${3:-}"

[[ -n "$domain" ]] || read -r -p "Domain: " domain
validate_domain "$domain" || error "Invalid domain" "$LINENO"

if [[ -z "$php_version" ]]; then
    choose_php_version
fi
[[ "$php_version" =~ ^[0-9]+\.[0-9]+$ ]] || error "Invalid PHP version" "$LINENO"
[[ -S "/run/php/php${php_version}-fpm.sock" ]] \
    || error "PHP-FPM $php_version is not running" "$LINENO"

[[ -n "$email" ]] || read -r -p "Let's Encrypt email: " email
validate_email "$email" || error "Invalid email" "$LINENO"

mkdir -p "/var/www/html/$domain"
fetch_asset nginxIndex.php "/var/www/html/$domain/index.php"
fetch_asset nginxExample.conf "/etc/nginx/sites-available/$domain.conf"
sed -i "s/example.com/$domain/g; s/phpversion/$php_version/g" \
    "/var/www/html/$domain/index.php" "/etc/nginx/sites-available/$domain.conf"

chown -R www-data:www-data "/var/www/html/$domain"
find "/var/www/html/$domain" -type d -exec chmod 755 {} +
find "/var/www/html/$domain" -type f -exec chmod 644 {} +

ln -sfn "/etc/nginx/sites-available/$domain.conf" "/etc/nginx/sites-enabled/$domain.conf"
nginx -t
systemctl reload nginx

ssl_active=false
if command -v certbot >/dev/null 2>&1; then
    if certbot --nginx --non-interactive --agree-tos --redirect \
        --email "$email" -d "$domain"; then
        ssl_active=true
    else
        echo "SSL is pending. Run later: certbot --nginx -d $domain --redirect"
    fi
fi

mkdir -p /root/SNYT
chmod 700 /root/SNYT
touch "$DOMAIN_LOG"
chmod 600 "$DOMAIN_LOG"
printf '%s | nginx | PHP %s | SSL %s\n' \
    "$domain" "$php_version" "$ssl_active" >> "$DOMAIN_LOG"

if [[ "$ssl_active" == true ]]; then
    printf '\nDomain added: https://%s (PHP %s)\n' "$domain" "$php_version"
else
    printf '\nDomain added: http://%s (PHP %s, SSL pending)\n' "$domain" "$php_version"
fi
