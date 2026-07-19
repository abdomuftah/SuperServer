#!/usr/bin/env bash
# ==============================================================================
# SNYT SuperServer
# A single-file Ubuntu/Debian web-server installer maintained by SNYT Hosting.
# Supported: Ubuntu 22.04/24.04/26.04 and Debian 11/12/13
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

SUPERSERVER_VERSION="3.3.0"
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

PHP_VERSION_CANDIDATES=(8.5 8.4 8.3 8.2 8.1)
PHP_CORE_SUFFIXES=(
  cli common fpm curl mysql mbstring xml zip intl gd bcmath
)
PHP_OPTIONAL_SUFFIXES=(
  redis sqlite3 soap bz2 imagick tidy
)
AVAILABLE_PHP_VERSIONS=()
PHP_SELECTED_VERSIONS=()

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

  echo -e "\n${RED}${BOLD}Installation failed.${NC}" >&2
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

add_launchpad_ppa_if_supported() {
  local ppa="$1"
  local owner archive release_url

  [[ "$DISTRO_ID" == "ubuntu" ]] || return 1
  owner="${ppa#ppa:}"
  owner="${owner%%/*}"
  archive="${ppa##*/}"
  release_url="https://ppa.launchpadcontent.net/${owner}/${archive}/ubuntu/dists/${VERSION_CODENAME}/Release"

  if check_release_url "$release_url"; then
    add-apt-repository -y "$ppa"
    return 0
  fi

  warn "Repository $ppa does not publish $VERSION_CODENAME; distribution packages will be used."
  return 1
}

