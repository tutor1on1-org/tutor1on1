# Work Log

Date: 2026-02-25

## Remote server setup (43.99.59.107)
- Verified host: Alibaba Cloud Linux 3.2104 (OpenAnolis).
- Installed: git, jq, unzip, tar, gcc, make.
- Installed Go 1.22.5 at `/usr/local/go`.
- Installed sqlc v1.30.0 at `/usr/local/bin/sqlc`.
- Created service user `ftapp` and directories:
  - `/opt/family_teacher_remote`
  - `/var/log/family_teacher_remote`
  - `/etc/family_teacher_remote`
- Created env stub: `/etc/family_teacher_remote/env` (placeholders for DB_DSN/JWT_SECRET).
- Installed MySQL Server 8.0 via `dnf` and started `mysqld` (enabled at boot).
- Set MySQL root password, created database `family_teacher`, and app user `ftapp` (localhost + 127.0.0.1) with privileges.
- Fixed `/etc/profile.d/which2.sh` to use absolute paths for `readlink`/`basename` and stop login errors.
- Wrote `/etc/family_teacher_remote/env` with DB_DSN and JWT_SECRET.
- Recorded temporary credentials in `SECRETS.md`.
- Applied initial schema migration `db/migrations/0001_init.up.sql` to `family_teacher`.
- Deployed `/opt/family_teacher_remote`, ran `go mod tidy`, built `family-teacher-api` binary.
- Created and enabled `family-teacher-api.service` (systemd) and verified `/health` returns OK.
- Installed Nginx + OpenSSL, generated self-signed TLS cert, and configured reverse proxy on 443.
- Updated API bind to `127.0.0.1:8080` behind Nginx, verified `https://43.99.59.107/health` returns OK.
- Enabled firewalld: allowed `ssh` + `https`, removed `http` + `8080/tcp`.
- Added systemd log file output and logrotate for `/var/log/family_teacher_remote/app.log`.
- Added OSS config scaffolding in Go API and redeployed.
- Added Aliyun OSS Go SDK integration with signed URL helpers and OSS env validation.
- Added admin CLI (`cmd/admin`) for listing/moderating marketplace reports and setting teacher/course status.
- Fixed Go build cache path by moving `GOPATH/GOMODCACHE` to `/var/lib/family_teacher_remote/go` to avoid `go/pkg/mod` inside the repo.
- Built and deployed updated API + admin binary, verified `/health` is OK over HTTPS.
- Updated Nginx `server_name` to the public IP (self-signed cert) and reloaded.
- Implemented filesystem bundle storage: API upload/download endpoints with X-Accel-Redirect.
- Configured Nginx internal `/_files/` alias to `/var/lib/family_teacher_remote/storage` and set `client_max_body_size` to 1GB.
- Created storage root `/var/lib/family_teacher_remote/storage` with `ftapp` ownership.
- Added daily storage backups to `/var/backups/family_teacher_remote` with 30-day retention.
- Added `STORAGE_ROOT` and `BUNDLE_MAX_BYTES` to server env and redeployed API.
- Removed OSS code paths and env usage; API now uses filesystem storage only.
- Added admin CLI commands for creating teachers, courses, bundles, and bundle versions.
- Added SQL seed helper `db/queries/seed.sql`.
- Cleaned `/etc/family_teacher_remote/env` to remove OSS_* entries.

## Remote server updates (2026-02-25)
- Added auth migration `0002_auth_username_recovery` (username column + password_resets table) and applied it to `family_teacher`.
- Updated API auth endpoints to use username + recovery email, plus change-password and recovery flows.
- Added `RECOVERY_TOKEN_TTL_MINUTES=30` to `/etc/family_teacher_remote/env`.
- Rebuilt `/opt/family_teacher_remote/bin/family-teacher-api` and restarted `family-teacher-api.service`.
- Verified `/health` on `127.0.0.1:8080` returned OK.
- Ran `scripts/test_auth.ps1` to simulate registration, change-password, and recovery flows.

## Remote server updates (2026-02-25)
- Added SMTP mailer support for recovery emails; request-recovery now sends email when SMTP is enabled.
- Set `RECOVERY_TOKEN_ECHO=true` and `SMTP_ENABLED=false` in `/etc/family_teacher_remote/env` for dev testing.
- Rebuilt `/opt/family_teacher_remote/bin/family-teacher-api` and restarted `family-teacher-api.service`.
- Verified `/health` on `127.0.0.1:8080` returned OK.
- Re-ran `scripts/test_auth.ps1` after SMTP changes.

## Remote server updates (2026-02-25)
- Added per-IP rate limiting for auth endpoints (register/login/recovery/change/refresh) and anti-enumeration adjustments in request-recovery.
- Rebuilt `/opt/family_teacher_remote/bin/family-teacher-api` and restarted `family-teacher-api.service`.
- Verified `/health` on `127.0.0.1:8080` returned OK.
- Re-ran `scripts/test_auth.ps1` after rate limit changes.

## Remote server updates (2026-02-25)
- Added marketplace APIs: catalog listing, teacher courses, enrollment requests/approvals, and student enrollments.
- Deployed new handlers to `/opt/family_teacher_remote`, rebuilt API, and restarted `family-teacher-api.service`.
- Verified `/health` on `127.0.0.1:8080` returned OK.

## Remote server updates (2026-02-26)
- Built `/opt/family_teacher_remote` API with session sync handlers and migration changes.
- Moved new `family-teacher-api` binary into `/opt/family_teacher_remote/bin`.
- Restarted `family-teacher-api.service` and verified it is active.

## Remote server updates (2026-02-26)
- Investigated student marketplace download `403` failures on `/api/bundles/download`.
- Confirmed Nginx access log showed `403` with body size `153` (Nginx error page), indicating file read permission issue during `X-Accel-Redirect`.
- Verified bundle files were `-rw-r----- ftapp:ftapp` under `/var/lib/family_teacher_remote/storage/bundles`.
- Fixed server permissions path by adding Nginx worker user to `ftapp` group:
  - `sudo usermod -a -G ftapp nginx`
  - `sudo systemctl restart nginx`
- Verified Nginx user can read bundle files (`sudo -u nginx head -c 4 ...` returned ZIP magic `504b0304`).

## Known issues
- Shell prints errors from `/etc/profile.d/which2.sh` because `readlink`/`basename` not found in PATH. Not blocking, but should be fixed.
