#!/usr/bin/env bash
# ==============================================================================
# SNYT SuperServer
# A single-file Ubuntu/Debian web-server installer maintained by SNYT Hosting.
# Supported: Ubuntu 22.04/24.04/26.04 and Debian 11/12/13
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

SUPERSERVER_VERSION="3.4.2"
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

# v3.4 wizard choices. All are collected before package installation starts.
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
PHP_CORE_SUFFIXES=(
  cli common fpm curl mysql mbstring xml zip intl gd bcmath
)
PHP_OPTIONAL_SUFFIXES=(
  redis sqlite3 soap bz2 imagick tidy
)
AVAILABLE_PHP_VERSIONS=()
UNAVAILABLE_PHP_VERSIONS=()
PHP_SELECTED_VERSIONS=()
PHP_SELECTION_ERROR=""

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
  UNAVAILABLE_PHP_VERSIONS=()
  PHP_SELECTED_VERSIONS=()

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

php_version_note() {
  local version="$1"

  case "$version" in
    8.1) printf 'legacy compatibility' ;;
    8.2) printf 'wide compatibility' ;;
    8.3) printf 'modern compatibility' ;;
    8.4) printf 'modern release' ;;
    8.5) printf 'newest candidate' ;;
    *) printf 'PHP-FPM' ;;
  esac
}

