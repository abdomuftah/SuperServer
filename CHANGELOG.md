# Changelog

All notable changes to SNYT SuperServer are documented here.

## [3.3.1] - 2026-07-19

### Changed

- The PHP menu now always displays PHP 8.1, 8.2, 8.3, 8.4 and 8.5.
- Every version is labeled `AVAILABLE` or `UNAVAILABLE` using live package checks.
- `all` now explicitly means every version currently marked `AVAILABLE`.
- PHP choices are listed in ascending order for easier selection.

### Fixed

- Users can now see older PHP choices even when the current operating system repository does not publish them.
- Selecting an unavailable PHP version now shows the exact missing core packages instead of silently hiding the version.

## [3.3.0] - 2026-07-19

### Added

- Multi-PHP installation in one run.
- Selection syntax supporting a single option, comma-separated options, ranges, or `all`.
- Default PHP selection for CLI, the primary domain and phpMyAdmin.
- Per-version PHP-FPM installation, configuration and validation.
- `super-sdomain --list-php` command.
- Local installed template directory at `/usr/local/share/snyt-superserver` so new domains do not depend on the GitHub branch state.
- Unified modern and responsive `assets/index.php` template.
- Dynamic starter-page system information including memory, disk, load, uptime and HTTPS state.
- Redesigned installer welcome screen and completion summary.

### Changed

- `super-sdomain` now reads the Let's Encrypt email automatically from `/root/SNYT/serverInfo.txt`.
- The add-domain helper now accepts only the domain and optional PHP version.
- Apache uses explicit per-VirtualHost FPM sockets and disables global PHP handlers to protect Multi-PHP routing.
- Apache phpMyAdmin configuration now uses the selected default FPM socket explicitly.
- The installer records selected, installed and default PHP versions in `serverInfo.txt`.
- Final validation checks every selected PHP-FPM service and socket.
- Web runtime validation supports both pre-SSL HTTP and post-SSL local HTTPS checks.
- Apache and Nginx now share one starter-page template.

### Security

- The starter page intentionally exposes only non-sensitive runtime information.
- Generated database credentials remain restricted to `/root/SNYT/serverInfo.txt`.

## [3.2.2] - 2026-07-19

### Fixed

- Removed duplicate Nginx `try_files` directives on Ubuntu 26.04 / Nginx 1.28+.
- Added a compatibility cleanup for older Nginx templates.
- Included all consumed assets in the release bundle.
- Removed deprecated PHP session directives from the SNYT PHP configuration.

## [3.2.1] - 2026-07-19

### Fixed

- PHP 8.5 OPcache detection when no separate `php8.5-opcache` package is published.
- Automatic Ubuntu Universe repository enablement.
- Improved missing-PHP-package diagnostics.

## [3.2.0] - 2026-07-18

### Added

- Friendly Apache/Nginx choice.
- Complete PHP package validation.
- PHP-FPM runtime and socket validation.
- Automatic SSH-port detection for UFW and Fail2ban.
- Safer previous-installation guard.
- Modern README and structured release bundle.