configure_debian_sury_php() {
  [[ "$DISTRO_ID" == "debian" ]] || return 0

  local release_url="https://packages.sury.org/php/dists/${VERSION_CODENAME}/Release"
  if ! check_release_url "$release_url"; then
    warn "Sury PHP does not publish $VERSION_CODENAME; Debian packages will be used."
    return 1
  fi

  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL --retry 3 https://packages.sury.org/php/apt.gpg \
    -o /etc/apt/keyrings/deb.sury.org-php.gpg
  chmod 0644 /etc/apt/keyrings/deb.sury.org-php.gpg
  echo "deb [signed-by=/etc/apt/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $VERSION_CODENAME main" \
    > /etc/apt/sources.list.d/php-sury.list
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
  PHP_SELECTED_VERSIONS=()

  for version in "${PHP_VERSION_CANDIDATES[@]}"; do
    if php_version_complete "$version"; then
      AVAILABLE_PHP_VERSIONS+=("$version")
    fi
  done

  if [[ ${#AVAILABLE_PHP_VERSIONS[@]} -eq 0 ]]; then
    warn "PHP package diagnostics:"
    for version in "${PHP_VERSION_CANDIDATES[@]}"; do
      echo "  PHP $version missing: $(php_missing_core_packages "$version")"
    done
    fatal "No complete PHP version was found. SuperServer requires CLI, FPM and all core extensions for the same version."
  fi
}

parse_php_selection() {
  local input="$1"
  local max="${#AVAILABLE_PHP_VERSIONS[@]}"
  local token start end number
  local -a tokens=()
  local -A selected=()

  input="${input//[[:space:]]/}"
  [[ -n "$input" ]] || input="all"

  if [[ "$input" == "all" || "$input" == "ALL" || "$input" == "*" ]]; then
    PHP_SELECTED_VERSIONS=("${AVAILABLE_PHP_VERSIONS[@]}")
    return 0
  fi

  IFS=',' read -r -a tokens <<< "$input"
  for token in "${tokens[@]}"; do
    if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"
      end="${BASH_REMATCH[2]}"
      (( start <= end )) || return 1
      for (( number=start; number<=end; number++ )); do
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

  PHP_SELECTED_VERSIONS=()
  for (( number=1; number<=max; number++ )); do
    [[ -n "${selected[$number]:-}" ]] || continue
    PHP_SELECTED_VERSIONS+=("${AVAILABLE_PHP_VERSIONS[$((number - 1))]}")
  done

  [[ ${#PHP_SELECTED_VERSIONS[@]} -gt 0 ]]
}

choose_php_versions() {
  local selection=""
  local default_selection=""
  local index version

  section "Multi-PHP version selection"
  discover_php_versions

  echo "Install one or several complete PHP-FPM versions."
  echo "Every displayed version has CLI, FPM and all required core extensions."
  echo

  for index in "${!AVAILABLE_PHP_VERSIONS[@]}"; do
    version="${AVAILABLE_PHP_VERSIONS[$index]}"
    if [[ "$index" -eq 0 ]]; then
      printf '  %d) PHP %s  %b\n' "$((index + 1))" "$version" "${GREEN}(newest complete version)${NC}"
    elif [[ "$version" == "8.2" ]]; then
      printf '  %d) PHP %s  %b\n' "$((index + 1))" "$version" "${YELLOW}(legacy compatibility)${NC}"
    else
      printf '  %d) PHP %s\n' "$((index + 1))" "$version"
    fi
  done

  echo
  echo "Examples: 1  |  1,3  |  1-3  |  all"
  while true; do
    read -r -p "Versions to install [all]: " selection
    if parse_php_selection "$selection"; then
      break
    fi
    warn "Invalid selection. Use numbers, comma-separated values, a range, or all."
  done

  if [[ ${#PHP_SELECTED_VERSIONS[@]} -eq 1 ]]; then
    php_version="${PHP_SELECTED_VERSIONS[0]}"
  else
    echo
    echo "Choose the default PHP version for CLI, the primary domain and phpMyAdmin:"
    for index in "${!PHP_SELECTED_VERSIONS[@]}"; do
      printf '  %d) PHP %s\n' "$((index + 1))" "${PHP_SELECTED_VERSIONS[$index]}"
    done

    while true; do
      read -r -p "Default PHP [1-${#PHP_SELECTED_VERSIONS[@]}]: " default_selection
      if [[ "$default_selection" =~ ^[0-9]+$ ]] \
        && (( default_selection >= 1 && default_selection <= ${#PHP_SELECTED_VERSIONS[@]} )); then
        php_version="${PHP_SELECTED_VERSIONS[$((default_selection - 1))]}"
        break
      fi
      warn "Choose a number between 1 and ${#PHP_SELECTED_VERSIONS[@]}."
    done
  fi

  local selected_text
  selected_text="$(join_by ", " "${PHP_SELECTED_VERSIONS[@]}")"
  safe_write_info "Selected PHP Versions" "$selected_text"
  safe_write_info "Default PHP Version" "$php_version"
  ok "PHP versions selected: $selected_text (default: $php_version)."
}

show_installation_summary() {
  echo
  echo -e "${BOLD}Installation plan${NC}"
  echo -e "  System       : $PRETTY_NAME"
  echo -e "  Architecture : $ARCH"
  echo -e "  Domain       : $domain"
  echo -e "  Web server   : ${web_server^}"
  echo -e "  PHP versions : $(join_by ", " "${PHP_SELECTED_VERSIONS[@]}")"
  echo -e "  Default PHP  : $php_version"
  echo -e "  SSH port     : $SSH_PORT"
  echo -e "  Credentials  : $INFO_FILE"
  echo

  confirm "Start the installation?" "Y" || fatal "Installation cancelled by the user."
}

install_base_packages() {
  section "Updating the operating system"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get dist-upgrade -y
  apt-get autoremove -y

  local base_packages=(
    ca-certificates curl wget gnupg lsb-release software-properties-common
    dialog openssl jq screen nano git zip unzip ufw
    default-jdk python3 python3-dev python3-pip
    gcc g++ make composer
  )

  if package_has_candidate default-libmysqlclient-dev; then
    base_packages+=(default-libmysqlclient-dev)
  elif package_has_candidate libmysqlclient-dev; then
    base_packages+=(libmysqlclient-dev)
  fi

  apt-get install -y "${base_packages[@]}"
}

configure_repositories() {
  section "Configuring compatible repositories"

  if [[ "$DISTRO_ID" == "ubuntu" ]]; then
    # Several required PHP packages (including FPM on current Ubuntu releases)
    # are published in Universe. Enabling it is safe and idempotent.
    info "Ensuring the Ubuntu Universe repository is enabled."
    add-apt-repository -y universe

    add_launchpad_ppa_if_supported ppa:ondrej/php || true

    # Web-server PPAs are optional. Distribution packages remain the safe fallback.
    if [[ "$web_server" == "apache" ]]; then
      add_launchpad_ppa_if_supported ppa:ondrej/apache2 || true
    else
      add_launchpad_ppa_if_supported ppa:ondrej/nginx-mainline || true
    fi
  else
    configure_debian_sury_php || true
  fi

  if check_release_url "https://packages.redis.io/deb/dists/$VERSION_CODENAME/Release"; then
    install -d -m 0755 /usr/share/keyrings
    curl -fsSL --retry 3 https://packages.redis.io/gpg \
      | gpg --dearmor --yes -o /usr/share/keyrings/redis-archive-keyring.gpg
    chmod 0644 /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $VERSION_CODENAME main" \
      > /etc/apt/sources.list.d/redis.list
  else
    warn "The Redis upstream repository does not publish $VERSION_CODENAME; using the distribution package."
    rm -f /etc/apt/sources.list.d/redis.list
  fi

  apt-get update
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

  if [[ "$web_server" == "apache" ]]; then
    apt-get install -y certbot python3-certbot-apache
  else
    apt-get install -y certbot python3-certbot-nginx
  fi

  systemctl enable --now certbot.timer 2>/dev/null || true
}

configure_mariadb() {
  section "Installing and securing MariaDB"

  apt-get install -y mariadb-server mariadb-client
  systemctl enable --now mariadb
  systemctl is-active --quiet mariadb

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

  local mariadb_auth_file
  mariadb_auth_file="$(mktemp)"
  chmod 0600 "$mariadb_auth_file"
  cat > "$mariadb_auth_file" <<EOF
[client]
user=$mysql_admin_user
password=$mysql_admin_password
host=localhost
EOF

  if mariadb --defaults-extra-file="$mariadb_auth_file" --execute='SELECT 1;' >/dev/null; then
    rm -f "$mariadb_auth_file"
  else
    rm -f "$mariadb_auth_file"
    fatal "The generated MariaDB administrative account failed authentication."
  fi

  safe_write_info "MariaDB Root Authentication" "unix_socket (use: sudo mariadb)"
  safe_write_info "MariaDB Admin User" "$mysql_admin_user"
  safe_write_info "MariaDB Admin Password" "$mysql_admin_password"
  safe_write_info "MariaDB Version" "$(mariadb --version | head -n1)"
}

install_single_php_version() {
  local version="$1"
  local core_packages=()
  local optional_packages=()
  local skipped_optional=()
  local suffix package

  section "Installing PHP $version"

  for suffix in "${PHP_CORE_SUFFIXES[@]}"; do
    package="php${version}-${suffix}"
    package_has_candidate "$package" || fatal "Required PHP package is unavailable: $package"
    core_packages+=("$package")
  done

  package="php${version}-opcache"
  if package_has_candidate "$package"; then
    core_packages+=("$package")
  else
    info "No separate $package package is published; OPcache will be validated as a built-in module."
  fi

  for suffix in "${PHP_OPTIONAL_SUFFIXES[@]}"; do
    package="php${version}-${suffix}"
    if package_has_candidate "$package"; then
      optional_packages+=("$package")
    else
      skipped_optional+=("$package")
    fi
  done

  apt-get install -y "${core_packages[@]}" "${optional_packages[@]}"

  if [[ ${#skipped_optional[@]} -gt 0 ]]; then
    warn "Optional PHP $version packages unavailable and skipped: ${skipped_optional[*]}"
  fi

  systemctl enable --now "php${version}-fpm"
  apply_php_configuration "$version"
  verify_php_runtime "$version"
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
  local sapi ini

  section "Applying the SNYT PHP $version configuration"

  for sapi in cli fpm; do
    ini="/etc/php/$version/$sapi/php.ini"
    [[ -f "$ini" ]] || continue
    backup_file "$ini"
    fetch_asset php.ini "$ini"
  done

  systemctl restart "php${version}-fpm"
}

verify_php_runtime() {
  local version="${1:-$php_version}"
  local cli_bin="/usr/bin/php${version}"
  local cli_version

  [[ -x "$cli_bin" ]] || fatal "PHP $version CLI binary is missing: $cli_bin"
  cli_version="$($cli_bin -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"

  [[ "$cli_version" == "$version" ]] || fatal \
    "PHP CLI mismatch: expected $version, but $cli_bin reports $cli_version."
  systemctl is-active --quiet "php${version}-fpm" || fatal "PHP-FPM $version is not active."
  [[ -S "/run/php/php${version}-fpm.sock" ]] || fatal \
    "PHP-FPM socket is missing: /run/php/php${version}-fpm.sock"

  "$cli_bin" -m | grep -qi '^curl$' || fatal "PHP $version curl extension is not loaded."
  "$cli_bin" -m | grep -qi '^mbstring$' || fatal "PHP $version mbstring extension is not loaded."
  "$cli_bin" -m | grep -qi '^mysqli$' || fatal "PHP $version MySQL extension is not loaded."
  "$cli_bin" -m | grep -qi '^Zend OPcache$' || fatal "PHP $version Zend OPcache is not loaded."
  ok "PHP $version CLI, FPM and OPcache passed validation."
}

create_primary_website() {
  section "Creating the primary website"

  mkdir -p "/var/www/html/$domain"

  if [[ "$web_server" == "apache" ]]; then
    fetch_asset index.php "/var/www/html/$domain/index.php"
    fetch_asset ApacheExample.conf "/etc/apache2/sites-available/$domain.conf"
    sed -i "s/primary.example.com/$domain/g; s/example.com/$domain/g; s/phpversion/$php_version/g" \
      "/var/www/html/$domain/index.php" "/etc/apache2/sites-available/$domain.conf"

    a2dissite 000-default.conf 2>/dev/null || true
    a2ensite "$domain.conf"
    apache2ctl configtest
    systemctl reload apache2
  else
    fetch_asset index.php "/var/www/html/$domain/index.php"
    fetch_asset nginxExample.conf "/etc/nginx/sites-available/$domain.conf"
    sed -i "s/primary.example.com/$domain/g; s/example.com/$domain/g; s/phpversion/$php_version/g" \
      "/var/www/html/$domain/index.php" "/etc/nginx/sites-available/$domain.conf"

    # Ubuntu's snippets/fastcgi-php.conf already provides a try_files guard.
    # Older SuperServer templates added a second try_files directive in the
    # same location, which causes nginx 1.28+ to fail with "directive is duplicate".
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
  local check_file="/var/www/html/$domain/.snyt-php-runtime-check.php"
  local response=""
  local attempt

  cat > "$check_file" <<'PHP_CHECK'
<?php echo PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;
PHP_CHECK
  chown www-data:www-data "$check_file"
  chmod 0644 "$check_file"

  for attempt in 1 2 3 4 5; do
    if [[ "$SSL_ACTIVE" == true && -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
      response="$(curl -kfsS --max-time 10 --resolve "$domain:443:127.0.0.1" \
        "https://$domain/.snyt-php-runtime-check.php" 2>/dev/null || true)"
    else
      response="$(curl -fsS --max-time 10 -H "Host: $domain" \
        "http://127.0.0.1/.snyt-php-runtime-check.php" 2>/dev/null || true)"
    fi
    [[ "$response" == "$php_version" ]] && break
    sleep 2
  done

  rm -f "$check_file"

  [[ "$response" == "$php_version" ]] || fatal \
    "Web PHP mismatch: selected $php_version, web server returned '${response:-no response}'."
  ok "${web_server^} is serving PHP $php_version through PHP-FPM."
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

  # phpMyAdmin may pull the distribution's generic PHP packages. Re-assert the
  # exact version selected by the user and validate it again.
  configure_php_alternatives
  systemctl restart "php${php_version}-fpm"
  verify_php_runtime

  if [[ "$web_server" == "apache" ]]; then
    rm -f /etc/apache2/conf-enabled/phpmyadmin.conf
    cat > /etc/apache2/conf-available/snyt-phpmyadmin.conf <<EOF
Alias /phpmyadmin /usr/share/phpmyadmin

<Directory /usr/share/phpmyadmin>
    Options FollowSymLinks
    DirectoryIndex index.php
    Require all granted

    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php/php${php_version}-fpm.sock|fcgi://localhost/"
    </FilesMatch>
</Directory>

<Directory /usr/share/phpmyadmin/setup>
    Require all denied
</Directory>
EOF
    a2enconf snyt-phpmyadmin
    apache2ctl configtest
    systemctl reload apache2
  else
    cat > /etc/nginx/snippets/phpmyadmin.conf <<'PMA_NGINX'
location = /phpmyadmin {
    return 301 /phpmyadmin/;
}

location /phpmyadmin/ {
    root /usr/share/;
    index index.php index.html;
}

location ~ ^/phpmyadmin/(.+\.php)$ {
    root /usr/share/;
    try_files $uri =404;
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_pass unix:/run/php/phpPHPVERSION-fpm.sock;
}

location ~* ^/phpmyadmin/(.+\.(?:css|js|jpg|jpeg|gif|png|svg|ico|woff|woff2|ttf|map))$ {
    root /usr/share/;
    expires 7d;
    access_log off;
}
PMA_NGINX
    sed -i "s/PHPVERSION/$php_version/g" /etc/nginx/snippets/phpmyadmin.conf

    if ! grep -qF 'include snippets/phpmyadmin.conf;' "/etc/nginx/sites-available/$domain.conf"; then
      sed -i '/server_name/a\    include snippets/phpmyadmin.conf;' "/etc/nginx/sites-available/$domain.conf"
    fi

    nginx -t
    systemctl reload nginx
  fi

  safe_write_info "phpMyAdmin Database App Password" "$pma_app_password"
}

install_python_tools() {
  section "Installing Python tools"

  python3 -m pip --version
  if python3 -m pip install --help 2>/dev/null | grep -q -- '--break-system-packages'; then
    python3 -m pip install --upgrade Django --break-system-packages
  else
    warn "This pip version does not support --break-system-packages; installing Django with the available pip syntax."
    python3 -m pip install --upgrade Django
  fi

  [[ -e /usr/local/bin/python ]] || ln -s "$(command -v python3)" /usr/local/bin/python
}

install_nodejs() {
  section "Installing Node.js LTS and PM2"

  local nodesource_ok=false
  if curl -fsSL --retry 3 https://deb.nodesource.com/setup_lts.x -o /tmp/snyt-nodesource.sh; then
    if bash /tmp/snyt-nodesource.sh; then
      nodesource_ok=true
    fi
  fi
  rm -f /tmp/snyt-nodesource.sh

  if [[ "$nodesource_ok" != true ]]; then
    warn "NodeSource setup failed; the distribution Node.js package will be used."
    rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/sources.list.d/nodesource.sources
    apt-get update
  fi

  apt-get install -y nodejs npm || apt-get install -y nodejs
  command -v npm >/dev/null 2>&1 || fatal "npm is unavailable after installing Node.js."
  npm install -g pm2@latest
  pm2 startup systemd -u root --hp /root >/tmp/snyt-pm2-startup.txt 2>&1 || true
}

install_redis() {
  section "Installing Redis"

  if package_has_candidate redis; then
    apt-get install -y redis
  else
    apt-get install -y redis-server redis-tools
  fi

  systemctl daemon-reload
  REDIS_UNIT=""

  local candidate
  for candidate in redis-server.service redis.service; do
    if systemctl start "$candidate" >/dev/null 2>&1; then
      REDIS_UNIT="$candidate"
      break
    fi
  done

  [[ -n "$REDIS_UNIT" ]] || fatal "Redis could not be started."

  if ! systemctl is-enabled redis-server.service >/dev/null 2>&1 \
    && ! systemctl is-enabled redis.service >/dev/null 2>&1; then
    systemctl preset redis-server.service >/dev/null 2>&1 \
      || systemctl preset redis.service >/dev/null 2>&1 \
      || true
  fi

  redis-cli ping | grep -q '^PONG$'
  safe_write_info "Redis Service" "$REDIS_UNIT"
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

configure_fail2ban() {
  section "Installing and configuring Fail2ban"

  apt-get install -y fail2ban

  if [[ "$web_server" == "apache" ]]; then
    fetch_asset Apachejail.local /etc/fail2ban/jail.local
  else
    fetch_asset Nginxjail.local /etc/fail2ban/jail.local
  fi

  mkdir -p /etc/fail2ban/jail.d
  cat > /etc/fail2ban/jail.d/00-snyt-ssh.local <<EOF
[sshd]
enabled = true
port = $SSH_PORT
backend = systemd
EOF

  fail2ban-client -t
  systemctl enable --now fail2ban
  fail2ban-client ping | grep -qi 'pong'
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

configure_ssl() {
  section "Configuring Let's Encrypt SSL"

  local certbot_args=(
    --non-interactive
    --agree-tos
    --redirect
    --email "$email"
    -d "$domain"
  )

  if [[ "$web_server" == "apache" ]]; then
    if certbot --apache "${certbot_args[@]}"; then
      SSL_ACTIVE=true
    fi
  else
    if certbot --nginx "${certbot_args[@]}"; then
      SSL_ACTIVE=true
    fi
  fi

  if [[ "$SSL_ACTIVE" == true ]]; then
    certbot renew --dry-run || warn "The Certbot renewal dry-run failed; inspect $LOG_FILE."
    safe_write_info "SSL Status" "Active with automatic renewal"
    safe_write_info "Primary URL" "https://$domain"
    safe_write_info "phpMyAdmin URL" "https://$domain/phpmyadmin/"
  else
    warn "SSL could not be issued now. Installation will continue over HTTP."
    echo "After fixing DNS and ports, run: certbot --$web_server -d $domain --redirect"
    safe_write_info "SSL Status" "Pending; run: certbot --$web_server -d $domain --redirect"
    safe_write_info "Primary URL" "http://$domain"
    safe_write_info "phpMyAdmin URL" "http://$domain/phpmyadmin/"
  fi
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

final_validation() {
  section "Running final validation"

  local version
  configure_php_alternatives

  for version in "${PHP_SELECTED_VERSIONS[@]}"; do
    verify_php_runtime "$version"
  done

  local active_cli
  active_cli="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
  [[ "$active_cli" == "$php_version" ]] || fatal \
    "Default PHP CLI mismatch: selected $php_version, active CLI is $active_cli."

  if [[ "$web_server" == "apache" ]]; then
    apache2ctl configtest
    systemctl is-active --quiet apache2
  else
    nginx -t
    systemctl is-active --quiet nginx
  fi

  verify_php_through_web_server
  systemctl is-active --quiet mariadb
  systemctl is-active --quiet fail2ban
  redis-cli ping | grep -q '^PONG$'
  command -v node >/dev/null
  command -v npm >/dev/null
  command -v python3 >/dev/null
  command -v composer >/dev/null

  ok "All required services and PHP-FPM versions passed validation."
}

write_final_info() {
  safe_write_info "Installation Status" "Complete"
  safe_write_info "Primary Domain" "$domain"
  safe_write_info "SSL Email" "$email"
  safe_write_info "Web Server" "$web_server"
  safe_write_info "Web Server Version" "$(
    if [[ "$web_server" == "apache" ]]; then
      apache2 -v | head -n1
    else
      nginx -v 2>&1
    fi
  )"
  safe_write_info "Installed PHP Versions" "$(join_by ", " "${PHP_SELECTED_VERSIONS[@]}")"
  safe_write_info "Default PHP Version" "$php_version"
  safe_write_info "PHP Version" "$(php -v | head -n1)"
  safe_write_info "Default PHP-FPM Service" "php${php_version}-fpm"
  safe_write_info "Default PHP-FPM Socket" "/run/php/php${php_version}-fpm.sock"
  safe_write_info "Redis Version" "$(redis-server --version)"
  safe_write_info "Node.js Version" "$(node --version)"
  safe_write_info "npm Version" "$(npm --version)"
  safe_write_info "Python Version" "$(python3 --version)"
  safe_write_info "Composer Version" "$(composer --version 2>/dev/null | head -n1)"
  safe_write_info "Credentials File" "$INFO_FILE (permissions 600)"
  safe_write_info "Installation Log" "$LOG_FILE"

  chmod 600 "$INFO_FILE"
  printf '%s\n' "$SUPERSERVER_VERSION" > "$STATE_FILE"
  chmod 600 "$STATE_FILE"
}

show_completion() {
  local scheme="http"
  [[ "$SSL_ACTIVE" == true ]] && scheme="https"

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

main() {
  check_previous_installation
  detect_os
  detect_ssh_port
  print_banner

  echo "Detected: $PRETTY_NAME ($VERSION_CODENAME / $ARCH)"
  echo "SSH port: $SSH_PORT"
  echo

  while true; do
    domain="$(prompt_nonempty 'Primary web domain (example.com): ')"
    validate_domain "$domain" && break
    warn "Invalid domain format."
  done

  while true; do
    email="$(prompt_nonempty "Email for Let's Encrypt: ")"
    if validate_email "$email"; then
      safe_write_info "SSL Email" "$email"
      break
    fi
    warn "Invalid email format."
  done

  choose_web_server
  install_base_packages
  configure_repositories
  choose_php_versions
  show_installation_summary

  install_web_server
  install_certbot
  configure_mariadb
  install_php_versions
  create_primary_website
  configure_phpmyadmin
  install_python_tools
  install_nodejs
  install_redis
  configure_firewall
  configure_fail2ban
  configure_unattended_upgrades
  install_fastfetch_motd
  configure_ssl
  install_domain_helper
  final_validation
  write_final_info
  show_completion
}

main "$@"