parse_php_selection() {
  local input="$1"
  local max="${#PHP_VERSION_CANDIDATES[@]}"
  local token start end number candidate
  local -a tokens=()
  local -A selected=()

  PHP_SELECTION_ERROR=""
  input="${input//[[:space:]]/}"
  [[ -n "$input" ]] || input="all"

  if [[ "$input" == "all" || "$input" == "ALL" || "$input" == "*" || "$input" == "available" ]]; then
    PHP_SELECTED_VERSIONS=("${AVAILABLE_PHP_VERSIONS[@]}")
    return 0
  fi

  IFS=',' read -r -a tokens <<< "$input"
  for token in "${tokens[@]}"; do
    if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"
      end="${BASH_REMATCH[2]}"
      if (( start > end )); then
        PHP_SELECTION_ERROR="Invalid range: $token"
        return 1
      fi
      for (( number=start; number<=end; number++ )); do
        if (( number < 1 || number > max )); then
          PHP_SELECTION_ERROR="Option $number is outside the displayed range."
          return 1
        fi
        selected["$number"]=1
      done
    elif [[ "$token" =~ ^[0-9]+$ ]]; then
      number="$token"
      if (( number < 1 || number > max )); then
        PHP_SELECTION_ERROR="Option $number is outside the displayed range."
        return 1
      fi
      selected["$number"]=1
    else
      PHP_SELECTION_ERROR="Use option numbers, comma-separated options, a range, or all."
      return 1
    fi
  done

  PHP_SELECTED_VERSIONS=()
  for (( number=1; number<=max; number++ )); do
    [[ -n "${selected[$number]:-}" ]] || continue
    candidate="${PHP_VERSION_CANDIDATES[$((number - 1))]}"

    if ! php_candidate_is_available "$candidate"; then
      PHP_SELECTION_ERROR="PHP $candidate cannot be installed on $PRETTY_NAME with the currently supported repositories. Missing: $(php_missing_core_packages "$candidate")"
      PHP_SELECTED_VERSIONS=()
      return 1
    fi

    PHP_SELECTED_VERSIONS+=("$candidate")
  done

  if [[ ${#PHP_SELECTED_VERSIONS[@]} -eq 0 ]]; then
    PHP_SELECTION_ERROR="Select at least one PHP version marked AVAILABLE."
    return 1
  fi

  return 0
}

choose_php_versions() {
  local selection=""
  local default_selection=""
  local index version status note recommended_version

  section "PHP version selection"
  discover_php_versions

  echo "All supported PHP choices are shown below."
  echo "Availability is detected live from this server's operating system and repositories."
  echo

  recommended_version="${AVAILABLE_PHP_VERSIONS[$((${#AVAILABLE_PHP_VERSIONS[@]} - 1))]}"

  for index in "${!PHP_VERSION_CANDIDATES[@]}"; do
    version="${PHP_VERSION_CANDIDATES[$index]}"
    note="$(php_version_note "$version")"

    if php_candidate_is_available "$version"; then
      status="${GREEN}AVAILABLE${NC}"
      if [[ "$version" == "$recommended_version" ]]; then
        printf '  %d) PHP %-3s  [%b]  %s %b\n' \
          "$((index + 1))" "$version" "$status" "$note" "${GREEN}(recommended available version)${NC}"
      else
        printf '  %d) PHP %-3s  [%b]  %s\n' \
          "$((index + 1))" "$version" "$status" "$note"
      fi
    else
      status="${RED}UNAVAILABLE${NC}"
      printf '  %d) PHP %-3s  [%b]  %s\n' \
        "$((index + 1))" "$version" "$status" "$note"
    fi
  done

  echo
  echo -e "${DIM}Only versions marked AVAILABLE can be installed safely.${NC}"
  echo -e "${DIM}Selecting an unavailable version prints its missing package details.${NC}"
  echo "Examples: 2  |  2,4  |  2-5  |  all"
  echo '"all" installs every version currently marked AVAILABLE.'

  while true; do
    read -r -p "PHP versions to install [all]: " selection
    if parse_php_selection "$selection"; then
      break
    fi
    warn "$PHP_SELECTION_ERROR"
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


# ==============================================================================
# SuperServer v3.4.2 overrides
# The original installer functions remain above for backwards readability; the
# definitions below are the active v3.4.2 implementation.
# ==============================================================================

PHP_CORE_SUFFIXES=(cli common fpm)
PHP_ESSENTIAL_MODULES=(curl mysql mbstring xml zip intl gd bcmath opcache readline)
PHP_ALL_MODULES=(
  curl mysql mbstring xml zip intl gd bcmath opcache readline
  redis sqlite3 soap bz2 imagick tidy xmlrpc gmp ldap imap snmp apcu
)

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

bootstrap_preflight() {
  section "Preparing repository preflight"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl wget gnupg lsb-release openssl software-properties-common
}

configure_sury_php_repository() {
  local release_url="https://packages.sury.org/php/dists/${VERSION_CODENAME}/Release"
  check_release_url "$release_url" || fatal \
    "packages.sury.org does not publish a PHP repository for $VERSION_CODENAME."

  # Remove old SuperServer/Launchpad PHP definitions so APT has one PHP source.
  rm -f /etc/apt/sources.list.d/*ondrej*php* \
        /etc/apt/sources.list.d/php-sury.list \
        /etc/apt/sources.list.d/php.list

  curl -fsSLo /tmp/debsuryorg-archive-keyring.deb \
    https://packages.sury.org/debsuryorg-archive-keyring.deb
  dpkg -i /tmp/debsuryorg-archive-keyring.deb
  rm -f /tmp/debsuryorg-archive-keyring.deb

  cat > /etc/apt/sources.list.d/php.list <<EOF
# Managed by SNYT SuperServer
deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $VERSION_CODENAME main
EOF

  cat > /etc/apt/preferences.d/snyt-php-sury <<'EOF'
Package: php* libapache2-mod-php*
Pin: origin packages.sury.org
Pin-Priority: 700
EOF
}

configure_repositories() {
  section "Configuring the Multi-PHP repository"
  if [[ "$DISTRO_ID" == "ubuntu" ]]; then
    add-apt-repository -y universe
  fi
  configure_sury_php_repository
  apt-get update
  ok "Sury Multi-PHP repository is active for $VERSION_CODENAME."
}

validate_selected_php_versions() {
  local version
  local -a unavailable=()

  section "Validating selected PHP releases"
  discover_php_versions

  for version in "${PHP_SELECTED_VERSIONS[@]}"; do
    if ! php_candidate_is_available "$version"; then
      unavailable+=("PHP $version: $(php_missing_core_packages "$version")")
    fi
  done

  if [[ ${#unavailable[@]} -gt 0 ]]; then
    echo
    error "The Sury repository does not currently provide every required package for the selected PHP releases:"
    printf '  - %s\n' "${unavailable[@]}"
    fatal "No PHP packages were installed. Rerun the wizard and choose releases available for this operating system."
  fi

  ok "All selected PHP releases are available from the configured repository."
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

parse_php_selection() {
  local input="$1"
  local max="${#PHP_VERSION_CANDIDATES[@]}"
  local token start end number candidate
  local -a tokens=()
  local -A selected=()

  PHP_SELECTION_ERROR=""
  input="${input//[[:space:]]/}"
  [[ -n "$input" ]] || input="all"

  # "all" intentionally excludes PHP 8.1 because it is EOL. The user can
  # still select option 1 explicitly or enter 1-5.
  if [[ "$input" =~ ^(all|ALL|available|supported|\*)$ ]]; then
    PHP_SELECTED_VERSIONS=()
    for candidate in "${AVAILABLE_PHP_VERSIONS[@]}"; do
      if [[ "$candidate" == "8.1" ]]; then
        continue
      fi
      PHP_SELECTED_VERSIONS+=("$candidate")
    done
    [[ ${#PHP_SELECTED_VERSIONS[@]} -gt 0 ]] || PHP_SELECTED_VERSIONS=("${AVAILABLE_PHP_VERSIONS[@]}")
    return 0
  fi

  if [[ "$input" == "all+legacy" ]]; then
    PHP_SELECTED_VERSIONS=("${AVAILABLE_PHP_VERSIONS[@]}")
    return 0
  fi

  IFS=',' read -r -a tokens <<< "$input"
  for token in "${tokens[@]}"; do
    if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"; end="${BASH_REMATCH[2]}"
      (( start <= end )) || { PHP_SELECTION_ERROR="Invalid range: $token"; return 1; }
      for ((number=start; number<=end; number++)); do
        (( number >= 1 && number <= max )) || { PHP_SELECTION_ERROR="Option $number is outside the list."; return 1; }
        selected["$number"]=1
      done
    elif [[ "$token" =~ ^[0-9]+$ ]]; then
      number="$token"
      (( number >= 1 && number <= max )) || { PHP_SELECTION_ERROR="Option $number is outside the list."; return 1; }
      selected["$number"]=1
    else
      PHP_SELECTION_ERROR="Use option numbers, comma-separated choices, a range, all, or all+legacy."
      return 1
    fi
  done

  PHP_SELECTED_VERSIONS=()
  for ((number=1; number<=max; number++)); do
    [[ -n "${selected[$number]:-}" ]] || continue
    candidate="${PHP_VERSION_CANDIDATES[$((number - 1))]}"
    if ! php_candidate_is_available "$candidate"; then
      PHP_SELECTION_ERROR="PHP $candidate is missing required packages: $(php_missing_core_packages "$candidate")"
      PHP_SELECTED_VERSIONS=()
      return 1
    fi
    PHP_SELECTED_VERSIONS+=("$candidate")
  done
  [[ ${#PHP_SELECTED_VERSIONS[@]} -gt 0 ]] || { PHP_SELECTION_ERROR="Select at least one PHP version."; return 1; }
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
  apt-get update
  apt-get dist-upgrade -y
  apt-get autoremove -y
  apt-get install -y \
    ca-certificates curl wget gnupg lsb-release software-properties-common \
    openssl jq screen nano git zip unzip ufw dialog gcc g++ make
}

install_optional_system_tools() {
  section "Installing selected system tools"

  if [[ "$INSTALL_COMPOSER" == true ]]; then
    apt-get install -y composer
  fi

  if [[ "$INSTALL_PYTHON" == true ]]; then
    apt-get install -y python3 python3-dev python3-pip
  fi

  if [[ "$INSTALL_JAVA" == true ]]; then
    apt-get install -y default-jdk
  fi
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
      info "No separate $package package; OPcache will be validated after installation."
      installed_modules+=("$suffix")
    else
      PHP_SKIPPED_PACKAGES+=("$package")
      warn "$package is unavailable and will be skipped."
    fi
  done

  apt-get install -y "${packages[@]}"
  systemctl enable --now "php${version}-fpm"
  apply_php_configuration "$version"
  verify_php_runtime "$version"

  for suffix in "${installed_modules[@]}"; do
    runtime="$(module_runtime_name "$suffix")"
    /usr/bin/php"$version" -m | grep -qiFx "$runtime" || fatal \
      "PHP $version extension validation failed: $runtime"
  done
}

verify_php_runtime() {
  local version="${1:-$php_version}" cli_bin="/usr/bin/php${version}" cli_version
  [[ -x "$cli_bin" ]] || fatal "Missing PHP CLI binary: $cli_bin"
  cli_version="$($cli_bin -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
  [[ "$cli_version" == "$version" ]] || fatal "PHP CLI mismatch for $version."
  systemctl is-active --quiet "php${version}-fpm" || fatal "php${version}-fpm is not active."
  [[ -S "/run/php/php${version}-fpm.sock" ]] || fatal "PHP-FPM socket missing for $version."
  "$cli_bin" -m | grep -qi '^Zend OPcache$' || fatal "Zend OPcache is not loaded for PHP $version."
  ok "PHP $version CLI, FPM and selected extensions passed validation."
}

configure_phpmyadmin() {
  [[ "$INSTALL_PHPMYADMIN" == true ]] || { info "phpMyAdmin was not selected."; return 0; }
  [[ "$INSTALL_MARIADB" == true ]] || fatal "phpMyAdmin requires MariaDB."
  section "Installing phpMyAdmin at /phpmyadmin/"

  pma_app_password="$(generate_password)"
  export DEBIAN_FRONTEND=noninteractive
  echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
  echo "phpmyadmin phpmyadmin/mysql/app-pass password $pma_app_password" | debconf-set-selections
  echo "phpmyadmin phpmyadmin/app-password-confirm password $pma_app_password" | debconf-set-selections
  echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect none" | debconf-set-selections
  apt-get install -y phpmyadmin
  configure_php_alternatives
  systemctl restart "php${php_version}-fpm"

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
    a2enconf snyt-phpmyadmin >/dev/null
    apache2ctl configtest
    systemctl reload apache2
  else
    cat > /etc/nginx/snippets/phpmyadmin.conf <<EOF
location = /phpmyadmin { return 301 /phpmyadmin/; }
location /phpmyadmin/ {
    root /usr/share/;
    index index.php index.html;
}
location ~ ^/phpmyadmin/(.+\.php)$ {
    root /usr/share/;
    try_files \$uri =404;
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    fastcgi_pass unix:/run/php/php${php_version}-fpm.sock;
}
location ~* ^/phpmyadmin/(.+\.(?:css|js|jpg|jpeg|gif|png|svg|ico|woff|woff2|ttf|map))$ {
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
  python3 -m pip --version
  if python3 -m pip install --help 2>/dev/null | grep -q -- '--break-system-packages'; then
    python3 -m pip install --upgrade Django gunicorn --break-system-packages
  else
    python3 -m pip install --upgrade Django gunicorn
  fi
  [[ -e /usr/local/bin/python ]] || ln -s "$(command -v python3)" /usr/local/bin/python
}

install_nodejs() {
  [[ "$INSTALL_NODEJS" == true ]] || return 0
  section "Installing Node.js"
  local nodesource_ok=false
  if curl -fsSL --retry 3 https://deb.nodesource.com/setup_lts.x -o /tmp/snyt-nodesource.sh \
      && bash /tmp/snyt-nodesource.sh; then
    nodesource_ok=true
  fi
  rm -f /tmp/snyt-nodesource.sh
  if [[ "$nodesource_ok" != true ]]; then
    warn "NodeSource failed; using distribution Node.js packages."
    rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/sources.list.d/nodesource.sources
    apt-get update
  fi
  apt-get install -y nodejs npm || apt-get install -y nodejs
  command -v npm >/dev/null || fatal "npm is unavailable."
  if [[ "$INSTALL_PM2" == true ]]; then
    npm install -g pm2@latest
    pm2 startup systemd -u root --hp /root >/tmp/snyt-pm2-startup.txt 2>&1 || true
  fi
}

configure_redis_repository() {
  if check_release_url "https://packages.redis.io/deb/dists/$VERSION_CODENAME/Release"; then
    install -d -m 0755 /usr/share/keyrings
    curl -fsSL --retry 3 https://packages.redis.io/gpg \
      | gpg --dearmor --yes -o /usr/share/keyrings/redis-archive-keyring.gpg
    chmod 0644 /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $VERSION_CODENAME main" \
      > /etc/apt/sources.list.d/redis.list
    apt-get update
  fi
}

install_redis() {
  [[ "$INSTALL_REDIS" == true ]] || return 0
  configure_redis_repository
  section "Installing Redis"
  if package_has_candidate redis; then apt-get install -y redis; else apt-get install -y redis-server redis-tools; fi
  systemctl daemon-reload
  REDIS_UNIT=""
  local candidate
  for candidate in redis-server.service redis.service; do
    if systemctl start "$candidate" >/dev/null 2>&1; then REDIS_UNIT="$candidate"; break; fi
  done
  [[ -n "$REDIS_UNIT" ]] || fatal "Redis could not be started."
  redis-cli ping | grep -q '^PONG$'
  safe_write_info "Redis Service" "$REDIS_UNIT"
}

install_docker() {
  [[ "$INSTALL_DOCKER" == true ]] || return 0
  section "Installing Docker Engine and Compose"
  apt-get install -y docker.io
  if package_has_candidate docker-compose-v2; then
    apt-get install -y docker-compose-v2
  elif package_has_candidate docker-compose-plugin; then
    apt-get install -y docker-compose-plugin
  else
    apt-get install -y docker-compose
  fi
  systemctl enable --now docker
  docker info >/dev/null
}

configure_crowdsec() {
  [[ "$SECURITY_MODE" != "none" ]] || { info "CrowdSec was not selected."; return 0; }
  section "Installing CrowdSec protection"
  curl -fsSL https://install.crowdsec.net | sh
  apt-get update
  apt-get install -y crowdsec
  cscli collections install crowdsecurity/linux
  if [[ "$web_server" == "nginx" ]]; then
    cscli collections install crowdsecurity/nginx
  else
    cscli collections install crowdsecurity/apache2
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
  if command -v iptables >/dev/null 2>&1 && iptables -V 2>/dev/null | grep -qi nf_tables \
      && package_has_candidate crowdsec-firewall-bouncer-nftables; then
    bouncer_package="crowdsec-firewall-bouncer-nftables"
  fi
  apt-get install -y "$bouncer_package"
  systemctl enable --now crowdsec-firewall-bouncer.service 2>/dev/null || true
  systemctl is-active --quiet crowdsec-firewall-bouncer.service || fatal "CrowdSec firewall bouncer is not active."

  if [[ "$SECURITY_MODE" == "crowdsec-appsec" ]]; then
    apt-get install -y nginx lua5.1 libnginx-mod-http-lua luarocks gettext-base lua-cjson crowdsec-nginx-bouncer
    cscli collections install crowdsecurity/appsec-virtual-patching crowdsecurity/appsec-generic-rules
    cat > /etc/crowdsec/acquis.d/appsec.yaml <<'EOF'
appsec_config: crowdsecurity/appsec-default
labels:
  type: appsec
listen_addr: 127.0.0.1:7422
source: appsec
EOF
    if [[ -f /etc/crowdsec/bouncers/crowdsec-nginx-bouncer.conf ]]; then
      if grep -q '^APPSEC_URL=' /etc/crowdsec/bouncers/crowdsec-nginx-bouncer.conf; then
        sed -i 's|^APPSEC_URL=.*|APPSEC_URL=http://127.0.0.1:7422|' /etc/crowdsec/bouncers/crowdsec-nginx-bouncer.conf
      else
        echo 'APPSEC_URL=http://127.0.0.1:7422' >> /etc/crowdsec/bouncers/crowdsec-nginx-bouncer.conf
      fi
    fi
    systemctl restart crowdsec
    systemctl restart nginx
    ss -lnt | grep -q '127.0.0.1:7422' || warn "CrowdSec AppSec port 7422 was not detected yet."
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
  apt-get install -y mariadb-server mariadb-client
  systemctl enable --now mariadb
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
  safe_write_info "MariaDB Root Authentication" "unix_socket (use: sudo mariadb)"
  safe_write_info "MariaDB Admin User" "$mysql_admin_user"
  safe_write_info "MariaDB Admin Password" "$mysql_admin_password"
  safe_write_info "MariaDB Version" "$(mariadb --version | head -n1)"
}

final_validation() {
  section "Running final validation"
  local version

  configure_php_alternatives
  for version in "${PHP_SELECTED_VERSIONS[@]}"; do
    verify_php_runtime "$version"
  done

  [[ "$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')" == "$php_version" ]] \
    || fatal "Default PHP CLI mismatch."

  if [[ "$web_server" == "apache" ]]; then
    apache2ctl configtest
    systemctl is-active --quiet apache2
  else
    nginx -t
    systemctl is-active --quiet nginx
  fi

  verify_php_through_web_server

  if [[ "$INSTALL_MARIADB" == true ]]; then
    systemctl is-active --quiet mariadb
  fi
  if [[ "$INSTALL_REDIS" == true ]]; then
    redis-cli ping | grep -q '^PONG$'
  fi
  if [[ "$INSTALL_NODEJS" == true ]]; then
    command -v node >/dev/null
    command -v npm >/dev/null
  fi
  if [[ "$INSTALL_PYTHON" == true ]]; then
    command -v python3 >/dev/null
  fi
  if [[ "$INSTALL_COMPOSER" == true ]]; then
    command -v composer >/dev/null
  fi
  if [[ "$INSTALL_DOCKER" == true ]]; then
    systemctl is-active --quiet docker
  fi
  if [[ "$SECURITY_MODE" != "none" ]]; then
    systemctl is-active --quiet crowdsec
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
  safe_write_info "PHP Module Profile" "$PHP_MODULE_PROFILE"
  safe_write_info "PHP Modules" "$(join_by ", " "${PHP_SELECTED_MODULES[@]}")"
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
  install_php_versions
  install_optional_system_tools
  create_primary_website
  configure_phpmyadmin
  install_python_tools
  install_nodejs
  install_redis
  install_docker
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
