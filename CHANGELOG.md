# Changelog

## 3.5.2 — CrowdSec firewall-bouncer recovery on Ubuntu 26.04

- Worked around the upstream CrowdSec firewall-bouncer 0.0.34 post-installation bug seen on Ubuntu 26.04.
- Catch the package post-install failure instead of terminating SuperServer immediately.
- Wait for the CrowdSec Local API health endpoint before registering the remediation component.
- Generate a dedicated `snyt-firewall-bouncer` key with `cscli bouncers add -o raw`.
- Store `api_url`, `api_key`, and firewall mode in the officially supported `.yaml.local` override.
- Restart and validate the bouncer before completing the interrupted dpkg configuration.
- Added service, journal, and bouncer-log diagnostics if remediation still cannot start.
- Added static validation that the package install is wrapped by the recovery function and that placeholder API keys are not trusted.

## 3.5.1 — Fully non-interactive execution and nounset audit

- Suppressed Composer's root-user confirmation after the installation plan is approved by setting `COMPOSER_ALLOW_SUPERUSER=1` and non-interactive mode.
- Fixed an unbound-variable failure in `ensure_php_fpm_ready` caused by referencing `version` inside the same `local` declaration that initialized it.
- Fixed the same latent nounset bug in `verify_php_runtime` before it could fail during later validation.
- Fixed equivalent same-declaration bugs in both Apache and Nginx `super-sdomain` helpers.
- Added non-interactive environment settings for APT list changes, needrestart, UCF, Composer and npm after final confirmation.
- Extended static project validation to reject local declarations that reference a variable assigned earlier in the same command.
- Added validation that Composer root/non-interactive protection remains present.

## 3.5.0 — Clean core and resilient package sources

- Removed the duplicated legacy function implementations that had accumulated in the single-file installer.
- Fixed the PHP web-runtime failure caused by assuming `/run/php/phpX.Y-fpm.sock` always exists.
- Added dynamic PHP-FPM listener discovery for Unix sockets and TCP listeners.
- Added PHP-FPM configuration tests, service recovery, listener wait loops, and journal diagnostics.
- Reordered package installation so general APT transactions finish before the final PHP-FPM validation and website creation.
- Added safe one-at-a-time provider fallback chains for PHP, MariaDB, Redis, Node.js, Docker, Certbot and Composer.
- Kept CrowdSec on its official repository and prevented unsafe cross-codename repository mixing.
- Updated `super-sdomain` for dynamically detected PHP-FPM endpoints.
- Moved Django and Gunicorn into an isolated Python virtual environment instead of modifying distribution-managed Python packages.
- Added provider details to `/root/SNYT/serverInfo.txt`.
- Strengthened final validation and failure diagnostics.
- Fixed provider discovery accidentally clearing the PHP versions chosen in the wizard.
- Added a persistent `/run/php` tmpfiles rule and runtime-directory recovery before every FPM restart.
- Changed PHP tuning from replacing the distribution `php.ini` to isolated `conf.d/99-snyt.ini` fragments.
- Corrected CrowdSec AppSec acquisition syntax, configured the Nginx bouncer `APPSEC_URL`, and added listener validation.
- Added a PyPI-to-distribution fallback for Django and Gunicorn.

## 3.4.2 — Keyboard checklists and web PHP validation fix

- Added interactive terminal checklists for every multi-select screen.
- Use the Up and Down arrow keys to move, Space to toggle, and Enter to confirm.
- Retained the number/range checklist as an automatic fallback for non-interactive or limited terminals.
- Fixed the primary-domain PHP validation test being blocked by the Nginx hidden-file rule.
- Runtime validation now uses a randomized non-hidden PHP filename.
- Added HTTP status and web-server error-log diagnostics when PHP validation fails.
- Updated README keyboard instructions and release badge.

## 3.4.1 — Wizard-first checklists and optional-component fix

- Moved all visible package updates and repository changes until after the final installation-plan approval.
- Added pure Bash checkbox-style toggle menus for PHP versions, custom PHP extensions, and optional components.
- Fixed the installation abort caused by a false optional Java condition under strict Bash error handling.
- Replaced optional `test && command` chains with explicit `if` blocks throughout the active installer path.
- Added non-interactive post-approval validation for selected Sury PHP releases.
- Missing optional PHP extension packages are now reported and skipped without asking questions mid-installation.
- Separated mandatory foundation packages from optional Composer, Python, and Java packages.
- Improved final validation for installations where optional components are disabled.

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
