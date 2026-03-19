# WORKLOG
Last updated: 2026-03-19

## Remote host (active)
- Provider: AliCloud ECS
- API host: `api.tutor1on1.org`
- Website host: `www.tutor1on1.org` (`tutor1on1.org` redirects here)
- SSH host: `43.99.59.107`
- SSH user: `ecs-user`
- SSH key: `C:\Users\kl\.ssh\id_rsa`
- API service: `family-teacher-api.service`
- Nginx reverse proxy: HTTPS entry, internal file serving via `X-Accel-Redirect`

## Important paths
- App deploy root: `/opt/family_teacher_remote`
- API binary: `/opt/family_teacher_remote/bin/family-teacher-api`
- Env file: `/etc/family_teacher_remote/env`
- Logs: `/var/log/family_teacher_remote/app.log`
- Storage root: `/var/lib/family_teacher_remote/storage`
- Public download root: `/var/lib/family_teacher_remote/public`
- Website static root: `/var/www/tutor1on1_site`

## Local data paths (this machine)
- `getApplicationDocumentsDirectory()` resolves to `C:\Mac\Home\Documents`
- Live local app DB: `C:\Mac\Home\Documents\family_teacher.db`
- Live local session sync cache: `C:\Mac\Home\Documents\sync_artifacts\sessions\`

## Operational requirements
- `STORAGE_ROOT` must be writable by `ftapp` (API user).
- Nginx worker (`nginx`) must be able to read/traverse storage paths (current fix: `nginx` in `ftapp` group).
- API upload max size and Nginx `client_max_body_size` must match.

## Common checks
- SSH smoke: `ssh ecs-user@tutor1on1.org "hostname && whoami"`
- Service status: `sudo systemctl status family-teacher-api.service`
- API logs: `sudo tail -n 200 /var/log/family_teacher_remote/app.log`
- Nginx logs: `sudo tail -n 200 /var/log/nginx/access.log`
- Health check: `curl https://api.tutor1on1.org/health`

## SSH notes
- Default remote user is `ecs-user`, not `root` or local Windows usernames.
- Always try the explicit key path first: `-i C:\Users\kl\.ssh\id_rsa -o IdentitiesOnly=yes`.
- Default remote host for manual ops is `tutor1on1.org`, so prefer `ssh ecs-user@tutor1on1.org`.
- If `ssh ecs-user@tutor1on1.org` fails to log in, stop and report the failure instead of retrying other usernames or host variants.
- If SSH fails with `Permission denied (publickey,...)`, verify the remote user before blaming the key.
- If SSH fails with `banner exchange: Connection to UNKNOWN port -1: Connection refused` and `Test-NetConnection 43.99.59.107 -Port 22` reports `TcpTestSucceeded=False`, port `22` is closed or blocked from the current network, so server log inspection is blocked at transport level.

## TLS notes
- Canonical public API origin is `https://api.tutor1on1.org`.
- Public TLS is managed by `certbot` on the host with the nginx plugin.
- Port `80/tcp` must stay open in both Alibaba security group and host firewall for HTTP-01 issuance and renewal.

## Deployment steps (quick)
1. Build and replace API binary in `/opt/family_teacher_remote/bin/`.
2. `sudo systemctl restart family-teacher-api.service`
3. Verify health endpoint and log tail.

Historical setup timeline moved to `LOGBOOK.md`.

## Remote server updates (2026-03-19, Android + Windows + website release)
- Published canonical Android APK to `https://api.tutor1on1.org/downloads/family_teacher.apk`.
- Published canonical Windows ZIP to `https://api.tutor1on1.org/downloads/family_teacher.zip`.
- Synced the static website under `/var/www/tutor1on1_site`.
- Current canonical downloads:
  - APK SHA-256: `9ef48c7754843a6e55e26dbcf5de463198a319e495d62fb653b201245c954790`
  - ZIP SHA-256: `7ba173c9c38584c422d19d4f73209de7fb3bdf7227945aa21554196155c9d054`

## Remote server updates (2026-03-08, current Windows release)
- Added sync download endpoints:
  - `GET /api/sync/download-manifest`
  - `POST /api/sync/download-fetch`
- Deployed updated sync backend, verified local/public health, and republished the canonical Windows desktop ZIP.
- Current canonical download:
  - URL: `https://43.99.59.107/downloads/family_teacher.zip`
  - SHA-256: `8e344223866c82c37d742b192f1e5f94c86dff3de4b035acc780a664504807d2`
- Packaging now uses `System.IO.Compression` after replacing `tar -a` for Windows Explorer compatibility.

## Remote server updates (2026-02-26, progress sync batch)
- Added API endpoint `POST /api/progress/sync/upload-batch` and deployed to host.
- Updated `progress_sync.go` and `routes.go`, rebuilt binary with `/usr/local/go/bin/go build`, restarted `family-teacher-api.service`.
- Verified:
  - health endpoint `https://43.99.59.107/health` returned `{"status":"ok"}`.
  - batch endpoint responds (unauthorized without token), confirming route is active.

## Remote server updates (2026-02-26, bundle version controls)
- Added upload dedupe by hash in API upload flow: if the uploaded bundle hash matches latest version, API returns `status=unchanged` and does not create a new version row.
- Added server retention policy in upload flow: keep latest 5 versions per bundle; prune older DB rows and delete old files.
- Added teacher APIs:
  - `GET /api/teacher/courses/:id/bundle-versions`
  - `POST /api/teacher/courses/:id/bundle-versions/:versionId/delete`
- Deployed backend changes:
  - copied updated `bundles.go` and `routes.go` to `/opt/family_teacher_remote`
  - built binary with `/usr/local/go/bin/go build`
  - restarted `family-teacher-api.service`
  - verified `curl -k https://43.99.59.107/health` returned `{"status":"ok"}`

## Remote server updates (2026-02-26)
- Investigated student import failure after download for `special_relativity`.
- Verified `bundle_version_id=10` downloaded from server and mapped to `/var/lib/family_teacher_remote/storage/bundles/3/1772075735.zip`.
- Verified server bundle includes `contents.txt` and all required lecture files (no missing lecture IDs from parsed contents).
- Added server-side bundle validation in `bundles.Upload` to reject invalid uploads:
  - require `contents.txt` or `context.txt`
  - parse node IDs from contents
  - require lecture file per node (`<id>_lecture.txt` or `<id>/lecture.txt`)
  - ignore AppleDouble/macOS metadata entries (`._*`, `__MACOSX/*`)
- Deployed updated API binary and restarted `family-teacher-api.service`; health check returned OK.

## Root-cause note (2026-02-26, student download import)
- Investigated repeated student error: `Missing file: ...\\contents.txt (or ...\\context.txt)` immediately after marketplace download.
- Verified server bundle integrity:
  - latest DB row for `special_relativity` points to `bundles/3/1772077823.zip`
  - zip contains `contents.txt` and prompt metadata.
- Root cause was client-side race in `CourseBundleService`:
  - used `extractArchiveToDisk(...)` without `await`.
  - `archive` 3.x extraction API is async, so import sometimes started before extraction finished.
- Fix: await extraction in both `extractBundleFromFile` and `extractBundleFromBytes`.
