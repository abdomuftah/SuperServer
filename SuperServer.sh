#!/usr/bin/env bash
# SNYT SuperServer
# Supported: Ubuntu 22.04/24.04/26.04 and Debian 11/12/13

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="3.1.0"
REPO_RAW="https://raw.githubusercontent.com/abdomuftah/SuperServer/main"
INFO_DIR="/root/SNYT"
INFO_FILE="$INFO_DIR/serverInfo.txt"
LOG_FILE="/var/log/snyt-superserver.log"

RED='\033[1;31m'; GREEN='\033[1;32m'; BLUE='\033[1;34m'; MAGENTA='\033[1;35m'; YELLOW='\033[1;33m'; NC='\033[0m'

mkdir -p "$INFO_DIR"
chmod 700 "$INFO_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

trap 'display_error "Unexpected failure" "$LINENO"' ERR

display_error() {
    local message="${1:-Unknown error}" line="${2:-?}"
    echo -e "${RED}Error: ${message} at line ${line}${NC}" >&2
    echo "Review: $LOG_FILE" >&2
    exit 1
}

section() {
    echo -e "\n${GREEN}******************************************${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}******************************************${NC}"
}

require_root() {
    [[ $EUID -eq 0 ]] || display_error "Run this script as root" "$LINENO"
}

get_user_input() {
    local prompt="$1" input
    read -r -p "$prompt" input
    [[ -n "$input" ]] || display_error "Input cannot be empty" "$LINENO"
    printf '%s' "$input"
}

validate_domain() {
    [[ "$1" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]
}

validate_email() {
    [[ "$1" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]
}

generate_password() {
    # 28 characters, URL/shell friendly, cryptographically random.
    openssl rand -hex 18
}

safe_write_info() {
    local key="$1" value="$2"
    mkdir -p "$INFO_DIR"
    touch "$INFO_FILE"
    chmod 600 "$INFO_FILE"
    if grep -qF "${key}:" "$INFO_FILE" 2>/dev/null; then
        sed -i "s|^${key}:.*|${key}: ${value}|" "$INFO_FILE"
    else
        printf '%s: %s\n' "$key" "$value" >> "$INFO_FILE"
    fi
}

backup_file() {
    local file="$1"
    [[ -e "$file" ]] || return 0
    cp -a "$file" "${file}.snyt-backup-$(date +%Y%m%d-%H%M%S)"
}

fetch_asset() {
    local asset="$1" target="$2" local_file
    local_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/assets/$asset"
    if [[ -f "$local_file" ]]; then
        install -m 0644 "$local_file" "$target"
    else
        curl -fsSL "$REPO_RAW/assets/$asset" -o "$target"
    fi
}

check_release_url() {
    curl -fsI --connect-timeout 8 --max-time 15 "$1" >/dev/null 2>&1
}

add_launchpad_ppa_if_supported() {
    local ppa="$1" owner archive release_url
    [[ "$DISTRO_ID" == "ubuntu" ]] || return 1
    owner="${ppa#ppa:}"; owner="${owner%%/*}"
    archive="${ppa##*/}"
    release_url="https://ppa.launchpadcontent.net/${owner}/${archive}/ubuntu/dists/${VERSION_CODENAME}/Release"
    if check_release_url "$release_url"; then
        add-apt-repository -y "$ppa"
        return 0
    fi
    echo -e "${YELLOW}Skipping unsupported PPA $ppa for $VERSION_CODENAME; using distribution packages when possible.${NC}"
    return 1
}

configure_debian_sury_php() {
    [[ "$DISTRO_ID" == "debian" ]] || return 0
    local release_url="https://packages.sury.org/php/dists/${VERSION_CODENAME}/Release"
    if ! check_release_url "$release_url"; then
        echo -e "${YELLOW}Sury PHP does not publish $VERSION_CODENAME; using Debian PHP packages.${NC}"
        return 1
    fi
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://packages.sury.org/php/apt.gpg -o /etc/apt/keyrings/deb.sury.org-php.gpg
    chmod 0644 /etc/apt/keyrings/deb.sury.org-php.gpg
    echo "deb [signed-by=/etc/apt/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $VERSION_CODENAME main" > /etc/apt/sources.list.d/php-sury.list
}

detect_os() {
    [[ -r /etc/os-release ]] || display_error "/etc/os-release is missing" "$LINENO"
    # shellcheck disable=SC1091
    source /etc/os-release
    DISTRO_ID="${ID:-}"
    case "$DISTRO_ID" in
        ubuntu)
            case "${VERSION_ID:-}" in
                22.04|24.04|26.04) ;;
                *) display_error "Unsupported Ubuntu version: ${VERSION_ID:-unknown}. Supported: 22.04, 24.04, 26.04" "$LINENO" ;;
            esac
            ;;
        debian)
            case "${VERSION_ID:-}" in
                11|12|13) ;;
                *) display_error "Unsupported Debian version: ${VERSION_ID:-unknown}. Supported: 11, 12, 13" "$LINENO" ;;
            esac
            ;;
        *) display_error "Unsupported distribution: ${DISTRO_ID:-unknown}. Use Ubuntu or Debian." "$LINENO" ;;
    esac
    VERSION_CODENAME="${VERSION_CODENAME:-${DEBIAN_CODENAME:-}}"
    [[ -n "$VERSION_CODENAME" ]] || display_error "Could not detect distribution codename" "$LINENO"
    ARCH="$(dpkg --print-architecture)"
    safe_write_info "SuperServer Version" "$VERSION"
    safe_write_info "Installation Date" "$(date --iso-8601=seconds)"
    safe_write_info "Operating System" "$PRETTY_NAME"
    safe_write_info "Distribution" "$DISTRO_ID"
    safe_write_info "Distribution Codename" "$VERSION_CODENAME"
    safe_write_info "Architecture" "$ARCH"
    safe_write_info "Hostname" "$(hostname -f 2>/dev/null || hostname)"
}

