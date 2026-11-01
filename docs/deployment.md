# Deployment

The live hostname is `rooms.leobrown.co.uk`. Its DNS must resolve to the existing Apache host. The app uses a dedicated loopback process on port 8791 and never replaces other apps' virtual hosts or databases.

1. Upload a clean source directory to a staging folder on the server.
2. Produce `public/source.zip` from tracked files using `git archive --format=zip --prefix=spare-room/ HEAD > public/source.zip`.
3. From the source folder run `sudo bash deploy/install.sh`. This installs files in `/var/www/spare-room`, creates the unprivileged `spare-room` user, starts the systemd API, adds dedicated Apache virtual hosts, obtains a TLS certificate using the host's existing Certbot account and enables the daily backup timer.
4. Check `https://rooms.leobrown.co.uk/api/health`, the landing/privacy pages and `/source.zip`.

Prerequisites: Python 3.11+, Apache 2.4 with proxy_http/headers/rewrite/ssl/reqtimeout, Certbot, sudo and correct DNS. No package installation is needed for the API. Runtime configuration uses paths, not database passwords or API tokens. The database and its WAL are readable only by the dedicated service account. The app path is root-owned and read-only to the service. TLS renewals use the host's Certbot timer and its existing Apache reload renewal hook.

## Update

Upload a new clean version, install its backend/public files, regenerate the matching source ZIP and restart `spare-room.service`. Do not replace `/var/lib/spare-room`. The initial schema uses `CREATE TABLE IF NOT EXISTS`; future schema changes need explicit migrations before restarting. Validate with `apache2ctl configtest` before reloading Apache.

## Operations

```sh
sudo systemctl status spare-room.service
sudo journalctl -u spare-room.service --since today
sudo systemctl status spare-room-backup.timer
sudo systemctl start spare-room-backup.service
sudo certbot renew --dry-run
```

Daily SQLite online backups run at 03:15 UTC with 14-day retention at `/var/lib/spare-room/backups`. Files are private to the service. Backups are local to this host; configure an encrypted off-site destination if disaster recovery is needed. To restore, stop the service, preserve the current database/WAL/SHM, restore a consistent backup with service-account ownership and mode 0600, remove stale WAL/SHM only after preserving them, then restart and check integrity.

## Apple setup

For personal installation, select your Apple team in Xcode and run on a trusted iPhone. For TestFlight/App Store, register the bundle ID, create the App Store Connect record, set your signing team, archive and upload. These account-owned signing steps require Apple account access. Review App Store privacy disclosures using the supplied privacy page and manifest. The shipped background-fetch path requires no APNs key or paid push service.

## Source hygiene

Only app code, server code, infrastructure templates, synthetic tests and documentation belong in Git/source ZIP. Never include `/var/lib/spare-room`, backups, real accounts, original voice notes, `.env` secrets, signing files, tokens or source repository credentials. The downloadable ZIP is generated from tracked files and excludes its own ignored output.
