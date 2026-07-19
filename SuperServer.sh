#!/usr/bin/env bash
# ==============================================================================
# SNYT SuperServer
# A single-file Ubuntu/Debian web-server installer maintained by SNYT Hosting.
# Supported: Ubuntu 22.04/24.04/26.04 and Debian 11/12/13
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

SUPERSERVER_VERSION="3.5.1"
REPO_RAW="https://raw.githubusercontent.com/abdomuftah/SuperServer/main"
INFO_DIR="/root/SNYT"
INFO_FILE="$INFO_DIR/serverInfo.txt"
LOG_FILE="/var/log/snyt-superserver.log"
STATE_FILE="$INFO_DIR/.superserver-installed"

RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

FORCE_INSTALL=false
SSL_ACTIVE=false
web_server=""
php_version=""
domain=""
email=""
SSH_PORT="22"
REDIS_UNIT=""
mysql_admin_user="snyt_admin"
mysql_admin_password=""
pma_app_password=""

# v3.5 wizard choices. All are collected before package installation starts.
SSL_MODE="email"
PHP_MODULE_PROFILE="essential"
PHP_SELECTED_MODULES=()
PHP_SKIPPED_PACKAGES=()
INSTALL_MARIADB=true
INSTALL_PHPMYADMIN=true
INSTALL_REDIS=true
INSTALL_COMPOSER=true
INSTALL_NODEJS=true
INSTALL_PM2=true
INSTALL_PYTHON=true
INSTALL_JAVA=false
INSTALL_DOCKER=false
INSTALL_UNATTENDED=true
INSTALL_MOTD=true
SECURITY_MODE="crowdsec-firewall"
INSTALL_PLAN_FILE="$INFO_DIR/install-plan.conf"

PHP_VERSION_CANDIDATES=(8.1 8.2 8.3 8.4 8.5)
PHP_CORE_SUFFIXES=(cli common fpm)
PHP_ESSENTIAL_MODULES=(curl mysql mbstring xml zip intl gd bcmath opcache readline)
PHP_ALL_MODULES=(
  curl mysql mbstring xml zip intl gd bcmath opcache readline
  redis sqlite3 soap bz2 imagick tidy xmlrpc gmp ldap imap snmp apcu
)
AVAILABLE_PHP_VERSIONS=()
UNAVAILABLE_PHP_VERSIONS=()
PHP_SELECTED_VERSIONS=()
PHP_SELECTION_ERROR=""

declare -A PHP_FPM_LISTEN=()
PHP_REPOSITORY_PROVIDER="unconfigured"
MARIADB_INSTALL_PROVIDER="distribution"
REDIS_INSTALL_PROVIDER="not-selected"
NODE_INSTALL_PROVIDER="not-selected"
DOCKER_INSTALL_PROVIDER="not-selected"
CERTBOT_INSTALL_PROVIDER="unconfigured"
COMPOSER_INSTALL_PROVIDER="not-selected"
CROWDSEC_INSTALL_PROVIDER="not-selected"

usage() {
  cat <<EOF
SNYT SuperServer v$SUPERSERVER_VERSION

Usage:
  sudo ./SuperServer.sh [option]

Options:
  --force      Allow execution when a previous SuperServer installation is found.
               This does not permit changing between Apache and Nginx in place.
  --version    Print the installer version and exit.
  -h, --help   Show this help screen.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --force) FORCE_INSTALL=true ;;
    --version) echo "$SUPERSERVER_VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Error: run SuperServer as root (sudo -i)." >&2
  exit 1
fi

mkdir -p "$INFO_DIR"
chmod 700 "$INFO_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

on_error() {
  local exit_code=$?
  local line="${1:-?}"
  local command="${2:-unknown}"

  echo -e "\n${RED}${BOLD}SuperServer stopped because a command failed.${NC}" >&2
  echo -e "${RED}Line:${NC} $line" >&2
  echo -e "${RED}Command:${NC} $command" >&2
  echo -e "${RED}Exit code:${NC} $exit_code" >&2
  echo -e "Review the log: ${BOLD}$LOG_FILE${NC}" >&2
  exit "$exit_code"
}
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

info() { echo -e "${CYAN}ℹ${NC} $*"; }
ok() { echo -e "${GREEN}✔${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
fatal() {
  echo -e "${RED}✖ $*${NC}" >&2
  echo "Review: $LOG_FILE" >&2
  exit 1
}

join_by() {
  local delimiter="$1"
  shift
  local result=""
  local item

  for item in "$@"; do
    if [[ -n "$result" ]]; then
      result+="$delimiter"
    fi
    result+="$item"
  done
  printf '%s' "$result"
}

section() {
  echo
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}${BOLD}  $1${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_banner() {
  clear || true
  local width=70

  echo -e "${BLUE}${BOLD}"
  cat <<'BANNER'
   _____ _   ___   _________   _____                        
  / ___// | / / | / /_  __/  / ___/___  ______   _____  _____
  \__ \/  |/ /  |/ / / /     \__ \/ _ \/ ___/ | / / _ \/ ___/
 ___/ / /|  / /|  / / /     ___/ /  __/ /   | |/ /  __/ /    
/____/_/ |_/_/ |_/ /_/     /____/\___/_/    |___/\___/_/     
BANNER
  echo -e "${NC}"
  echo -e "${MAGENTA}╭────────────────────────────────────────────────────────────────────╮${NC}"
  echo -e "${MAGENTA}│${NC}  ${BOLD}Deploy • Secure • Validate${NC}                                       ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}├────────────────────────────────────────────────────────────────────┤${NC}"
  printf "${MAGENTA}│${NC}  %-66s${MAGENTA}│${NC}\n" "Version : $SUPERSERVER_VERSION"
  printf "${MAGENTA}│${NC}  %-66s${MAGENTA}│${NC}\n" "System  : $PRETTY_NAME ($VERSION_CODENAME / $ARCH)"
  printf "${MAGENTA}│${NC}  %-66s${MAGENTA}│${NC}\n" "SSH     : port $SSH_PORT"
  echo -e "${MAGENTA}├────────────────────────────────────────────────────────────────────┤${NC}"
  echo -e "${MAGENTA}│${NC}  This wizard installs Apache or Nginx, Multi-PHP FPM, MariaDB, ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}│${NC}  Redis, SSL, development tools, firewall and server hardening. ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}│${NC}                                                                    ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}│${NC}  Credentials are generated automatically and stored privately in: ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}│${NC}  ${CYAN}/root/SNYT/serverInfo.txt${NC}                                      ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}╰────────────────────────────────────────────────────────────────────╯${NC}"
  echo
}

prompt_nonempty() {
  local prompt="$1"
  local input=""
  while [[ -z "$input" ]]; do
    read -r -p "$prompt" input
    [[ -n "$input" ]] || echo -e "${YELLOW}⚠${NC} This value cannot be empty." >&2
  done
  printf '%s' "$input"
}

confirm() {
  local prompt="${1:-Continue?}"
  local default="${2:-Y}"
  local answer=""

  if [[ "$default" == "Y" ]]; then
    read -r -p "$prompt [Y/n]: " answer
    answer="${answer:-Y}"
  else
    read -r -p "$prompt [y/N]: " answer
    answer="${answer:-N}"
  fi

  [[ "$answer" =~ ^[Yy]$ ]]
}

validate_domain() {
  [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$ ]]
}

validate_email() {
  [[ "$1" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]
}

generate_password() {
  # 36 URL/shell-friendly hexadecimal characters from a cryptographic RNG.
  openssl rand -hex 18
}

safe_write_info() {
  local key="$1"
  local value="$2"
  local tmp

  mkdir -p "$INFO_DIR"
  touch "$INFO_FILE"
  chmod 600 "$INFO_FILE"
  tmp="$(mktemp)"

  awk -F': ' -v wanted="$key" '$1 != wanted { print }' "$INFO_FILE" > "$tmp"
  printf '%s: %s\n' "$key" "$value" >> "$tmp"
  install -m 0600 "$tmp" "$INFO_FILE"
  rm -f "$tmp"
}

backup_file() {
  local file="$1"
  [[ -e "$file" ]] || return 0
  cp -a "$file" "${file}.snyt-backup-$(date +%Y%m%d-%H%M%S)"
}

fetch_asset() {
  local asset="$1"
  local target="$2"
  local mode="${3:-0644}"
  local local_file

  local_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/assets/$asset"
  mkdir -p "$(dirname "$target")"

  if [[ -f "$local_file" ]]; then
    install -m "$mode" "$local_file" "$target"
  else
    curl -fsSL --retry 3 --connect-timeout 10 "$REPO_RAW/assets/$asset" -o "$target"
    chmod "$mode" "$target"
  fi
}

package_has_candidate() {
  local package="$1"
  local candidate
  candidate="$(apt-cache policy "$package" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
  [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

check_release_url() {
  curl -fsSL --retry 2 --connect-timeout 8 --max-time 20 "$1" -o /dev/null >/dev/null 2>&1
}

detect_os() {
  [[ -r /etc/os-release ]] || fatal "/etc/os-release is missing."
  # shellcheck disable=SC1091
  source /etc/os-release

  DISTRO_ID="${ID:-}"
  case "$DISTRO_ID" in
    ubuntu)
      case "${VERSION_ID:-}" in
        22.04|24.04|26.04) ;;
        *) fatal "Unsupported Ubuntu version: ${VERSION_ID:-unknown}. Supported: 22.04, 24.04, 26.04." ;;
      esac
      ;;
    debian)
      case "${VERSION_ID:-}" in
        11|12|13) ;;
        *) fatal "Unsupported Debian version: ${VERSION_ID:-unknown}. Supported: 11, 12, 13." ;;
      esac
      ;;
    *) fatal "Unsupported distribution: ${DISTRO_ID:-unknown}. Use Ubuntu or Debian." ;;
  esac

  VERSION_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-${DEBIAN_CODENAME:-}}}"
  [[ -n "$VERSION_CODENAME" ]] || fatal "Could not detect the distribution codename."
  ARCH="$(dpkg --print-architecture)"

  safe_write_info "SuperServer Version" "$SUPERSERVER_VERSION"
  safe_write_info "Installation Date" "$(date --iso-8601=seconds)"
  safe_write_info "Operating System" "$PRETTY_NAME"
  safe_write_info "Distribution" "$DISTRO_ID"
  safe_write_info "Distribution Codename" "$VERSION_CODENAME"
  safe_write_info "Architecture" "$ARCH"
  safe_write_info "Hostname" "$(hostname -f 2>/dev/null || hostname)"
}

detect_ssh_port() {
  local detected=""

  if command -v sshd >/dev/null 2>&1; then
    detected="$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2; exit}' || true)"
  fi

  if [[ -z "$detected" ]]; then
    detected="$(
      grep -RhsE '^[[:space:]]*Port[[:space:]]+[0-9]+' \
        /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null \
        | tail -n1 | awk '{print $2}' || true
    )"
  fi

  SSH_PORT="${detected:-22}"
  [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || SSH_PORT="22"
  safe_write_info "SSH Port" "$SSH_PORT"
}