choose_web_server() {
    echo "Choose web server:"
    select opt in apache nginx; do
        case "$opt" in apache|nginx) web_server="$opt"; break;; *) echo "Invalid option";; esac
    done
}

php_available() {
    apt-cache show "php$1-cli" >/dev/null 2>&1
}

choose_php_version() {
    echo "Choose PHP profile/version:"
    echo "1) Nextcloud (newest compatible available: prefers 8.4, then 8.3)"
    echo "2) General / Laravel (newest stable available)"
    echo "3) Legacy application (PHP 8.2)"
    echo "4) Choose manually"
    local choice
    read -r -p "Selection [1-4]: " choice
    case "$choice" in
        1)
            for v in 8.4 8.3 8.2; do php_available "$v" && { php_version="$v"; break; }; done
            ;;
        2)
            for v in 8.5 8.4 8.3 8.2; do php_available "$v" && { php_version="$v"; break; }; done
            ;;
        3) php_version="8.2" ;;
        4)
            read -r -p "PHP version (example 8.2): " php_version
            [[ "$php_version" =~ ^[0-9]+\.[0-9]+$ ]] || display_error "Invalid PHP version" "$LINENO"
            ;;
        *) display_error "Invalid PHP selection" "$LINENO" ;;
    esac
    [[ -n "${php_version:-}" ]] || display_error "No supported PHP package was found" "$LINENO"
    php_available "$php_version" || display_error "PHP $php_version is not available for this Ubuntu/repository combination" "$LINENO"
}

configure_unattended_upgrades() {
    section "Configuring automatic security updates"
    apt-get install -y unattended-upgrades apt-listchanges
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
CONF
    systemctl enable --now unattended-upgrades.service || true
}

install_fastfetch_motd() {
    section "Installing SNYT Fastfetch and MOTD"
    local api asset_url="" tmp="/tmp/fastfetch.deb" pattern
    apt-get install -y jq figlet
    case "$ARCH" in
        amd64) pattern='linux-amd64.deb$' ;;
        arm64) pattern='linux-aarch64.deb$' ;;
        *) pattern='' ;;
    esac
    if [[ -n "$pattern" ]]; then
        api="$(curl -fsSL https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest || true)"
        asset_url="$(jq -r --arg p "$pattern" '.assets[] | select(.name|test($p)) | .browser_download_url' <<<"$api" | head -n1)"
    fi
    if [[ -n "$asset_url" && "$asset_url" != "null" ]]; then
        curl -fsSL "$asset_url" -o "$tmp"
        apt-get install -y "$tmp" || dpkg -i "$tmp" || apt-get -f install -y
        rm -f "$tmp"
    else
        apt-get install -y fastfetch || echo "Fastfetch package unavailable; MOTD will use standard system information."
    fi

    mkdir -p /etc/snyt
    cat > /etc/snyt/fastfetch.jsonc <<'JSON'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": { "type": "small", "padding": { "top": 1, "right": 2 } },
  "display": { "separator": "  ➜  " },
  "modules": [
    { "type": "title", "format": "SNYT Hosting • {user-name}@{host-name}" },
    "separator", "os", "host", "kernel", "uptime", "packages", "shell", "terminal",
    "cpu", "memory", "swap", "disk", "localip", "break", "colors"
  ]
}
JSON
    cat > /etc/update-motd.d/01-snyt <<'MOTD'
