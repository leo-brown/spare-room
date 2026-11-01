#!/usr/bin/env bash
# Run from the uploaded source directory on the existing Debian/Ubuntu Apache host.
set -euo pipefail
if [[ $(id -u) -ne 0 ]]; then echo 'Run with sudo.' >&2; exit 1; fi
cd "$(dirname "$0")/.."
command -v python3 >/dev/null
command -v apache2ctl >/dev/null
id spare-room >/dev/null 2>&1 || useradd --system --home-dir /var/lib/spare-room --shell /usr/sbin/nologin spare-room
install -d -m 755 /var/www/spare-room/{backend,public,deploy}
install -m 644 backend/server.py backend/schema.sql /var/www/spare-room/backend/
install -m 644 public/index.html public/privacy.html /var/www/spare-room/public/
if [[ -f public/source.zip ]]; then install -m 644 public/source.zip /var/www/spare-room/public/; fi
install -m 644 deploy/backup.py /var/www/spare-room/deploy/
install -m 644 deploy/spare-room.service deploy/spare-room-backup.service deploy/spare-room-backup.timer /etc/systemd/system/
install -d -m 700 -o spare-room -g spare-room /var/lib/spare-room
install -m 644 deploy/rooms-http.conf /etc/apache2/sites-available/spare-room-http.conf
a2enmod proxy proxy_http headers rewrite ssl reqtimeout
a2ensite spare-room-http
apache2ctl configtest
systemctl reload apache2
systemctl daemon-reload
systemctl enable --now spare-room.service
curl --fail --silent http://127.0.0.1:8791/api/health
# Existing Certbot account is reused; DNS must already resolve to this host.
certbot certonly --webroot -w /var/www/spare-room/public -d rooms.leobrown.co.uk --cert-name rooms.leobrown.co.uk --non-interactive --keep-until-expiring
install -m 644 deploy/rooms-https.conf /etc/apache2/sites-available/spare-room-https.conf
a2ensite spare-room-https
apache2ctl configtest
systemctl reload apache2
systemctl enable --now spare-room-backup.timer
curl --fail --silent https://rooms.leobrown.co.uk/api/health
