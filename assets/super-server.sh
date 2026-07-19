#!/usr/bin/env bash
set -Eeuo pipefail
INFO_FILE=/root/SNYT/serverInfo.txt
read_info(){ awk -F': ' -v k="$1" '$1==k{sub(/^[^:]+: /,"");print;exit}' "$INFO_FILE" 2>/dev/null; }
web="$(read_info 'Web Server' || true)"
status(){
  echo "SNYT SuperServer Health"
  echo "======================="
  for unit in ssh "${web/apache/apache2}" mariadb redis-server redis crowdsec docker; do
    systemctl list-unit-files "$unit.service" >/dev/null 2>&1 || continue
    printf '%-22s %s\n' "$unit" "$(systemctl is-active "$unit" 2>/dev/null || true)"
  done
  echo "PHP-FPM:"
  systemctl --no-pager --type=service --state=running 'php*-fpm.service' 2>/dev/null | sed -n '2,$p' || true
  echo "Disk: $(df -h / | awk 'NR==2{print $5" used ("$4" free)"}')"
  echo "Memory: $(free -h | awk '/Mem:/{print $3" / "$2}')"
  echo "Load: $(cut -d' ' -f1-3 /proc/loadavg)"
}
doctor(){
  status
  echo
  echo "Configuration tests"
  [[ "$web" == nginx ]] && nginx -t || apache2ctl configtest
  command -v certbot >/dev/null && certbot certificates || true
  command -v cscli >/dev/null && cscli metrics || true
  systemctl --failed --no-pager
}
case "${1:-menu}" in
  status) status ;;
  doctor) doctor ;;
  domains) cat /root/SNYT/domains.txt 2>/dev/null || echo "No additional domains recorded." ;;
  php) super-sdomain --list-php ;;
  ssl) certbot certificates ;;
  info) sed -E '/[Pp]assword:/s/:.*/: [REDACTED]/' "$INFO_FILE" ;;
  restart)
    [[ "$web" == nginx ]] && systemctl restart nginx || systemctl restart apache2
    systemctl restart "php$(read_info 'Default PHP Version')-fpm"
    echo "Web server and default PHP-FPM restarted."
    ;;
  menu)
    cat <<'MENU'
SNYT SuperServer
1) Status
2) Doctor
3) Domains
4) PHP versions
5) SSL certificates
6) Restart web/PHP
7) Installation information
0) Exit
MENU
    read -r -p "Selection: " choice
    case "$choice" in
      1) exec "$0" status;; 2) exec "$0" doctor;; 3) exec "$0" domains;;
      4) exec "$0" php;; 5) exec "$0" ssl;; 6) exec "$0" restart;;
      7) exec "$0" info;; *) exit 0;;
    esac
    ;;
  *) echo "Usage: super-server [status|doctor|domains|php|ssl|restart|info]"; exit 2 ;;
esac