check_previous_installation() {
  if [[ -f "$STATE_FILE" && "$FORCE_INSTALL" != true ]]; then
    fatal "A completed SuperServer installation already exists. Use --force only after taking a snapshot or backup."
  fi
}

choose_web_server() {
  local choice=""

  echo -e "${BOLD}Choose your web server${NC}"
  echo
  echo -e "  ${BLUE}1) Apache${NC}"
  echo "     Best for WordPress, .htaccess, shared-style websites and compatibility."
  echo
  echo -e "  ${BLUE}2) Nginx${NC}"
  echo "     Best for reverse proxies, Docker applications and a lightweight stack."
  echo

  while true; do
    read -r -p "Selection [1-2]: " choice
    case "$choice" in
      1) web_server="apache" ;;
      2) web_server="nginx" ;;
      *) warn "Enter 1 for Apache or 2 for Nginx."; continue ;;
    esac

    echo
    info "Selected web server: ${web_server^}"
    if confirm "Use ${web_server^}?" "Y"; then
      break
    fi
    echo
  done

  safe_write_info "Web Server Selection" "$web_server"
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$'
}

check_web_server_conflict() {
  if [[ "$web_server" == "apache" ]] && package_installed nginx; then
    fatal "Nginx is already installed. SuperServer will not remove or replace an existing web server automatically."
  fi

  if [[ "$web_server" == "nginx" ]] && package_installed apache2; then
    fatal "Apache is already installed. SuperServer will not remove or replace an existing web server automatically."
  fi
}

php_version_complete() {
  local version="$1"
  local suffix

  for suffix in "${PHP_CORE_SUFFIXES[@]}"; do
    package_has_candidate "php${version}-${suffix}" || return 1
  done
  return 0
}

php_missing_core_packages() {
  local version="$1"
  local suffix package
  local missing=()

  for suffix in "${PHP_CORE_SUFFIXES[@]}"; do
    package="php${version}-${suffix}"
    package_has_candidate "$package" || missing+=("$package")
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    printf 'none'
  else
    printf '%s ' "${missing[@]}"
  fi
}

discover_php_versions() {
  local version
  AVAILABLE_PHP_VERSIONS=()
  UNAVAILABLE_PHP_VERSIONS=()

  for version in "${PHP_VERSION_CANDIDATES[@]}"; do
    if php_version_complete "$version"; then
      AVAILABLE_PHP_VERSIONS+=("$version")
    else
      UNAVAILABLE_PHP_VERSIONS+=("$version")
    fi
  done

  if [[ ${#AVAILABLE_PHP_VERSIONS[@]} -eq 0 ]]; then
    warn "PHP package diagnostics:"
    for version in "${PHP_VERSION_CANDIDATES[@]}"; do
      echo "  PHP $version missing: $(php_missing_core_packages "$version")"
    done
    fatal "No installable PHP version was found for this operating system and its enabled repositories."
  fi
}

php_candidate_is_available() {
  local wanted="$1"
  local version

  for version in "${AVAILABLE_PHP_VERSIONS[@]}"; do
    [[ "$version" == "$wanted" ]] && return 0
  done
  return 1
}

record_provider() {
  local component="$1" provider="$2"
  case "$component" in
    PHP) PHP_REPOSITORY_PROVIDER="$provider" ;;
    MariaDB) MARIADB_INSTALL_PROVIDER="$provider" ;;
    Redis) REDIS_INSTALL_PROVIDER="$provider" ;;
    Node.js) NODE_INSTALL_PROVIDER="$provider" ;;
    Docker) DOCKER_INSTALL_PROVIDER="$provider" ;;
    Certbot) CERTBOT_INSTALL_PROVIDER="$provider" ;;
    Composer) COMPOSER_INSTALL_PROVIDER="$provider" ;;
    CrowdSec) CROWDSEC_INSTALL_PROVIDER="$provider" ;;
  esac
  info "$component source: $provider"
}

apt_update_retry() {
  local attempt
  for attempt in 1 2 3; do
    if apt-get update; then
      return 0
    fi
    warn "APT update failed (attempt $attempt/3). Retrying in 4 seconds."
    sleep 4
  done
  return 1
}

selected_php_versions_available() {
  local version
  discover_php_versions
  for version in "${PHP_SELECTED_VERSIONS[@]}"; do
    php_candidate_is_available "$version" || return 1
  done
  return 0
}

remove_superserver_php_sources() {
  rm -f \
    /etc/apt/sources.list.d/php.list \
    /etc/apt/sources.list.d/snyt-php*.list \
    /etc/apt/sources.list.d/php-sury.list \
    /etc/apt/preferences.d/snyt-php-provider \
    /etc/apt/preferences.d/snyt-php-sury
}

remove_ondrej_php_ppa_files() {
  rm -f /etc/apt/sources.list.d/ondrej-ubuntu-php*.list \
        /etc/apt/sources.list.d/ondrej-ubuntu-php*.sources
}

try_php_provider_sury() {
  local release_url="https://packages.sury.org/php/dists/${VERSION_CODENAME}/Release"
  check_release_url "$release_url" || return 1

  remove_superserver_php_sources
  remove_ondrej_php_ppa_files

  if ! curl -fsSLo /tmp/debsuryorg-archive-keyring.deb \
      https://packages.sury.org/debsuryorg-archive-keyring.deb; then
    return 1
  fi
  if ! dpkg -i /tmp/debsuryorg-archive-keyring.deb; then
    rm -f /tmp/debsuryorg-archive-keyring.deb
    return 1
  fi
  rm -f /tmp/debsuryorg-archive-keyring.deb

  cat > /etc/apt/sources.list.d/php.list <<EOF
# Managed by SNYT SuperServer
deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $VERSION_CODENAME main
EOF
  cat > /etc/apt/preferences.d/snyt-php-provider <<'EOF'
Package: php* libapache2-mod-php*
Pin: origin packages.sury.org
Pin-Priority: 700
EOF

  if ! apt_update_retry; then
    remove_superserver_php_sources
    return 1
  fi
  selected_php_versions_available
}

try_php_provider_ondrej_ppa() {
  [[ "$DISTRO_ID" == "ubuntu" ]] || return 1
  local release_url="https://ppa.launchpadcontent.net/ondrej/php/ubuntu/dists/${VERSION_CODENAME}/Release"
  check_release_url "$release_url" || return 1

  remove_superserver_php_sources
  remove_ondrej_php_ppa_files
  if ! add-apt-repository -y ppa:ondrej/php; then
    remove_ondrej_php_ppa_files
    return 1
  fi
  if ! apt_update_retry; then
    remove_ondrej_php_ppa_files
    return 1
  fi
  selected_php_versions_available
}

try_php_provider_distribution() {
  remove_superserver_php_sources
  remove_ondrej_php_ppa_files
  apt_update_retry || return 1
  selected_php_versions_available
}

php_fpm_listen_value() {
  local version="$1" file value=""
  shopt -s nullglob
  for file in /etc/php/"$version"/fpm/pool.d/*.conf; do
    value="$(awk '
      /^[[:space:]]*;/ { next }
      /^[[:space:]]*\[/ { pool=$0 }
      pool ~ /^[[:space:]]*\[www\][[:space:]]*$/ && /^[[:space:]]*listen[[:space:]]*=/ {
        sub(/^[^=]*=[[:space:]]*/, ""); gsub(/[[:space:]]+$/, ""); print; exit
      }
    ' "$file")"
    [[ -n "$value" ]] && break
  done
  shopt -u nullglob

  if [[ -z "$value" ]]; then
    value="$(grep -RhsE '^[[:space:]]*listen[[:space:]]*=' /etc/php/"$version"/fpm/pool.d 2>/dev/null \
      | tail -n1 | sed -E 's/^[^=]*=[[:space:]]*//; s/[[:space:]]+$//' || true)"
  fi
  printf '%s' "$value"
}

