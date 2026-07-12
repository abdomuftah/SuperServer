# SNYT SuperServer

A complete Ubuntu and Debian web-server installer maintained by SNYT Hosting.

## Supported systems

- Ubuntu Server 22.04 LTS
- Ubuntu Server 24.04 LTS
- Ubuntu Server 26.04 LTS
- Debian 11 Bullseye
- Debian 12 Bookworm
- Debian 13 Trixie
- amd64 and arm64 where upstream packages are available

The installer detects the Linux distribution and release and architecture automatically. External repositories are only added after their Release metadata is confirmed for the detected distribution codename. When an upstream repository has not published the new Ubuntu release yet, SuperServer safely falls back to distribution packages instead of breaking APT.

## Included software

- Apache or Nginx
- Selectable PHP/PHP-FPM with common extensions
- MariaDB
- phpMyAdmin
- Redis
- Current Node.js LTS and PM2
- Python, pip and Django (`--break-system-packages` retained)
- Composer and Java
- Certbot with automatic renewal
- UFW and Fail2ban
- unattended-upgrades
- Latest Fastfetch release with SNYT MOTD
- Add-domain helper: `super-sdomain`

## Installation

```bash
wget https://link.snyt.xyz/SuperServer -O SuperServer.sh
chmod +x SuperServer.sh
sudo ./SuperServer.sh
```

Run the installer as `root` on a clean supported Ubuntu Server or Debian installation.

## Credentials and logs

SuperServer generates random database credentials. They are not shown in the final terminal screen.

```text
/root/SNYT/serverInfo.txt
```

The directory uses mode `700` and the information file uses mode `600`.

Installation log:

```text
/var/log/snyt-superserver.log
```

## Add another domain

```bash
sudo super-sdomain
```

The helper detects the installed PHP-FPM version, creates the virtual host and requests Let's Encrypt SSL when DNS points to the server.

## Notes

- MariaDB root keeps the distribution's secure Unix-socket authentication. Use `sudo mariadb` locally.
- phpMyAdmin uses the generated `snyt_admin` database administrator stored in `serverInfo.txt`.
- Certbot skips certificate issuance when DNS does not point to the server and prints the command to run later.
- The installer uses newest stable/compatible releases, not beta or development builds.

## Repository policy

- Ubuntu uses the Ondřej PHP PPA only when Release metadata exists for the detected codename.
- Debian uses the Sury PHP repository only when Release metadata exists for the detected codename.
- Redis uses the official Redis APT repository when available, otherwise the distribution package.
- Node.js uses the current NodeSource LTS setup.
- External repositories are never added blindly.