#!/usr/bin/env bash
printf '\n'
if command -v figlet >/dev/null 2>&1; then figlet -f slant SNYT 2>/dev/null; else echo '=== SNYT Hosting ==='; fi
printf 'Managed by SNYT SuperServer\n\n'
if command -v fastfetch >/dev/null 2>&1; then fastfetch --config /etc/snyt/fastfetch.jsonc; fi
printf '\n'
MOTD
    chmod +x /etc/update-motd.d/01-snyt
}

install_certbot() {
    section "Installing Certbot and automatic renewal"
    if [[ "$web_server" == apache ]]; then
        apt-get install -y certbot python3-certbot-apache
    else
        apt-get install -y certbot python3-certbot-nginx
    fi
    systemctl enable --now certbot.timer 2>/dev/null || true
}

configure_ssl() {
    section "Configuring Let's Encrypt SSL"
    local public_ip dns_ips
    public_ip="$(curl -4fsSL --max-time 10 https://api.ipify.org || true)"
    dns_ips="$(getent ahostsv4 "$domain" | awk '{print $1}' | sort -u | tr '\n' ' ')"
    if [[ -z "$dns_ips" || ( -n "$public_ip" && "$dns_ips" != *"$public_ip"* ) ]]; then
        echo -e "${YELLOW}DNS for $domain does not resolve to this server yet. SSL issuance skipped.${NC}"
        safe_write_info "SSL Status" "Pending DNS; run: certbot --$web_server -d $domain --redirect"
        return 0
    fi
    if [[ "$web_server" == apache ]]; then
        certbot --apache --non-interactive --agree-tos --redirect --email "$email" -d "$domain"
    else
        certbot --nginx --non-interactive --agree-tos --redirect --email "$email" -d "$domain"
    fi
    certbot renew --dry-run || echo -e "${YELLOW}Certbot dry-run failed; inspect $LOG_FILE.${NC}"
    safe_write_info "SSL Status" "Active with automatic renewal"
}

configure_phpmyadmin() {
    section "Installing and securing phpMyAdmin"
    pma_app_password="$(generate_password)"
    export DEBIAN_FRONTEND=noninteractive
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/mysql/app-pass password $pma_app_password" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/app-password-confirm password $pma_app_password" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect none" | debconf-set-selections
    apt-get install -y phpmyadmin

    if [[ "$web_server" == apache ]]; then
        [[ -e /etc/apache2/conf-enabled/phpmyadmin.conf ]] || ln -s /etc/phpmyadmin/apache.conf /etc/apache2/conf-enabled/phpmyadmin.conf
        apache2ctl configtest
        systemctl reload apache2
    else
        cat > /etc/nginx/snippets/phpmyadmin.conf <<'EOF_PMA'
location /phpmyadmin {
    root /usr/share/;
    index index.php index.html index.htm;
    location ~ ^/phpmyadmin/(.+\.php)$ {
        try_files $uri =404;
        root /usr/share/;
        fastcgi_pass unix:/run/php/phpPHPVERSION-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
    location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))$ { root /usr/share/; }
}
EOF_PMA
        sed -i "s/PHPVERSION/$php_version/g" /etc/nginx/snippets/phpmyadmin.conf
        grep -q 'snippets/phpmyadmin.conf' "/etc/nginx/sites-available/$domain.conf" || sed -i '/server_name/a\\    include snippets/phpmyadmin.conf;' "/etc/nginx/sites-available/$domain.conf"
        nginx -t && systemctl reload nginx
    fi
    safe_write_info "phpMyAdmin URL" "https://$domain/phpmyadmin"
    safe_write_info "phpMyAdmin Database App Password" "$pma_app_password"
}

configure_mariadb() {
    section "Installing and securing MariaDB"
    apt-get install -y mariadb-server mariadb-client
    systemctl enable --now mariadb
    mysql_admin_user="snyt_admin"
    mysql_admin_password="$(generate_password)"
    mysql --protocol=socket <<SQL
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
CREATE USER IF NOT EXISTS '${mysql_admin_user}'@'localhost' IDENTIFIED BY '${mysql_admin_password}';
ALTER USER '${mysql_admin_user}'@'localhost' IDENTIFIED BY '${mysql_admin_password}';
GRANT ALL PRIVILEGES ON *.* TO '${mysql_admin_user}'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
    safe_write_info "MariaDB Root Authentication" "unix_socket (use: sudo mariadb)"
    safe_write_info "MariaDB Admin User" "$mysql_admin_user"
    safe_write_info "MariaDB Admin Password" "$mysql_admin_password"
    safe_write_info "MariaDB Version" "$(mariadb --version | head -n1)"
}

