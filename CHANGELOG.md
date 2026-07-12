# Changelog

## 3.1.0

- Added Debian 11, 12 and 13 support.
- Kept Ubuntu 22.04, 24.04 and 26.04 support.
- Added distribution-aware repository setup: Ubuntu PPAs and Debian Sury PHP.
- Added repository Release metadata checks before enabling third-party sources.
- Added Redis package and service-name compatibility across distributions.
- Added portable MySQL development package selection.
- Added dynamic optional PHP extension detection.
- Removed unused legacy `super-sdomain` wrapper copies and inactive Glances service asset.
- Retained random credentials, protected `serverInfo.txt`, phpMyAdmin, Certbot, Fail2ban, unattended-upgrades, Fastfetch/MOTD, Node.js LTS, PM2 and Django with `--break-system-packages`.
