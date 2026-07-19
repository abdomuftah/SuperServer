# Changelog

## 3.4.0 — Multi-PHP Wizard and CrowdSec

### Added

- Direct `packages.sury.org/php` repository integration for Ubuntu and Debian.
- PHP 8.1–8.5 selection with live package verification.
- `all` and `all+legacy` PHP selection behavior.
- Essential, All and Custom PHP extension profiles.
- Extension availability verification before installation starts.
- Optional no-email Let’s Encrypt registration.
- Complete initial questionnaire and final installation plan.
- `/root/SNYT/install-plan.conf`.
- Optional phpMyAdmin while retaining `/phpmyadmin/`.
- Optional MariaDB, Redis, Composer, Node.js, PM2, Python, Java, Docker, unattended upgrades and MOTD.
- CrowdSec Security Engine and firewall bouncer.
- Optional Nginx CrowdSec AppSec/WAF.
- `super-server` status and doctor helper.
- Subdomain SSL inheritance for email and no-email accounts.

### Changed

- Replaced Fail2ban with CrowdSec.
- Apache continues to use PHP-FPM only; `mod_php` is intentionally excluded.
- The installer performs only a minimal repository preflight before collecting every user choice.
- No interactive questions are displayed after the final installation confirmation.
- PHP module names are mapped to real Debian packages to avoid duplicate and virtual package errors.

### Retained

- Modern server information `index.php` template.
- Apache/Nginx selection.
- Multi-PHP per-domain FPM sockets.
- Fixed `/phpmyadmin/` URL.
- UFW, Certbot, generated credentials, Redis service compatibility, Fastfetch and SNYT MOTD.

### Test status

- Bash syntax validated for installer and helper scripts.
- PHP syntax validated for the index template.
- Full VM installation matrix still required before marking this release production-stable.