configure_firewall() {
    section "Configuring UFW firewall"
    ufw default deny incoming
    ufw default allow outgoing
    if ufw app info OpenSSH >/dev/null 2>&1; then
        ufw allow OpenSSH
    else
        ufw allow 22/tcp
    fi
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
}

configure_fail2ban() {
    section "Installing and configuring Fail2ban"
    apt-get install -y fail2ban
    if [[ "$web_server" == apache ]]; then
        fetch_asset Apachejail.local /etc/fail2ban/jail.local
    else
        fetch_asset Nginxjail.local /etc/fail2ban/jail.local
    fi
    systemctl enable --now fail2ban
    fail2ban-client ping
}

require_root
detect_os
clear
echo -e "${BLUE}**********************************************${NC}"
echo -e "${BLUE}*          SNYT SuperServer Setup            *${NC}"
echo -e "${BLUE}*                  v$VERSION                   *${NC}"
echo -e "${BLUE}**********************************************${NC}"
echo "Detected: $PRETTY_NAME ($VERSION_CODENAME / $ARCH)"
echo

domain="$(get_user_input 'Set Web Domain (example.com): ')"
validate_domain "$domain" || display_error "Invalid domain format" "$LINENO"
email="$(get_user_input "Email for Let's Encrypt SSL: ")"
validate_email "$email" || display_error "Invalid email format" "$LINENO"
choose_web_server

section "Updating system packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get dist-upgrade -y
apt-get autoremove -y
base_packages=(
    ca-certificates curl wget gnupg lsb-release software-properties-common dialog openssl jq
    screen nano git zip unzip ufw default-jdk python3 python3-dev python3-pip gcc g++ make composer
)
if apt-cache show default-libmysqlclient-dev >/dev/null 2>&1; then
    base_packages+=(default-libmysqlclient-dev)
elif apt-cache show libmysqlclient-dev >/dev/null 2>&1; then
    base_packages+=(libmysqlclient-dev)
fi
apt-get install -y "${base_packages[@]}"

section "Configuring current repositories"
if [[ "$DISTRO_ID" == "ubuntu" ]]; then
    add_launchpad_ppa_if_supported ppa:ondrej/php || true
    if [[ "$web_server" == apache ]]; then
        add_launchpad_ppa_if_supported ppa:ondrej/apache2 || true
    else
        add_launchpad_ppa_if_supported ppa:ondrej/nginx-mainline || true
    fi
else
    configure_debian_sury_php || true
fi
# Redis official repository; fall back to Ubuntu if the current codename is not published.
if check_release_url "https://packages.redis.io/deb/dists/$VERSION_CODENAME/Release"; then
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    chmod 644 /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $VERSION_CODENAME main" > /etc/apt/sources.list.d/redis.list
else
    echo -e "${YELLOW}Redis upstream repository does not publish $VERSION_CODENAME yet; using the distribution Redis package.${NC}"
fi
apt-get update
choose_php_version

section "Installing $web_server"
if [[ "$web_server" == apache ]]; then
    apt-get install -y apache2
    systemctl enable --now apache2
else
    apt-get install -y nginx
    systemctl enable --now nginx
fi
install_certbot

configure_mariadb

section "Installing PHP $php_version and extensions"
php_packages=(
    "php$php_version" "php$php_version-cli" "php$php_version-common" "php$php_version-fpm"
    "php$php_version-curl" "php$php_version-mysql" "php$php_version-redis" "php$php_version-sqlite3"
    "php$php_version-intl" "php$php_version-gd" "php$php_version-mbstring" "php$php_version-xml"
    "php$php_version-zip" "php$php_version-bcmath" "php$php_version-soap" "php$php_version-bz2"
    "php$php_version-imagick" "php$php_version-tidy" "php$php_version-opcache"
)
available_php_packages=()
missing_php_packages=()
for package in "${php_packages[@]}"; do
    if apt-cache show "$package" >/dev/null 2>&1; then
        available_php_packages+=("$package")
    else
        missing_php_packages+=("$package")
    fi
