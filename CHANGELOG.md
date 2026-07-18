# Changelog

All notable changes to **SNYT SuperServer** are documented here.

## [3.2.0] - 2026-07-19

### Added

- Friendly Apache/Nginx selection with descriptions and confirmation.
- Automatic detection of the effective OpenSSH port.
- UFW and Fail2ban configuration for custom SSH ports.
- Complete PHP-version discovery based on CLI, FPM and required extensions.
- Exact PHP selection from only complete versions available through APT.
- PHP CLI/FPM/socket/extension validation.
- Temporary local web request that confirms the selected PHP version is served by Apache or Nginx.
- Final required-service validation before installation success is reported.
- Previous-installation guard with an explicit `--force` testing option.
- `--version` and `--help` command-line options.
- NodeSource failure fallback to distribution Node.js packages.
- phpMyAdmin post-install PHP revalidation.
- Interactive PHP-FPM selection in both `super-sdomain` helpers.
- Per-site PHP-FPM socket binding for Apache VirtualHosts.
- Domain creation history in `/root/SNYT/domains.txt`.
- Dynamic HTTP/HTTPS phpMyAdmin URL in `serverInfo.txt`.

### Changed

- SuperServer no longer installs the generic `phpX.Y` meta package.
- PHP core and optional packages are handled separately.
- Apache always uses PHP-FPM instead of mod_php.
- The selected PHP alternatives are re-applied after phpMyAdmin installation.
- Redis repository and service handling are safer on new Ubuntu/Debian releases.
- Python keeps `--break-system-packages` where supported without trying to replace the APT-managed pip package.
- Installer output, errors, summary and README were redesigned.
- Credentials, log and state files use restricted permissions.

### Fixed

- Selecting a PHP version whose CLI package existed but whose FPM or required extensions were missing.
- PHP versions other than 8.2 failing later during FPM service activation.
- Generic PHP packages pulling an unintended default PHP stack or Apache module.
- phpMyAdmin URL being recorded as HTTPS when certificate issuance failed.
- UFW assuming SSH always listens on port 22.
- Fail2ban using the wrong port on hardened SSH installations.
- Apache add-domain requests not actually binding the site to the requested PHP version.
- Redis linked-unit enable errors.

### Validation status

- Bash syntax validation completed.
- Full installation testing must be completed on clean VM snapshots before production release approval.

## [3.1.4]

- Previous public repository version before the web-server and PHP reliability update.
