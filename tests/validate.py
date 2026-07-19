#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SHELL_FILES = [
    ROOT / "SuperServer.sh",
    ROOT / "assets/apache_setup.sh",
    ROOT / "assets/nginx_setup.sh",
    ROOT / "assets/super-server.sh",
]

errors: list[str] = []

for path in SHELL_FILES:
    text = path.read_text(encoding="utf-8")
    functions = re.findall(r"(?m)^([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{", text)
    duplicates = sorted({name for name in functions if functions.count(name) > 1})
    if duplicates:
        errors.append(f"{path.relative_to(ROOT)} has duplicate functions: {', '.join(duplicates)}")

main = (ROOT / "SuperServer.sh").read_text(encoding="utf-8")
version_match = re.search(r'^SUPERSERVER_VERSION="([^"]+)"', main, re.M)
if not version_match:
    errors.append("SUPERSERVER_VERSION is missing")
else:
    version = version_match.group(1)
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    if f"v{version}" not in readme:
        errors.append(f"README does not mention v{version}")
    if f"## {version}" not in changelog:
        errors.append(f"CHANGELOG does not contain a {version} section")

if "original installer functions remain above" in main.lower():
    errors.append("legacy override implementation text is still present")

# Runtime scripts must discover the real FPM listener instead of assuming one.
for path in [ROOT / "SuperServer.sh", ROOT / "assets/apache_setup.sh", ROOT / "assets/nginx_setup.sh"]:
    text = path.read_text(encoding="utf-8")
    if "php_fpm_listen_value" not in text:
        errors.append(f"{path.relative_to(ROOT)} does not discover PHP-FPM listeners")


# PHP repository discovery must not destroy the wizard selection. This bug can
# make provider validation succeed with an empty PHP plan.
discover_match = re.search(
    r"discover_php_versions\(\)\s*\{(?P<body>.*?)^\}",
    main,
    re.M | re.S,
)
if not discover_match:
    errors.append("discover_php_versions function is missing")
elif "PHP_SELECTED_VERSIONS=()" in discover_match.group("body"):
    errors.append("discover_php_versions clears PHP_SELECTED_VERSIONS")

# /run is temporary. The installer and both domain helpers must recreate the
# PHP runtime directory before restarting PHP-FPM.
for path in [ROOT / "SuperServer.sh", ROOT / "assets/apache_setup.sh", ROOT / "assets/nginx_setup.sh"]:
    text = path.read_text(encoding="utf-8")
    if "install -d -o www-data -g www-data -m 0755 /run/php" not in text:
        errors.append(f"{path.relative_to(ROOT)} does not recreate /run/php")


# CrowdSec AppSec follows the current acquisition schema and must wire the
# Nginx bouncer to the local AppSec listener.
if "appsec_configs:" not in main:
    errors.append("CrowdSec AppSec acquisition does not use appsec_configs")
if "APPSEC_URL=http://127.0.0.1:7422" not in main:
    errors.append("CrowdSec Nginx bouncer is not pointed at AppSec")

# PHP settings should be additive fragments, not replacement distro php.ini
# files that can vary between PHP versions.
if 'conf_dir/99-snyt.ini' not in main:
    errors.append("PHP configuration is not installed as a conf.d fragment")

# Verify local README assets.
readme = (ROOT / "README.md").read_text(encoding="utf-8")
for rel in re.findall(r'(?:src=|]\()"?(\.\/assets\/readme\/[^)"\s>]+)', readme):
    target = ROOT / rel[2:]
    if not target.exists():
        errors.append(f"README asset is missing: {rel}")

required = [
    "assets/php.ini",
    "assets/index.php",
    "assets/ApacheExample.conf",
    "assets/nginxExample.conf",
    "assets/apache_setup.sh",
    "assets/nginx_setup.sh",
    "assets/super-server.sh",
]
for rel in required:
    if not (ROOT / rel).is_file():
        errors.append(f"required file missing: {rel}")

if errors:
    print("Validation failed:")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)

print("Static project validation passed.")