done
[[ ${#available_php_packages[@]} -gt 0 ]] || display_error "No PHP $php_version packages are available" "$LINENO"
apt-get install -y "${available_php_packages[@]}"
if [[ ${#missing_php_packages[@]} -gt 0 ]]; then
    echo -e "${YELLOW}Optional PHP packages unavailable and skipped: ${missing_php_packages[*]}${NC}"
fi
update-alternatives --set php "/usr/bin/php$php_version"
systemctl enable --now "php$php_version-fpm"
if [[ "$web_server" == apache ]]; then
    a2dismod "php$php_version" 2>/dev/null || true
    a2enmod proxy_fcgi setenvif rewrite headers ssl http2
    a2enconf "php$php_version-fpm"
fi

section "Applying PHP configuration"
for sapi in cli fpm apache2; do
    ini="/etc/php/$php_version/$sapi/php.ini"
    [[ -f "$ini" ]] || continue
    backup_file "$ini"
    fetch_asset php.ini "$ini"
done
systemctl restart "php$php_version-fpm"

section "Creating website for $domain"
mkdir -p "/var/www/html/$domain"
if [[ "$web_server" == apache ]]; then
    fetch_asset ApacheIndex.php "/var/www/html/$domain/index.php"
    fetch_asset ApacheExample.conf "/etc/apache2/sites-available/$domain.conf"
    sed -i "s/example.com/$domain/g" "/var/www/html/$domain/index.php" "/etc/apache2/sites-available/$domain.conf"
    a2dissite 000-default.conf 2>/dev/null || true
    a2ensite "$domain.conf"
    apache2ctl configtest
    systemctl reload apache2
else
    fetch_asset nginxIndex.php "/var/www/html/$domain/index.php"
    fetch_asset nginxExample.conf "/etc/nginx/sites-available/$domain.conf"
    sed -i "s/example.com/$domain/g; s/phpversion/$php_version/g" "/var/www/html/$domain/index.php" "/etc/nginx/sites-available/$domain.conf"
    ln -sfn "/etc/nginx/sites-available/$domain.conf" "/etc/nginx/sites-enabled/$domain.conf"
    rm -f /etc/nginx/sites-enabled/default
    nginx -t
    systemctl reload nginx
fi
chown -R www-data:www-data "/var/www/html/$domain"
find "/var/www/html/$domain" -type d -exec chmod 755 {} +
find "/var/www/html/$domain" -type f -exec chmod 644 {} +

configure_phpmyadmin

section "Installing Python tools"
python3 -m pip install --upgrade pip --break-system-packages
python3 -m pip install --upgrade Django --break-system-packages
[[ -e /usr/local/bin/python ]] || ln -s "$(command -v python3)" /usr/local/bin/python

section "Installing current Node.js LTS and PM2"
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs
npm install -g pm2@latest
pm2 startup systemd -u root --hp /root >/tmp/snyt-pm2-startup.txt 2>&1 || true

section "Installing Redis"
if apt-cache show redis >/dev/null 2>&1; then
    apt-get install -y redis
else
    apt-get install -y redis-server redis-tools
fi
if systemctl list-unit-files | grep -q '^redis-server.service'; then
    systemctl enable --now redis-server
else
    systemctl enable --now redis
fi
redis-cli ping | grep -q PONG

configure_firewall
configure_fail2ban
configure_unattended_upgrades
install_fastfetch_motd
configure_ssl

section "Installing add-domain helper"
if [[ "$web_server" == apache ]]; then
    fetch_asset apache_setup.sh /usr/local/sbin/super-sdomain
else
    fetch_asset nginx_setup.sh /usr/local/sbin/super-sdomain
fi
chmod 700 /usr/local/sbin/super-sdomain
ln -sfn /usr/local/sbin/super-sdomain /root/super-sdomain.sh

safe_write_info "Primary Domain" "$domain"
safe_write_info "Web Server" "$web_server"
safe_write_info "Web Server Version" "$(if [[ $web_server == apache ]]; then apache2 -v | head -n1; else nginx -v 2>&1; fi)"
safe_write_info "PHP Version" "$(php -v | head -n1)"
safe_write_info "PHP-FPM Socket" "/run/php/php${php_version}-fpm.sock"
safe_write_info "Redis Version" "$(redis-server --version)"
safe_write_info "Node.js Version" "$(node --version)"
safe_write_info "Python Version" "$(python3 --version)"
safe_write_info "Credentials File" "$INFO_FILE (permissions 600)"
chmod 600 "$INFO_FILE"

clear
echo -e "${MAGENTA}=========================================${NC}"
echo -e "${MAGENTA}SNYT SuperServer $VERSION installation completed${NC}"
echo -e "${MAGENTA}System: $PRETTY_NAME${NC}"
echo -e "${MAGENTA}Web: https://$domain${NC}"
echo -e "${MAGENTA}PHP: $php_version | Server: $web_server${NC}"
echo -e "${MAGENTA}Credentials: $INFO_FILE${NC}"
echo -e "${MAGENTA}Log: $LOG_FILE${NC}"
echo -e "${MAGENTA}Add a domain: super-sdomain${NC}"
echo -e "${MAGENTA}=========================================${NC}"