php_fpm_endpoint_exists() {
  local endpoint="$1" host port
  if [[ "$endpoint" == /* ]]; then
    [[ -S "$endpoint" ]]
    return
  fi
  if [[ "$endpoint" == *:* ]]; then
    host="${endpoint%:*}"
    port="${endpoint##*:}"
    ss -lntH 2>/dev/null | awk -v h="$host" -v p=":$port" '$4 ~ p"$" {found=1} END{exit !found}'
    return
  fi
  return 1
}

php_fpm_nginx_endpoint() {
  local endpoint="$1"
  if [[ "$endpoint" == /* ]]; then
    printf 'unix:%s' "$endpoint"
  else
    printf '%s' "$endpoint"
  fi
}

php_fpm_apache_handler() {
  local endpoint="$1"
  if [[ "$endpoint" == /* ]]; then
    printf 'proxy:unix:%s|fcgi://localhost/' "$endpoint"
  else
    printf 'proxy:fcgi://%s/' "$endpoint"
  fi
}

ensure_php_fpm_ready() {
  local version="$1"
  local unit="php${version}-fpm.service"
  local endpoint=""
  local attempt
  local fpm_bin="/usr/sbin/php-fpm${version}"

  [[ -x "$fpm_bin" ]] || fatal "PHP-FPM binary is missing: $fpm_bin"
  # /run is a tmpfs and is recreated on every boot. Some package/service
  # combinations expect /run/php to exist before PHP-FPM starts.
  install -d -o www-data -g www-data -m 0755 /run/php
  if ! "$fpm_bin" -tt >/tmp/snyt-php-fpm-test.log 2>&1; then
    cat /tmp/snyt-php-fpm-test.log >&2 || true
    fatal "PHP-FPM $version configuration test failed."
  fi

  systemctl daemon-reload
  systemctl unmask "$unit" >/dev/null 2>&1 || true
  systemctl enable "$unit" >/dev/null 2>&1 || true
  systemctl restart "$unit"

  for attempt in {1..15}; do
    endpoint="$(php_fpm_listen_value "$version")"
    if systemctl is-active --quiet "$unit" && [[ -n "$endpoint" ]] \
        && php_fpm_endpoint_exists "$endpoint"; then
      PHP_FPM_LISTEN["$version"]="$endpoint"
      ok "PHP $version FPM is ready at $endpoint."
      return 0
    fi
    sleep 1
  done

  warn "PHP-FPM $version service status:"
  systemctl status "$unit" --no-pager -l 2>/dev/null || true
  warn "PHP-FPM $version recent journal:"
  journalctl -u "$unit" -n 40 --no-pager 2>/dev/null || true
  warn "Detected listen value: ${endpoint:-none}"
  ls -la /run/php 2>/dev/null || true
  fatal "PHP-FPM $version did not create a usable listener."
}

ensure_all_php_fpm_ready() {
  local version
  section "Revalidating every PHP-FPM service"
  for version in "${PHP_SELECTED_VERSIONS[@]}"; do
    ensure_php_fpm_ready "$version"
  done
}

install_web_server() {
  section "Installing ${web_server^}"
  check_web_server_conflict

  if [[ "$web_server" == "apache" ]]; then
    apt-get install -y apache2
    systemctl enable --now apache2
    systemctl is-active --quiet apache2
  else
    apt-get install -y nginx
    systemctl enable --now nginx
    systemctl is-active --quiet nginx
  fi
}

install_certbot() {
  section "Installing Certbot"
  local plugin="python3-certbot-${web_server}"

  if package_has_candidate certbot && package_has_candidate "$plugin" \
      && apt-get install -y certbot "$plugin"; then
    record_provider "Certbot" "distribution APT packages"
    systemctl enable --now certbot.timer 2>/dev/null || true
    return 0
  fi

  warn "APT Certbot packages were unavailable; trying the official Snap channel."
  # Avoid an ambiguous mixed installation if APT partially installed Certbot.
  apt-get remove -y certbot "python3-certbot-${web_server}" >/dev/null 2>&1 || true
  hash -r
  apt-get install -y snapd
  systemctl enable --now snapd.socket 2>/dev/null || true
  snap install core >/dev/null 2>&1 || snap refresh core >/dev/null 2>&1 || true
  snap install --classic certbot
  ln -sfn /snap/bin/certbot /usr/local/bin/certbot
  command -v certbot >/dev/null || fatal "Certbot installation failed from both APT and Snap."
  record_provider "Certbot" "official Snap package"
}

install_php_versions() {
  local version module conf

  for version in "${PHP_SELECTED_VERSIONS[@]}"; do
    install_single_php_version "$version"
  done

  configure_php_alternatives

  if [[ "$web_server" == "apache" ]]; then
    # Multi-PHP is routed per VirtualHost. Disable global mod_php/FPM handlers
    # so one PHP version cannot accidentally override another site's socket.
    while read -r module; do
      [[ -n "$module" ]] && a2dismod "$module" 2>/dev/null || true
    done < <(find /etc/apache2/mods-enabled -maxdepth 1 -type l -name 'php*.load' \
      -printf '%f\n' 2>/dev/null | sed 's/\.load$//')

    while read -r conf; do
      [[ -n "$conf" ]] && a2disconf "$conf" 2>/dev/null || true
    done < <(find /etc/apache2/conf-enabled -maxdepth 1 -type l -name 'php*-fpm.conf' \
      -printf '%f\n' 2>/dev/null | sed 's/\.conf$//')

    a2enmod proxy proxy_fcgi setenvif rewrite headers ssl http2
    apache2ctl configtest
    systemctl reload apache2
  fi

  safe_write_info "Installed PHP Versions" "$(join_by ", " "${PHP_SELECTED_VERSIONS[@]}")"
}

configure_php_alternatives() {
  local command target

  for command in php phar phar.phar; do
    target="/usr/bin/${command}${php_version}"
    [[ -x "$target" ]] || continue

    if update-alternatives --query "$command" >/dev/null 2>&1; then
      update-alternatives --set "$command" "$target"
    fi
  done
}

apply_php_configuration() {
  local version="$1"
  local sapi conf_dir

  section "Applying the SNYT PHP $version configuration"

  # Keep the distribution php.ini intact. A version-neutral conf.d fragment is
  # safer across PHP 8.1-8.5 and remains easy to update or remove later.
  for sapi in cli fpm; do
    conf_dir="/etc/php/$version/$sapi/conf.d"
    [[ -d "$conf_dir" ]] || continue
    fetch_asset php.ini "$conf_dir/99-snyt.ini"
  done

  cat > /etc/tmpfiles.d/snyt-php.conf <<'EOF'
d /run/php 0755 www-data www-data -
EOF
  systemd-tmpfiles --create /etc/tmpfiles.d/snyt-php.conf
  ensure_php_fpm_ready "$version"
}

create_primary_website() {
  section "Creating the primary website"
  local endpoint nginx_endpoint apache_handler

  ensure_php_fpm_ready "$php_version"
  endpoint="${PHP_FPM_LISTEN[$php_version]}"
  mkdir -p "/var/www/html/$domain"
  fetch_asset index.php "/var/www/html/$domain/index.php"

  if [[ "$web_server" == "apache" ]]; then
    fetch_asset ApacheExample.conf "/etc/apache2/sites-available/$domain.conf"
    apache_handler="$(php_fpm_apache_handler "$endpoint")"
    sed -i "s/primary.example.com/$domain/g; s/example.com/$domain/g; s/phpversion/$php_version/g" \
      "/var/www/html/$domain/index.php" "/etc/apache2/sites-available/$domain.conf"
    sed -i -E "s#SetHandler \"[^\"]+\"#SetHandler \"$apache_handler\"#" \
      "/etc/apache2/sites-available/$domain.conf"
    a2dissite 000-default.conf 2>/dev/null || true
    a2ensite "$domain.conf"
    apache2ctl configtest
    systemctl reload apache2
  else
    fetch_asset nginxExample.conf "/etc/nginx/sites-available/$domain.conf"
    nginx_endpoint="$(php_fpm_nginx_endpoint "$endpoint")"
    sed -i "s/primary.example.com/$domain/g; s/example.com/$domain/g; s/phpversion/$php_version/g" \
      "/var/www/html/$domain/index.php" "/etc/nginx/sites-available/$domain.conf"
    sed -i -E "s|fastcgi_pass[[:space:]]+[^;]+;|fastcgi_pass $nginx_endpoint;|" \
      "/etc/nginx/sites-available/$domain.conf"
    perl -0pi -e 's/\btry_files\s+\$uri\s+=404;\s*(?=include\s+snippets\/fastcgi-php\.conf;)/ /g' \
      "/etc/nginx/sites-available/$domain.conf"
    ln -sfn "/etc/nginx/sites-available/$domain.conf" "/etc/nginx/sites-enabled/$domain.conf"
    rm -f /etc/nginx/sites-enabled/default
    nginx -t
    systemctl reload nginx
  fi

  chown -R www-data:www-data "/var/www/html/$domain"
  find "/var/www/html/$domain" -type d -exec chmod 755 {} +
  find "/var/www/html/$domain" -type f -exec chmod 644 {} +
  verify_php_through_web_server
}

verify_php_through_web_server() {
  local check_name="snyt-php-runtime-check-$(openssl rand -hex 4).php"
  local check_file="/var/www/html/$domain/$check_name"
  local response_file=""
  local response=""
  local http_code="000"
  local attempt

  response_file="$(mktemp /tmp/snyt-php-response.XXXXXX)"

  cat > "$check_file" <<'PHP_CHECK'
<?php echo PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;
PHP_CHECK
  chown www-data:www-data "$check_file"
  chmod 0644 "$check_file"

  for attempt in 1 2 3 4 5; do
    : > "$response_file"

    if [[ "$SSL_ACTIVE" == true && -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
      http_code="$(
        curl -kLsS --max-time 10 \
          --resolve "$domain:443:127.0.0.1" \
          -o "$response_file" \
          -w '%{http_code}' \
          "https://$domain/$check_name" 2>/dev/null || true
      )"
    else
      http_code="$(
        curl -LsS --max-time 10 \
          -H "Host: $domain" \
          -o "$response_file" \
          -w '%{http_code}' \
          "http://127.0.0.1/$check_name" 2>/dev/null || true
      )"
    fi

    response="$(tr -d '\r\n[:space:]' < "$response_file" 2>/dev/null || true)"
    [[ "$response" == "$php_version" ]] && break
    sleep 2
  done

  rm -f "$check_file" "$response_file"

  if [[ "$response" != "$php_version" ]]; then
    if [[ "$web_server" == "nginx" ]]; then
      warn "Nginx error-log tail:"
      tail -n 12 /var/log/nginx/error.log 2>/dev/null || true
    else
      warn "Apache error-log tail:"
      tail -n 12 /var/log/apache2/error.log 2>/dev/null || true
    fi

    fatal "Web PHP mismatch: selected $php_version, HTTP status ${http_code:-000}, response '${response:-empty}'."
  fi

  ok "${web_server^} is serving PHP $php_version through PHP-FPM."
}

configure_firewall() {
  section "Configuring the UFW firewall"

  ufw default deny incoming
  ufw default allow outgoing
  ufw allow "${SSH_PORT}/tcp" comment 'SSH'
  ufw allow 80/tcp comment 'HTTP'
  ufw allow 443/tcp comment 'HTTPS'
  ufw --force enable

  ufw status | grep -q "${SSH_PORT}/tcp" || fatal "UFW did not preserve SSH port $SSH_PORT."
}

configure_unattended_upgrades() {
  section "Configuring automatic security updates"

  apt-get install -y unattended-upgrades apt-listchanges
  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AUTO_UPGRADES'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUTO_UPGRADES

  systemctl enable --now unattended-upgrades.service || true
}

install_fastfetch_motd() {
  section "Installing the SNYT Fastfetch MOTD"

  local api=""
  local asset_url=""
  local tmp="/tmp/fastfetch.deb"
  local pattern=""

  apt-get install -y jq figlet

  case "$ARCH" in
    amd64) pattern='linux-amd64.deb$' ;;
    arm64) pattern='linux-aarch64.deb$' ;;
  esac

  if [[ -n "$pattern" ]]; then
    api="$(curl -fsSL --retry 2 https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest || true)"
    asset_url="$(jq -r --arg p "$pattern" \
      '.assets[]? | select(.name | test($p)) | .browser_download_url' \
      <<<"$api" | head -n1)"
  fi

  if [[ -n "$asset_url" && "$asset_url" != "null" ]]; then
    curl -fsSL --retry 3 "$asset_url" -o "$tmp"
    apt-get install -y "$tmp" || { dpkg -i "$tmp"; apt-get -f install -y; }
    rm -f "$tmp"
  elif package_has_candidate fastfetch; then
    apt-get install -y fastfetch
  else
    warn "Fastfetch is unavailable; the SNYT MOTD will show the banner without system details."
  fi

  mkdir -p /etc/snyt
  cat > /etc/snyt/fastfetch.jsonc <<'FASTFETCH_JSON'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": {
    "type": "small",
    "padding": { "top": 1, "right": 2 }
  },
  "display": { "separator": " ➜ " },
  "modules": [
    { "type": "title", "format": "SNYT Hosting • {user-name}@{host-name}" },
    "separator",
    "os",
    "host",
    "kernel",
    "uptime",
    "packages",
    "shell",
    "terminal",
    "cpu",
    "memory",
    "swap",
    "disk",
    "localip",
    "break",
    "colors"
  ]
}
FASTFETCH_JSON

  cat > /etc/update-motd.d/01-snyt <<'SNYT_MOTD'
#!/usr/bin/env bash
printf '\n'
if command -v figlet >/dev/null 2>&1; then
  figlet -f slant SNYT 2>/dev/null
else
  echo '=== SNYT Hosting ==='
fi
printf 'Managed by SNYT SuperServer\n\n'
if command -v fastfetch >/dev/null 2>&1; then
  fastfetch --config /etc/snyt/fastfetch.jsonc
fi
printf '\n'
SNYT_MOTD
  chmod 0755 /etc/update-motd.d/01-snyt
}

install_domain_helper() {
  section "Installing the add-domain helper"

  local shared_assets="/usr/local/share/snyt-superserver"
  install -d -m 0755 "$shared_assets"
  fetch_asset index.php "$shared_assets/index.php" 0644

  if [[ "$web_server" == "apache" ]]; then
    fetch_asset ApacheExample.conf "$shared_assets/ApacheExample.conf" 0644
    fetch_asset apache_setup.sh /usr/local/sbin/super-sdomain 0700
  else
    fetch_asset nginxExample.conf "$shared_assets/nginxExample.conf" 0644
    fetch_asset nginx_setup.sh /usr/local/sbin/super-sdomain 0700
  fi

  ln -sfn /usr/local/sbin/super-sdomain /root/super-sdomain.sh
}

show_completion() {
  local scheme="http"
  if [[ "$SSL_ACTIVE" == true ]]; then
    scheme="https"
  fi

  echo
  echo -e "${MAGENTA}╭──────────────────────────────────────────────────────────────╮${NC}"
  echo -e "${MAGENTA}│${NC}  ${GREEN}${BOLD}✔ SNYT SuperServer is ready${NC}                                  ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}├──────────────────────────────────────────────────────────────┤${NC}"
  printf "${MAGENTA}│${NC}  %-60s${MAGENTA}│${NC}\n" "Version       : $SUPERSERVER_VERSION"
  printf "${MAGENTA}│${NC}  %-60s${MAGENTA}│${NC}\n" "System        : $PRETTY_NAME"
  printf "${MAGENTA}│${NC}  %-60s${MAGENTA}│${NC}\n" "Website       : $scheme://$domain"
  printf "${MAGENTA}│${NC}  %-60s${MAGENTA}│${NC}\n" "Web server    : ${web_server^}"
  printf "${MAGENTA}│${NC}  %-60s${MAGENTA}│${NC}\n" "PHP installed : $(join_by ", " "${PHP_SELECTED_VERSIONS[@]}")"
  printf "${MAGENTA}│${NC}  %-60s${MAGENTA}│${NC}\n" "Default PHP   : $php_version"
  printf "${MAGENTA}│${NC}  %-60s${MAGENTA}│${NC}\n" "Credentials   : $INFO_FILE"
  printf "${MAGENTA}│${NC}  %-60s${MAGENTA}│${NC}\n" "Add a domain  : super-sdomain"
  echo -e "${MAGENTA}╰──────────────────────────────────────────────────────────────╯${NC}"
  echo
  echo -e "${DIM}Keep $INFO_FILE private. It contains generated database credentials.${NC}"
  echo
}




module_label() {
  case "$1" in
    curl) printf 'cURL' ;;
    mysql) printf 'MySQL / PDO MySQL' ;;
    mbstring) printf 'Multibyte String' ;;
    xml) printf 'XML suite (DOM, SimpleXML, XML, XSL)' ;;
    zip) printf 'ZIP' ;;
    intl) printf 'Internationalization (Intl)' ;;
    gd) printf 'GD image library' ;;
    bcmath) printf 'BCMath' ;;
    opcache) printf 'Zend OPcache' ;;
    readline) printf 'Readline' ;;
    redis) printf 'Redis extension' ;;
    sqlite3) printf 'SQLite3 / PDO SQLite' ;;
    soap) printf 'SOAP' ;;
    bz2) printf 'BZip2' ;;
    imagick) printf 'ImageMagick' ;;
    tidy) printf 'HTML Tidy' ;;
    xmlrpc) printf 'XML-RPC' ;;
    gmp) printf 'GMP' ;;
    ldap) printf 'LDAP' ;;
    imap) printf 'IMAP' ;;
    snmp) printf 'SNMP' ;;
    apcu) printf 'APCu cache' ;;
    *) printf '%s' "$1" ;;
  esac
}

module_runtime_name() {
  case "$1" in
    mysql) printf 'mysqli' ;;
    xml) printf 'SimpleXML' ;;
    opcache) printf 'Zend OPcache' ;;
    sqlite3) printf 'sqlite3' ;;
    apcu) printf 'apcu' ;;
    *) printf '%s' "$1" ;;
  esac
}

bool_text() {
  if [[ "$1" == true ]]; then
    printf 'Yes'
  else
    printf 'No'
  fi
}

choose_ssl_contact() {
  local choice=""
  echo -e "${BOLD}Let's Encrypt account contact${NC}"
  echo
  echo "  1) Use a real email address (recommended)"
  echo "  2) Continue without an email address"
  echo
  while true; do
    read -r -p "Selection [1]: " choice
    choice="${choice:-1}"
    case "$choice" in
      1)
        SSL_MODE="email"
        while true; do
          email="$(prompt_nonempty "Let's Encrypt email: ")"
          validate_email "$email" && break
          warn "Invalid email format."
        done
        break
        ;;
      2)
        SSL_MODE="no-email"
        email="none"
        warn "No recovery/contact email will be attached to the ACME account."
        break
        ;;
      *) warn "Enter 1 or 2." ;;
    esac
  done
}

configure_repositories() {
  section "Selecting a safe Multi-PHP package source"
  if [[ "$DISTRO_ID" == "ubuntu" ]]; then
    add-apt-repository -y universe
  fi

  if try_php_provider_sury; then
    record_provider "PHP" "packages.sury.org"
    return 0
  fi
  warn "Sury could not satisfy the selected PHP versions; trying the Ondřej Launchpad PPA."

  if try_php_provider_ondrej_ppa; then
    record_provider "PHP" "ppa:ondrej/php"
    return 0
  fi
  warn "The Ondřej PPA could not satisfy the plan; trying distribution packages."

  if try_php_provider_distribution; then
    record_provider "PHP" "distribution repositories"
    return 0
  fi

  echo
  warn "No safe PHP provider can install every selected release: $(join_by ", " "${PHP_SELECTED_VERSIONS[@]}")"
  for version in "${PHP_SELECTED_VERSIONS[@]}"; do
    printf '  PHP %s missing: %s\n' "$version" "$(php_missing_core_packages "$version")"
  done
  fatal "SuperServer will not mix packages from a different Ubuntu/Debian codename."
}

validate_selected_php_versions() {
  local version
  section "Validating selected PHP releases"
  discover_php_versions
  for version in "${PHP_SELECTED_VERSIONS[@]}"; do
    php_candidate_is_available "$version" || fatal \
      "PHP $version is incomplete from $PHP_REPOSITORY_PROVIDER: $(php_missing_core_packages "$version")"
  done
  ok "All selected PHP releases are complete from $PHP_REPOSITORY_PROVIDER."
}

php_version_note() {
  case "$1" in
    8.1) printf 'legacy / end-of-life — explicit compatibility use only' ;;
    8.2) printf 'security-maintained compatibility release' ;;
    8.3) printf 'supported compatibility release' ;;
    8.4) printf 'supported modern release' ;;
    8.5) printf 'newest supported release' ;;
    *) printf 'PHP-FPM release' ;;
  esac
}

checkbox_menu_legacy() {
  local title="$1" hint="$2"
  local -n labels_ref="$3"
  local -n states_ref="$4"
  local input="" index marker
  local -a toggles=()

  while true; do
    echo
    echo -e "${BOLD}${title}${NC}"
    echo -e "${DIM}${hint}${NC}"
    echo

    for index in "${!labels_ref[@]}"; do
      if [[ "${states_ref[$index]}" == true ]]; then
        marker="${GREEN}[x]${NC}"
      else
        marker="${DIM}[ ]${NC}"
      fi
      printf '  %2d) %b %s\n' "$((index + 1))" "$marker" "${labels_ref[$index]}"
    done

    echo
    echo -e "${DIM}Toggle with a number or range (example: 2,4-6).${NC}"
    echo -e "${DIM}Commands: a = select all, n = clear all, d = done.${NC}"
    read -r -p "Selection [d]: " input
    input="${input:-d}"

    case "${input,,}" in
      d|done)
        return 0
        ;;
      a|all)
        for index in "${!states_ref[@]}"; do states_ref[$index]=true; done
        ;;
      n|none|clear)
        for index in "${!states_ref[@]}"; do states_ref[$index]=false; done
        ;;
      *)
        toggles=()
        if ! parse_number_selection "$input" "${#labels_ref[@]}" toggles; then
          warn "Invalid selection. Use numbers, ranges, a, n or d."
          continue
        fi
        for index in "${toggles[@]}"; do
          index=$((index - 1))
          if [[ "${states_ref[$index]}" == true ]]; then
            states_ref[$index]=false
          else
            states_ref[$index]=true
          fi
        done
        ;;
    esac
  done
}

checkbox_menu() {
  local title="$1" hint="$2"
  local labels_name="$3" states_name="$4"
  local -n labels_ref="$labels_name"
  local -n states_ref="$states_name"
  local cursor=0 key="" sequence="" index marker pointer selected_count=0
  local total="${#labels_ref[@]}"

  # Non-interactive shells, dumb terminals and redirected input use the
  # number/range fallback so automated installs remain usable.
  if [[ ! -t 0 || ! -t 1 || "${TERM:-dumb}" == "dumb" ]]; then
    checkbox_menu_legacy "$title" "$hint" "$labels_name" "$states_name"
    return
  fi

  echo
  echo -e "${BOLD}${title}${NC}"
  echo -e "${DIM}${hint}${NC}"
  echo
  printf '\033[s'

  while true; do
    # Restore the saved menu position and clear only the menu area.
    printf '\033[u\033[J'
    selected_count=0

    for index in "${!labels_ref[@]}"; do
      if [[ "${states_ref[$index]}" == true ]]; then
        marker="${GREEN}[x]${NC}"
        selected_count=$((selected_count + 1))
      else
        marker="${DIM}[ ]${NC}"
      fi

      if (( index == cursor )); then
        pointer="${CYAN}${BOLD}>${NC}"
        printf '  %b %2d) %b %b%s%b\n' \
          "$pointer" "$((index + 1))" "$marker" "$BOLD" "${labels_ref[$index]}" "$NC"
      else
        pointer=" "
        printf '  %s %2d) %b %s\n' \
          "$pointer" "$((index + 1))" "$marker" "${labels_ref[$index]}"
      fi
    done

    echo
    echo -e "${DIM}↑/↓ move  •  Space toggle  •  A select all  •  N clear all${NC}"
    printf "${DIM}Enter confirms the selection.${NC}  Selected: %d/%d" "$selected_count" "$total"

    key=""
    IFS= read -rsn1 key

    # Arrow keys arrive as an escape byte followed by two bytes such as [A.
    if [[ "$key" == $'\e' ]]; then
      sequence=""
      IFS= read -rsn2 -t 0.15 sequence || true
      key+="$sequence"
    fi

    case "$key" in
      $'\e[A'|k|K)
        cursor=$(((cursor - 1 + total) % total))
        ;;
      $'\e[B'|j|J)
        cursor=$(((cursor + 1) % total))
        ;;
      $'\e[H')
        cursor=0
        ;;
      $'\e[F')
        cursor=$((total - 1))
        ;;
      " ")
        if [[ "${states_ref[$cursor]}" == true ]]; then
          states_ref[$cursor]=false
        else
          states_ref[$cursor]=true
        fi
        ;;
      a|A)
        for index in "${!states_ref[@]}"; do states_ref[$index]=true; done
        ;;
      n|N)
        for index in "${!states_ref[@]}"; do states_ref[$index]=false; done
        ;;
      "")
        echo
        return 0
        ;;
    esac
  done
}

any_checkbox_selected() {
  local -n states_ref="$1"
  local state
  for state in "${states_ref[@]}"; do
    if [[ "$state" == true ]]; then
      return 0
    fi
  done
  return 1
}

choose_php_versions() {
  local index version default_selection=""
  local -a labels=() states=()

  section "Multi-PHP version selection"
  echo "Choose every PHP-FPM release that should be installed."
  echo "Sury repository availability is verified automatically after you approve the plan."

  for version in "${PHP_VERSION_CANDIDATES[@]}"; do
    labels+=("PHP $version — $(php_version_note "$version")")
    if [[ "$version" == "8.1" ]]; then
      states+=(false)
    else
      states+=(true)
    fi
  done

  while true; do
    checkbox_menu \
      "PHP versions" \
      "Recommended defaults: PHP 8.2, 8.3, 8.4 and 8.5. PHP 8.1 is legacy." \
      labels states
    if any_checkbox_selected states; then
      break
    fi
    warn "Select at least one PHP version."
  done

  PHP_SELECTED_VERSIONS=()
  for index in "${!states[@]}"; do
    if [[ "${states[$index]}" == true ]]; then
      PHP_SELECTED_VERSIONS+=("${PHP_VERSION_CANDIDATES[$index]}")
    fi
  done

  if [[ " ${PHP_SELECTED_VERSIONS[*]} " == *" 8.1 "* ]]; then
    warn "PHP 8.1 is end-of-life and should only be used for legacy applications."
  fi

  if [[ ${#PHP_SELECTED_VERSIONS[@]} -eq 1 ]]; then
    php_version="${PHP_SELECTED_VERSIONS[0]}"
  else
    echo
    echo "Choose the default PHP version for CLI, the primary website and phpMyAdmin:"
    for index in "${!PHP_SELECTED_VERSIONS[@]}"; do
      printf '  %d) PHP %s\n' "$((index + 1))" "${PHP_SELECTED_VERSIONS[$index]}"
    done
    while true; do
      read -r -p "Default PHP [${#PHP_SELECTED_VERSIONS[@]}]: " default_selection
      default_selection="${default_selection:-${#PHP_SELECTED_VERSIONS[@]}}"
      if [[ "$default_selection" =~ ^[0-9]+$ ]] \
        && (( default_selection >= 1 && default_selection <= ${#PHP_SELECTED_VERSIONS[@]} )); then
        php_version="${PHP_SELECTED_VERSIONS[$((default_selection - 1))]}"
        break
      fi
      warn "Choose a valid option."
    done
  fi

  ok "Selected PHP versions: $(join_by ", " "${PHP_SELECTED_VERSIONS[@]}") (default: $php_version)."
}


parse_number_selection() {
  local input="$1" max="$2" token start end number
  local -n output_ref="$3"
  local -a tokens=()
  local -A selected=()
  output_ref=()
  input="${input//[[:space:]]/}"
  [[ -n "$input" ]] || return 1
  IFS=',' read -r -a tokens <<< "$input"
  for token in "${tokens[@]}"; do
    if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"; end="${BASH_REMATCH[2]}"
      (( start <= end )) || return 1
      for ((number=start; number<=end; number++)); do
        (( number >= 1 && number <= max )) || return 1
        selected["$number"]=1
      done
    elif [[ "$token" =~ ^[0-9]+$ ]]; then
      number="$token"
      (( number >= 1 && number <= max )) || return 1
      selected["$number"]=1
    else
      return 1
    fi
  done
  for ((number=1; number<=max; number++)); do
    if [[ -n "${selected[$number]:-}" ]]; then
      output_ref+=("$number")
    fi
  done
  [[ ${#output_ref[@]} -gt 0 ]]
}

array_contains() {
  local wanted="$1" item
  shift
  for item in "$@"; do
    if [[ "$item" == "$wanted" ]]; then
      return 0
    fi
  done
  return 1
}

choose_php_module_profile() {
  local choice="" index module
  local -a labels=() states=()

  section "PHP extension profile"
  echo "  1) Essential — common production extensions"
  echo "  2) All       — every supported extension in the SuperServer catalog"
  echo "  3) Custom    — toggle individual extensions with checkboxes"
  echo

  while true; do
    read -r -p "Profile [1]: " choice
    choice="${choice:-1}"
    case "$choice" in
      1)
        PHP_MODULE_PROFILE="essential"
        PHP_SELECTED_MODULES=("${PHP_ESSENTIAL_MODULES[@]}")
        break
        ;;
      2)
        PHP_MODULE_PROFILE="all"
        PHP_SELECTED_MODULES=("${PHP_ALL_MODULES[@]}")
        break
        ;;
      3)
        PHP_MODULE_PROFILE="custom"
        labels=()
        states=()
        for module in "${PHP_ALL_MODULES[@]}"; do
          labels+=("$(module_label "$module")")
          if array_contains "$module" "${PHP_ESSENTIAL_MODULES[@]}"; then
            states+=(true)
          else
            states+=(false)
          fi
        done

        checkbox_menu \
          "Custom PHP extensions" \
          "CLI, Common and PHP-FPM are always installed. Essential extensions start selected." \
          labels states

        PHP_SELECTED_MODULES=()
        for index in "${!states[@]}"; do
          if [[ "${states[$index]}" == true ]]; then
            PHP_SELECTED_MODULES+=("${PHP_ALL_MODULES[$index]}")
          fi
        done
        break
        ;;
      *)
        warn "Enter 1, 2 or 3."
        ;;
    esac
  done

  echo
  info "PHP extension profile: $PHP_MODULE_PROFILE"
  if [[ ${#PHP_SELECTED_MODULES[@]} -gt 0 ]]; then
    printf '  %s\n' "$(join_by ", " "${PHP_SELECTED_MODULES[@]}")"
  else
    printf '  Core packages only: CLI, Common and PHP-FPM\n'
  fi
}


validate_php_module_plan() {
  local version module package
  local -a missing=()

  for version in "${PHP_SELECTED_VERSIONS[@]}"; do
    for module in "${PHP_SELECTED_MODULES[@]}"; do
      package="php${version}-${module}"
      if package_has_candidate "$package"; then
        continue
      fi
      if [[ "$module" == "opcache" ]]; then
        continue
      fi
      missing+=("$package")
    done
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo
    warn "These optional PHP extension packages are not published and will be skipped automatically:"
    printf '  - %s\n' "${missing[@]}"
  else
    ok "Every requested PHP extension package is available for the selected PHP versions."
  fi
}


choose_phpmyadmin() {
  local answer=""
  echo
  read -r -p "Install phpMyAdmin at /phpmyadmin/? [Y/n]: " answer
  answer="${answer:-Y}"
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    INSTALL_PHPMYADMIN=true
  else
    INSTALL_PHPMYADMIN=false
  fi
}


choose_components() {
  local index
  local -a labels=(
    "MariaDB server"
    "Redis server"
    "Composer"
    "Node.js and npm"
    "PM2 process manager"
    "Python development tools"
    "Java JDK"
    "Docker Engine and Compose"
    "Automatic security updates"
    "SNYT Fastfetch and MOTD"
  )
  local -a states=(true true true true true true false false true true)

  section "Optional components"
  checkbox_menu \
    "Component selection" \
    "Recommended components start selected. Toggle anything you do not need, then choose done." \
    labels states

  INSTALL_MARIADB="${states[0]}"
  INSTALL_REDIS="${states[1]}"
  INSTALL_COMPOSER="${states[2]}"
  INSTALL_NODEJS="${states[3]}"
  INSTALL_PM2="${states[4]}"
  INSTALL_PYTHON="${states[5]}"
  INSTALL_JAVA="${states[6]}"
  INSTALL_DOCKER="${states[7]}"
  INSTALL_UNATTENDED="${states[8]}"
  INSTALL_MOTD="${states[9]}"

  if [[ "$INSTALL_PM2" == true && "$INSTALL_NODEJS" != true ]]; then
    info "PM2 requires Node.js; Node.js was enabled automatically."
    INSTALL_NODEJS=true
  fi

  if [[ "$INSTALL_PHPMYADMIN" == true && "$INSTALL_MARIADB" != true ]]; then
    info "phpMyAdmin requires MariaDB; MariaDB was enabled automatically."
    INSTALL_MARIADB=true
  fi
}


choose_security() {
  local choice=""
  section "Intrusion protection"
  echo "  1) CrowdSec Security Engine + firewall bouncer (recommended)"
  if [[ "$web_server" == "nginx" ]]; then
    echo "  2) CrowdSec + firewall bouncer + Nginx AppSec/WAF"
    echo "  3) No CrowdSec"
  else
    echo "  2) No CrowdSec"
  fi
  echo
  while true; do
    read -r -p "Security [1]: " choice
    choice="${choice:-1}"
    if [[ "$web_server" == "nginx" ]]; then
      case "$choice" in
        1) SECURITY_MODE="crowdsec-firewall"; break ;;
        2) SECURITY_MODE="crowdsec-appsec"; break ;;
        3) SECURITY_MODE="none"; break ;;
        *) warn "Enter 1, 2 or 3." ;;
      esac
    else
      case "$choice" in
        1) SECURITY_MODE="crowdsec-firewall"; break ;;
        2) SECURITY_MODE="none"; break ;;
        *) warn "Enter 1 or 2." ;;
      esac
    fi
  done
}

save_install_plan() {
  mkdir -p "$INFO_DIR"
  cat > "$INSTALL_PLAN_FILE" <<EOF
# SNYT SuperServer installation plan — generated before installation
DOMAIN="$domain"
SSL_MODE="$SSL_MODE"
SSL_EMAIL="$email"
WEB_SERVER="$web_server"
PHP_VERSIONS="$(join_by "," "${PHP_SELECTED_VERSIONS[@]}")"
DEFAULT_PHP="$php_version"
PHP_MODULE_PROFILE="$PHP_MODULE_PROFILE"
PHP_MODULES="$(join_by "," "${PHP_SELECTED_MODULES[@]}")"
INSTALL_MARIADB="$INSTALL_MARIADB"
INSTALL_PHPMYADMIN="$INSTALL_PHPMYADMIN"
INSTALL_REDIS="$INSTALL_REDIS"
INSTALL_COMPOSER="$INSTALL_COMPOSER"
INSTALL_NODEJS="$INSTALL_NODEJS"
INSTALL_PM2="$INSTALL_PM2"
INSTALL_PYTHON="$INSTALL_PYTHON"
INSTALL_JAVA="$INSTALL_JAVA"
INSTALL_DOCKER="$INSTALL_DOCKER"
INSTALL_UNATTENDED="$INSTALL_UNATTENDED"
INSTALL_MOTD="$INSTALL_MOTD"
SECURITY_MODE="$SECURITY_MODE"
EOF
  chmod 600 "$INSTALL_PLAN_FILE"
}

show_installation_summary() {
  local ssl_display="No email"
  if [[ "$SSL_MODE" == "email" ]]; then
    ssl_display="$email"
  fi

  echo
  echo -e "${MAGENTA}╭────────────────────────────────────────────────────────────────────╮${NC}"
  echo -e "${MAGENTA}│${NC}  ${BOLD}SNYT SuperServer installation plan${NC}                              ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}├────────────────────────────────────────────────────────────────────┤${NC}"
  printf "${MAGENTA}│${NC}  %-66s${MAGENTA}│${NC}\n" "Domain          : $domain"
  printf "${MAGENTA}│${NC}  %-66s${MAGENTA}│${NC}\n" "SSL account     : $ssl_display"
  printf "${MAGENTA}│${NC}  %-66s${MAGENTA}│${NC}\n" "Web server      : ${web_server^}"
  printf "${MAGENTA}│${NC}  %-66s${MAGENTA}│${NC}\n" "PHP versions    : $(join_by ", " "${PHP_SELECTED_VERSIONS[@]}")"
  printf "${MAGENTA}│${NC}  %-66s${MAGENTA}│${NC}\n" "Default PHP     : $php_version"
  printf "${MAGENTA}│${NC}  %-66s${MAGENTA}│${NC}\n" "PHP extensions  : $PHP_MODULE_PROFILE (${#PHP_SELECTED_MODULES[@]} selected)"
  printf "${MAGENTA}│${NC}  %-66s${MAGENTA}│${NC}\n" "MariaDB         : $(bool_text "$INSTALL_MARIADB")"
  printf "${MAGENTA}│${NC}  %-66s${MAGENTA}│${NC}\n" "phpMyAdmin      : $(bool_text "$INSTALL_PHPMYADMIN") — /phpmyadmin/"
  printf "${MAGENTA}│${NC}  %-66s${MAGENTA}│${NC}\n" "Redis           : $(bool_text "$INSTALL_REDIS")"
  printf "${MAGENTA}│${NC}  %-66s${MAGENTA}│${NC}\n" "Node.js / PM2   : $(bool_text "$INSTALL_NODEJS") / $(bool_text "$INSTALL_PM2")"
  printf "${MAGENTA}│${NC}  %-66s${MAGENTA}│${NC}\n" "Python / Java   : $(bool_text "$INSTALL_PYTHON") / $(bool_text "$INSTALL_JAVA")"
  printf "${MAGENTA}│${NC}  %-66s${MAGENTA}│${NC}\n" "Docker          : $(bool_text "$INSTALL_DOCKER")"
  printf "${MAGENTA}│${NC}  %-66s${MAGENTA}│${NC}\n" "Security        : $SECURITY_MODE"
  printf "${MAGENTA}│${NC}  %-66s${MAGENTA}│${NC}\n" "Plan file       : $INSTALL_PLAN_FILE"
  echo -e "${MAGENTA}╰────────────────────────────────────────────────────────────────────╯${NC}"
  echo
  confirm "Start installation with this plan?" "Y" || fatal "Installation cancelled."
  save_install_plan
}


install_base_packages() {
  section "Updating the operating system and installing the foundation"
  export DEBIAN_FRONTEND=noninteractive
  export APT_LISTCHANGES_FRONTEND=none
  export NEEDRESTART_MODE=a
  export UCF_FORCE_CONFFOLD=1
  export COMPOSER_ALLOW_SUPERUSER=1
  export COMPOSER_NO_INTERACTION=1
  export npm_config_yes=true
  apt-get update
  apt-get dist-upgrade -y
  apt-get autoremove -y
  apt-get install -y \
    ca-certificates curl wget gnupg lsb-release software-properties-common \
    openssl jq screen nano git zip unzip ufw dialog gcc g++ make
}

install_optional_system_tools() {
  section "Installing selected system tools"
  if [[ "$INSTALL_JAVA" == true ]]; then
    apt-get install -y default-jdk
  fi
}

install_composer() {
  [[ "$INSTALL_COMPOSER" == true ]] || return 0
  section "Installing Composer"
  local installer=/tmp/composer-setup.php expected actual

  # Composer prompts when executed as root unless this is explicitly allowed.
  # The user already selected Composer in the opening wizard, so no question
  # is permitted after the final installation-plan confirmation.
  export COMPOSER_ALLOW_SUPERUSER=1
  export COMPOSER_NO_INTERACTION=1

  expected="$(curl -fsSL https://composer.github.io/installer.sig 2>/dev/null || true)"
  if [[ -n "$expected" ]] && curl -fsSL https://getcomposer.org/installer -o "$installer"; then
    actual="$(php -r "echo hash_file('sha384', '$installer');")"
    if [[ "$actual" == "$expected" ]] \
        && php "$installer" --quiet --install-dir=/usr/local/bin --filename=composer; then
      rm -f "$installer"
      record_provider "Composer" "official verified installer"
      composer --no-interaction --version >/dev/null
      return 0
    fi
  fi
  rm -f "$installer"
  warn "Composer's official installer failed; trying the distribution package."
  apt-get install -y composer
  record_provider "Composer" "distribution APT package"
  composer --no-interaction --version >/dev/null || fatal "Composer installation failed."
}

install_single_php_version() {
  local version="$1" suffix package runtime
  local -a packages=() installed_modules=()
  section "Installing PHP $version"

  for suffix in "${PHP_CORE_SUFFIXES[@]}"; do
    package="php${version}-${suffix}"
    package_has_candidate "$package" || fatal "Required PHP package unavailable: $package"
    packages+=("$package")
  done

  for suffix in "${PHP_SELECTED_MODULES[@]}"; do
    package="php${version}-${suffix}"
    if package_has_candidate "$package"; then
      packages+=("$package")
      installed_modules+=("$suffix")
    elif [[ "$suffix" == "opcache" ]]; then
      info "No separate $package package; OPcache will be checked as a built-in/shared module."
      installed_modules+=("$suffix")
    else
      PHP_SKIPPED_PACKAGES+=("$package")
      warn "$package is unavailable and will be skipped."
    fi
  done

  # Remove duplicates while preserving order.
  mapfile -t packages < <(printf '%s\n' "${packages[@]}" | awk '!seen[$0]++')
  apt-get install -y "${packages[@]}"
  apply_php_configuration "$version"
  ensure_php_fpm_ready "$version"
  verify_php_runtime "$version"

  for suffix in "${installed_modules[@]}"; do
    runtime="$(module_runtime_name "$suffix")"
    if ! /usr/bin/php"$version" -m | grep -qiFx "$runtime"; then
      fatal "PHP $version extension validation failed: $runtime"
    fi
  done
}

verify_php_runtime() {
  local version="${1:-$php_version}"
  local cli_bin="/usr/bin/php${version}"
  local cli_version
  local endpoint
  [[ -x "$cli_bin" ]] || fatal "Missing PHP CLI binary: $cli_bin"
  cli_version="$($cli_bin -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
  [[ "$cli_version" == "$version" ]] || fatal "PHP CLI mismatch for $version."

  ensure_php_fpm_ready "$version"
  endpoint="${PHP_FPM_LISTEN[$version]:-$(php_fpm_listen_value "$version")}"
  php_fpm_endpoint_exists "$endpoint" || fatal "PHP-FPM endpoint is unavailable for $version: ${endpoint:-none}"

  "$cli_bin" -m | grep -qi '^Zend OPcache$' || fatal "Zend OPcache is not loaded for PHP $version."
  ok "PHP $version CLI, FPM and OPcache passed validation."
}

configure_phpmyadmin() {
  [[ "$INSTALL_PHPMYADMIN" == true ]] || { info "phpMyAdmin was not selected."; return 0; }
  [[ "$INSTALL_MARIADB" == true ]] || fatal "phpMyAdmin requires MariaDB."
  section "Installing phpMyAdmin at /phpmyadmin/"
  local endpoint nginx_endpoint apache_handler

  pma_app_password="$(generate_password)"
  export DEBIAN_FRONTEND=noninteractive
  echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
  echo "phpmyadmin phpmyadmin/mysql/app-pass password $pma_app_password" | debconf-set-selections
  echo "phpmyadmin phpmyadmin/app-password-confirm password $pma_app_password" | debconf-set-selections
  echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect none" | debconf-set-selections

  if ! apt-get install -y phpmyadmin; then
    fatal "The distribution phpMyAdmin package failed. SuperServer intentionally does not silently replace it with an unmanaged tarball."
  fi

  configure_php_alternatives
  ensure_php_fpm_ready "$php_version"
  endpoint="${PHP_FPM_LISTEN[$php_version]}"

  if [[ "$web_server" == "apache" ]]; then
    apache_handler="$(php_fpm_apache_handler "$endpoint")"
    rm -f /etc/apache2/conf-enabled/phpmyadmin.conf
    cat > /etc/apache2/conf-available/snyt-phpmyadmin.conf <<EOF
Alias /phpmyadmin /usr/share/phpmyadmin
<Directory /usr/share/phpmyadmin>
    Options FollowSymLinks
    DirectoryIndex index.php
    Require all granted
    <FilesMatch \\.php$>
        SetHandler "$apache_handler"
    </FilesMatch>
</Directory>
<Directory /usr/share/phpmyadmin/setup>
    Require all denied
</Directory>
EOF
    a2enconf snyt-phpmyadmin >/dev/null
    apache2ctl configtest
    systemctl reload apache2
  else
    nginx_endpoint="$(php_fpm_nginx_endpoint "$endpoint")"
    cat > /etc/nginx/snippets/phpmyadmin.conf <<EOF
location = /phpmyadmin { return 301 /phpmyadmin/; }
location /phpmyadmin/ {
    root /usr/share/;
    index index.php index.html;
}
location ~ ^/phpmyadmin/(.+\\.php)$ {
    root /usr/share/;
    try_files \$uri =404;
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    fastcgi_pass $nginx_endpoint;
}
location ~* ^/phpmyadmin/(.+\\.(?:css|js|jpg|jpeg|gif|png|svg|ico|woff|woff2|ttf|map))$ {
    root /usr/share/;
    expires 7d;
    access_log off;
}
EOF
    grep -qF 'include snippets/phpmyadmin.conf;' "/etc/nginx/sites-available/$domain.conf" || \
      sed -i '/server_name/a\    include snippets/phpmyadmin.conf;' "/etc/nginx/sites-available/$domain.conf"
    nginx -t
    systemctl reload nginx
  fi
  safe_write_info "phpMyAdmin Database App Password" "$pma_app_password"
}

install_python_tools() {
  [[ "$INSTALL_PYTHON" == true ]] || return 0
  section "Installing Python tools"
  apt-get install -y python3 python3-dev python3-pip python3-venv
  python3 -m pip --version

  # Avoid changing distribution-managed Python packages. Install app tools in
  # isolated venvs and expose stable wrapper links.
  rm -rf /opt/snyt-python-tools
  python3 -m venv /opt/snyt-python-tools
  if /opt/snyt-python-tools/bin/pip install --upgrade pip Django gunicorn; then
    ln -sfn /opt/snyt-python-tools/bin/django-admin /usr/local/bin/django-admin
    ln -sfn /opt/snyt-python-tools/bin/gunicorn /usr/local/bin/gunicorn
    info "Python application tools installed in /opt/snyt-python-tools."
  else
    warn "PyPI installation failed; trying distribution Django/Gunicorn packages."
    rm -rf /opt/snyt-python-tools
    if package_has_candidate python3-django && package_has_candidate gunicorn; then
      apt-get install -y python3-django gunicorn
      command -v django-admin >/dev/null || fatal "Django fallback installation failed."
      command -v gunicorn >/dev/null || fatal "Gunicorn fallback installation failed."
    else
      fatal "Python tools were unavailable from both PyPI and distribution packages."
    fi
  fi
  [[ -e /usr/local/bin/python ]] || ln -s "$(command -v python3)" /usr/local/bin/python
}

install_nodejs() {
  [[ "$INSTALL_NODEJS" == true ]] || return 0
  section "Installing Node.js"
  local nodesource_ok=false

  if curl -fsSL --retry 3 https://deb.nodesource.com/setup_lts.x -o /tmp/snyt-nodesource.sh \
      && bash /tmp/snyt-nodesource.sh \
      && package_has_candidate nodejs \
      && apt-get install -y nodejs; then
    nodesource_ok=true
    record_provider "Node.js" "NodeSource LTS repository"
  fi
  rm -f /tmp/snyt-nodesource.sh

  if [[ "$nodesource_ok" != true ]]; then
    warn "NodeSource failed; using distribution Node.js and npm packages."
    rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/sources.list.d/nodesource.sources
    apt_update_retry || fatal "APT update failed after removing NodeSource."
    apt-get install -y nodejs npm
    record_provider "Node.js" "distribution repositories"
  fi

  command -v node >/dev/null || fatal "Node.js is unavailable."
  command -v npm >/dev/null || fatal "npm is unavailable."
  if [[ "$INSTALL_PM2" == true ]]; then
    npm install -g pm2@latest
    pm2 startup systemd -u root --hp /root >/tmp/snyt-pm2-startup.txt 2>&1 || true
  fi
}

configure_redis_repository() {
  local release_url="https://packages.redis.io/deb/dists/$VERSION_CODENAME/Release"
  check_release_url "$release_url" || return 1

  install -d -m 0755 /usr/share/keyrings
  if ! curl -fsSL --retry 3 https://packages.redis.io/gpg \
      | gpg --dearmor --yes -o /usr/share/keyrings/redis-archive-keyring.gpg; then
    return 1
  fi
  chmod 0644 /usr/share/keyrings/redis-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $VERSION_CODENAME main" \
    > /etc/apt/sources.list.d/redis.list
  if ! apt_update_retry; then
    rm -f /etc/apt/sources.list.d/redis.list
    return 1
  fi
  package_has_candidate redis || package_has_candidate redis-server
}

install_redis() {
  [[ "$INSTALL_REDIS" == true ]] || return 0
  section "Installing Redis"

  if configure_redis_repository; then
    if package_has_candidate redis; then
      apt-get install -y redis
    else
      apt-get install -y redis-server redis-tools
    fi
    record_provider "Redis" "official packages.redis.io repository"
  else
    warn "The official Redis repository failed; using distribution packages."
    rm -f /etc/apt/sources.list.d/redis.list
    apt_update_retry || fatal "APT update failed before Redis fallback."
    apt-get install -y redis-server redis-tools
    record_provider "Redis" "distribution repositories"
  fi

  systemctl daemon-reload
  REDIS_UNIT=""
  local candidate
  for candidate in redis-server.service redis.service; do
    if systemctl list-unit-files "$candidate" >/dev/null 2>&1; then
      systemctl enable "$candidate" >/dev/null 2>&1 || true
      if systemctl restart "$candidate" >/dev/null 2>&1; then
        REDIS_UNIT="$candidate"
        break
      fi
    fi
  done
  [[ -n "$REDIS_UNIT" ]] || fatal "Redis could not be started."
  redis-cli ping | grep -q '^PONG$' || fatal "Redis did not answer PONG."
  safe_write_info "Redis Service" "$REDIS_UNIT"
}

install_docker() {
  [[ "$INSTALL_DOCKER" == true ]] || return 0
  section "Installing Docker Engine and Compose"
  local docker_repo_ok=false arch
  arch="$(dpkg --print-architecture)"

  if check_release_url "https://download.docker.com/linux/${DISTRO_ID}/dists/${VERSION_CODENAME}/Release"; then
    install -m 0755 -d /etc/apt/keyrings
    if curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" -o /etc/apt/keyrings/docker.asc; then
      chmod a+r /etc/apt/keyrings/docker.asc
      cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/${DISTRO_ID}
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: ${arch}
Signed-By: /etc/apt/keyrings/docker.asc
EOF
      if apt_update_retry && package_has_candidate docker-ce \
          && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        docker_repo_ok=true
        record_provider "Docker" "official Docker APT repository"
      fi
    fi
  fi

  if [[ "$docker_repo_ok" != true ]]; then
    warn "Official Docker packages were unavailable; using distribution Docker packages."
    rm -f /etc/apt/sources.list.d/docker.sources /etc/apt/sources.list.d/docker.list
    apt_update_retry || fatal "APT update failed before Docker fallback."
    apt-get install -y docker.io
    if package_has_candidate docker-compose-v2; then
      apt-get install -y docker-compose-v2
    elif package_has_candidate docker-compose-plugin; then
      apt-get install -y docker-compose-plugin
    else
      apt-get install -y docker-compose
    fi
    record_provider "Docker" "distribution repositories"
  fi

  systemctl enable --now docker
  docker info >/dev/null || fatal "Docker daemon validation failed."
}

configure_crowdsec() {
  [[ "$SECURITY_MODE" != "none" ]] || { info "CrowdSec was not selected."; return 0; }
  section "Installing CrowdSec protection"

  if ! curl -fsSL https://install.crowdsec.net -o /tmp/install-crowdsec.sh; then
    fatal "CrowdSec's official repository installer could not be downloaded."
  fi
  sh /tmp/install-crowdsec.sh
  rm -f /tmp/install-crowdsec.sh
  apt_update_retry || fatal "CrowdSec repository update failed."
  apt-get install -y crowdsec
  record_provider "CrowdSec" "official CrowdSec repository"

  cscli collections install crowdsecurity/linux || true
  if [[ "$web_server" == "nginx" ]]; then
    cscli collections install crowdsecurity/nginx || true
  else
    cscli collections install crowdsecurity/apache2 || true
  fi

  mkdir -p /etc/crowdsec/acquis.d
  if [[ "$web_server" == "nginx" ]]; then
    cat > /etc/crowdsec/acquis.d/snyt-web.yaml <<'EOF'
filenames:
  - /var/log/nginx/access.log
  - /var/log/nginx/error.log
labels:
  type: nginx
---
filenames:
  - /var/log/auth.log
labels:
  type: syslog
EOF
  else
    cat > /etc/crowdsec/acquis.d/snyt-web.yaml <<'EOF'
filenames:
  - /var/log/apache2/*.log
labels:
  type: apache2
---
filenames:
  - /var/log/auth.log
labels:
  type: syslog
EOF
  fi

  systemctl enable --now crowdsec
  systemctl restart crowdsec

  local bouncer_package="crowdsec-firewall-bouncer-iptables"
  if package_has_candidate crowdsec-firewall-bouncer-nftables \
      && command -v iptables >/dev/null 2>&1 \
      && iptables -V 2>/dev/null | grep -qi nf_tables; then
    bouncer_package="crowdsec-firewall-bouncer-nftables"
  fi
  apt-get install -y "$bouncer_package"
  systemctl enable --now crowdsec-firewall-bouncer.service 2>/dev/null || true
  systemctl is-active --quiet crowdsec-firewall-bouncer.service \
    || fatal "CrowdSec firewall bouncer is not active."

  if [[ "$SECURITY_MODE" == "crowdsec-appsec" ]]; then
    # AppSec packages vary by repository generation. Only enable the mode when
    # the official package is actually published for this OS.
    if package_has_candidate crowdsec-nginx-bouncer; then
      apt-get install -y lua5.1 libnginx-mod-http-lua luarocks gettext-base lua-cjson crowdsec-nginx-bouncer
      cscli collections install crowdsecurity/appsec-virtual-patching || true
      cscli collections install crowdsecurity/appsec-generic-rules || true
      cat > /etc/crowdsec/acquis.d/appsec.yaml <<'EOF'
appsec_configs:
  - crowdsecurity/appsec-default
labels:
  type: appsec
listen_addr: 127.0.0.1:7422
source: appsec
EOF
      systemctl restart crowdsec

      if [[ -f /etc/crowdsec/bouncers/crowdsec-nginx-bouncer.conf ]]; then
        if grep -q '^APPSEC_URL=' /etc/crowdsec/bouncers/crowdsec-nginx-bouncer.conf; then
          sed -i 's|^APPSEC_URL=.*|APPSEC_URL=http://127.0.0.1:7422|'             /etc/crowdsec/bouncers/crowdsec-nginx-bouncer.conf
        else
          printf '\nAPPSEC_URL=http://127.0.0.1:7422\n'             >> /etc/crowdsec/bouncers/crowdsec-nginx-bouncer.conf
        fi
      else
        warn "The Nginx bouncer configuration file was not created; AppSec was disabled."
        rm -f /etc/crowdsec/acquis.d/appsec.yaml
        SECURITY_MODE="crowdsec-firewall"
      fi

      if [[ "$SECURITY_MODE" == "crowdsec-appsec" ]]; then
        systemctl restart crowdsec
        nginx -t
        systemctl restart nginx
        ss -lntH | awk '$4 ~ /:7422$/ {found=1} END{exit !found}'           || fatal "CrowdSec AppSec is not listening on 127.0.0.1:7422."
      fi
    else
      warn "CrowdSec Nginx AppSec package is unavailable; firewall bouncer protection remains active."
      SECURITY_MODE="crowdsec-firewall"
    fi
  fi

  systemctl is-active --quiet crowdsec || fatal "CrowdSec is not active."
  cscli version >/dev/null
  safe_write_info "Intrusion Protection" "$SECURITY_MODE"
}

configure_ssl() {
  section "Configuring Let's Encrypt SSL"
  local certbot_args=(--non-interactive --agree-tos --redirect -d "$domain")
  if [[ "$SSL_MODE" == "email" ]]; then
    certbot_args+=(--email "$email")
  else
    certbot_args+=(--register-unsafely-without-email)
  fi

  if [[ "$web_server" == "apache" ]]; then
    certbot --apache "${certbot_args[@]}" && SSL_ACTIVE=true || true
  else
    certbot --nginx "${certbot_args[@]}" && SSL_ACTIVE=true || true
  fi

  if [[ "$SSL_ACTIVE" == true ]]; then
    certbot renew --dry-run || warn "Certbot renewal dry-run failed."
    safe_write_info "SSL Status" "Active with automatic renewal"
    safe_write_info "Primary URL" "https://$domain"
    if [[ "$INSTALL_PHPMYADMIN" == true ]]; then
      safe_write_info "phpMyAdmin URL" "https://$domain/phpmyadmin/"
    fi
  else
    warn "SSL issuance is pending; installation continues over HTTP."
    safe_write_info "SSL Status" "Pending"
    safe_write_info "Primary URL" "http://$domain"
    if [[ "$INSTALL_PHPMYADMIN" == true ]]; then
      safe_write_info "phpMyAdmin URL" "http://$domain/phpmyadmin/"
    fi
  fi
}


configure_mariadb() {
  [[ "$INSTALL_MARIADB" == true ]] || { info "MariaDB was not selected."; return 0; }
  section "Installing and securing MariaDB"

  if package_has_candidate mariadb-server; then
    apt-get install -y mariadb-server mariadb-client
    record_provider "MariaDB" "distribution repositories"
  else
    warn "Distribution MariaDB packages are unavailable; trying MariaDB's official repository."
    curl -fsSLo /tmp/mariadb_repo_setup https://r.mariadb.com/downloads/mariadb_repo_setup
    chmod 0700 /tmp/mariadb_repo_setup
    /tmp/mariadb_repo_setup
    rm -f /tmp/mariadb_repo_setup
    apt_update_retry || fatal "MariaDB official repository update failed."
    apt-get install -y mariadb-server mariadb-client
    record_provider "MariaDB" "official MariaDB repository"
  fi

  systemctl enable --now mariadb
  systemctl is-active --quiet mariadb || fatal "MariaDB is not active."

  mysql_admin_password="$(generate_password)"
  mariadb --protocol=socket <<SQL
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
CREATE USER IF NOT EXISTS '${mysql_admin_user}'@'localhost' IDENTIFIED BY '${mysql_admin_password}';
ALTER USER '${mysql_admin_user}'@'localhost' IDENTIFIED BY '${mysql_admin_password}';
GRANT ALL PRIVILEGES ON *.* TO '${mysql_admin_user}'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

  local auth_file
  auth_file="$(mktemp)"
  chmod 0600 "$auth_file"
  cat > "$auth_file" <<EOF
[client]
user=$mysql_admin_user
password=$mysql_admin_password
host=localhost
EOF
  if ! mariadb --defaults-extra-file="$auth_file" --execute='SELECT 1;' >/dev/null; then
    rm -f "$auth_file"
    fatal "The generated MariaDB administrative account failed authentication."
  fi
  rm -f "$auth_file"

  safe_write_info "MariaDB Root Authentication" "unix_socket (use: sudo mariadb)"
  safe_write_info "MariaDB Admin User" "$mysql_admin_user"
  safe_write_info "MariaDB Admin Password" "$mysql_admin_password"
  safe_write_info "MariaDB Version" "$(mariadb --version | head -n1)"
}

final_validation() {
  section "Running final validation"
  local version active_cli

  configure_php_alternatives
  ensure_all_php_fpm_ready
  for version in "${PHP_SELECTED_VERSIONS[@]}"; do
    verify_php_runtime "$version"
  done

  active_cli="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
  [[ "$active_cli" == "$php_version" ]] || fatal \
    "Default PHP CLI mismatch: selected $php_version, active CLI is $active_cli."

  if [[ "$web_server" == "apache" ]]; then
    apache2ctl configtest
    systemctl is-active --quiet apache2 || fatal "Apache is not active."
  else
    nginx -t
    systemctl is-active --quiet nginx || fatal "Nginx is not active."
  fi
  verify_php_through_web_server

  if [[ "$INSTALL_MARIADB" == true ]]; then
    systemctl is-active --quiet mariadb || fatal "MariaDB is not active."
  fi
  if [[ "$INSTALL_REDIS" == true ]]; then
    redis-cli ping | grep -q '^PONG$' || fatal "Redis validation failed."
  fi
  if [[ "$INSTALL_NODEJS" == true ]]; then
    command -v node >/dev/null || fatal "Node.js validation failed."
    command -v npm >/dev/null || fatal "npm validation failed."
  fi
  if [[ "$INSTALL_PYTHON" == true ]]; then
    command -v python3 >/dev/null || fatal "Python validation failed."
  fi
  if [[ "$INSTALL_COMPOSER" == true ]]; then
    command -v composer >/dev/null || fatal "Composer validation failed."
  fi
  if [[ "$INSTALL_DOCKER" == true ]]; then
    docker info >/dev/null || fatal "Docker validation failed."
  fi
  if [[ "$SECURITY_MODE" != "none" ]]; then
    systemctl is-active --quiet crowdsec || fatal "CrowdSec validation failed."
    systemctl is-active --quiet crowdsec-firewall-bouncer.service       || fatal "CrowdSec firewall bouncer validation failed."
  fi
  if [[ "$SECURITY_MODE" == "crowdsec-appsec" ]]; then
    ss -lntH | awk '$4 ~ /:7422$/ {found=1} END{exit !found}'       || fatal "CrowdSec AppSec listener validation failed."
  fi
  ok "All selected services and PHP-FPM versions passed validation."
}

write_final_info() {
  safe_write_info "Installation Status" "Complete"
  safe_write_info "Primary Domain" "$domain"
  safe_write_info "SSL Registration Mode" "$SSL_MODE"
  safe_write_info "SSL Email" "$email"
  safe_write_info "Web Server" "$web_server"
  safe_write_info "Installed PHP Versions" "$(join_by ", " "${PHP_SELECTED_VERSIONS[@]}")"
  safe_write_info "Default PHP Version" "$php_version"
  safe_write_info "PHP Repository Provider" "$PHP_REPOSITORY_PROVIDER"
  safe_write_info "PHP Module Profile" "$PHP_MODULE_PROFILE"
  safe_write_info "PHP Modules" "$(join_by ", " "${PHP_SELECTED_MODULES[@]}")"
  safe_write_info "MariaDB Provider" "$MARIADB_INSTALL_PROVIDER"
  safe_write_info "Redis Provider" "$REDIS_INSTALL_PROVIDER"
  safe_write_info "Node.js Provider" "$NODE_INSTALL_PROVIDER"
  safe_write_info "Docker Provider" "$DOCKER_INSTALL_PROVIDER"
  safe_write_info "Certbot Provider" "$CERTBOT_INSTALL_PROVIDER"
  safe_write_info "Composer Provider" "$COMPOSER_INSTALL_PROVIDER"
  safe_write_info "CrowdSec Provider" "$CROWDSEC_INSTALL_PROVIDER"
  safe_write_info "phpMyAdmin Installed" "$(bool_text "$INSTALL_PHPMYADMIN")"
  safe_write_info "Security Provider" "$SECURITY_MODE"
  safe_write_info "Installation Plan" "$INSTALL_PLAN_FILE"
  safe_write_info "Credentials File" "$INFO_FILE (permissions 600)"
  safe_write_info "Installation Log" "$LOG_FILE"
  chmod 600 "$INFO_FILE"
  printf '%s\n' "$SUPERSERVER_VERSION" > "$STATE_FILE"
  chmod 600 "$STATE_FILE"
}

install_management_helper() {
  section "Installing SuperServer management tools"
  fetch_asset super-server.sh /usr/local/sbin/super-server 0755
  ln -sfn /usr/local/sbin/super-server /root/super-server.sh
}

main() {
  check_previous_installation
  detect_os
  detect_ssh_port
  print_banner

  echo -e "${GREEN}${BOLD}Configuration wizard${NC}"
  echo "No package updates, repository changes or service installations will run"
  echo "until every choice is collected and you approve the final plan."
  echo

  while true; do
    domain="$(prompt_nonempty 'Primary web domain (example.com): ')"
    validate_domain "$domain" && break
    warn "Invalid domain format."
  done

  choose_ssl_contact
  choose_web_server
  check_web_server_conflict
  choose_php_versions
  choose_php_module_profile
  choose_phpmyadmin
  choose_components
  choose_security
  show_installation_summary

  # No interactive prompts are allowed after this point.
  install_base_packages
  configure_repositories
  validate_selected_php_versions
  validate_php_module_plan
  install_web_server
  install_certbot
  configure_mariadb

  # Install system components before PHP-FPM so later APT transactions cannot
  # leave a selected FPM service stopped or its runtime socket removed.
  install_optional_system_tools
  install_python_tools
  install_nodejs
  install_redis
  install_docker

  install_php_versions
  configure_php_alternatives
  install_composer
  ensure_all_php_fpm_ready
  create_primary_website
  configure_phpmyadmin
  ensure_all_php_fpm_ready

  configure_firewall
  configure_crowdsec
  if [[ "$INSTALL_UNATTENDED" == true ]]; then
    configure_unattended_upgrades
  fi
  if [[ "$INSTALL_MOTD" == true ]]; then
    install_fastfetch_motd
  fi

  configure_ssl
  install_domain_helper
  install_management_helper
  final_validation
  write_final_info
  show_completion
}

main "$@"
