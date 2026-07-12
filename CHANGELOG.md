# Changelog

## 3.1.4 - 2026-07-12

- Fixed SuperServer version being overwritten by `/etc/os-release`.
- Improved Let's Encrypt handling for Cloudflare-proxied domains.
- SSL failure no longer aborts the complete installation.
- Final screen now shows HTTP when SSL is still pending.
- Retained robust Redis linked-service handling.

## 3.1.3

- Fixed Redis 8.x systemd linked-unit handling on Ubuntu 26.04 and recent Debian releases.
- Start Redis through the available alias without calling `systemctl enable` on a linked unit.
- Use systemd package presets only as a non-fatal fallback.


## 3.1.2

- Fixed Redis startup on systems where `redis.service` is a linked alias.
- SuperServer now resolves and enables the canonical Redis systemd unit automatically.
- Saves the detected Redis service name in `serverInfo.txt`.

## 3.1.1

- Fixed installation failure when `pip` is managed by Ubuntu/Debian and has no Python `RECORD` file.
- SuperServer now keeps the distribution-provided pip package and uses it directly for Django installation.

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
