# WORKLOG
Last updated: 2026-03-31

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

## Public client release (2026-03-25, v1.0.1)
- Published Android APK:
  - URL: `https://api.tutor1on1.org/downloads/Tutor1on1.apk`
  - SHA-256: `80fd36ad8534dcf7431b1982ed00cd4f27e53b20985aaf1a4156da71122f12ab`
- Published Windows ZIP:
  - URL: `https://api.tutor1on1.org/downloads/Tutor1on1.zip`
  - SHA-256: `766352fbe1ff6e959741c42b94918dc144722e1a1fe7cd5c422e64688cf3d445`
  - Local ZIP validation passed with required entry `tutor1on1.exe`.
- Published GitHub Release:
  - URL: `https://github.com/tutor1on1-org/tutor1on1/releases/tag/v1.0.1`
  - Assets: `Tutor1on1.apk`, `Tutor1on1.zip`, `SHA256SUMS.txt`
- Website sync completed:
  - Root: `https://www.tutor1on1.org`
  - Shared `web/site.js` now targets GitHub tag `v1.0.1`, and localized Windows install pages now instruct users to run `tutor1on1.exe`.
- Release-tool lessons applied:
  - `scripts/validate_project.ps1` now fails fast on non-zero step exit codes.
  - Windows packaging skips case-insensitive self-deletion when legacy `Tutor1on1.exe` and expected `tutor1on1.exe` refer to the same NTFS path.
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

## Deployment caveat
- The live Go module root on the host is `/opt/family_teacher_remote` with `go.mod` there, not `/opt/family_teacher_remote/remote`.
- If the remote source tree is stale or missing files and `go build` on the host fails with undefined symbols that do exist locally, prefer local `GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build` and upload the binary instead of trying to repair the host tree ad hoc.

Historical setup timeline moved to `LOGBOOK.md`.

## Remote server updates (2026-04-01, state1-first sync topology deploy)
- Pushed commit `d363fc9082158fe5b82c6ade13deb12408329a1b` to `origin/simple`.
- Uploaded a freshly cross-compiled Linux API binary and deployed it to `/opt/family_teacher_remote/bin/family-teacher-api`.
- Applied production schema additions for course/enrollment sync state1/state2 tables and sync `content_hash` columns.
- Restarted `family-teacher-api.service`; current service start time is `Wed 2026-04-01 04:58:17 CST`.
- Backup:
  - MySQL dump path: `/home/ecs-user/db_backups/family_teacher_20260401_045816_pre_state1_topology.sql.gz`
  - Clean follow-up MySQL dump with `--no-tablespaces`: `/home/ecs-user/db_backups/family_teacher_20260401_052001_post_state1_topology_notablespaces.sql.gz`
  - API binary backup: `/opt/family_teacher_remote/bin/family-teacher-api.20260401_045816.bak`
- Verified:
  - public health endpoint `https://api.tutor1on1.org/health` returned `200 {"status":"ok"}` after restart.
  - unauthenticated `GET https://api.tutor1on1.org/api/teacher/courses/sync-state1` returned `401 unauthorized`.
  - unauthenticated `GET https://api.tutor1on1.org/api/enrollments/sync-state1` returned `401 unauthorized`.
  - unauthenticated `GET https://api.tutor1on1.org/api/sync/download-state1` returned `401 unauthorized`.

## Remote client artifact refresh (2026-04-01, post state1-first sync deploy)
- Ran `scripts/release_public.ps1 -SkipGit` after backend deploy completed.
- Republished canonical Android APK to `https://api.tutor1on1.org/downloads/Tutor1on1.apk`.
- Republished canonical Windows ZIP to `https://api.tutor1on1.org/downloads/Tutor1on1.zip`.
- Republished GitHub release assets under `https://github.com/tutor1on1-org/tutor1on1/releases/tag/v1.0.1`.
- Republished the website under `https://www.tutor1on1.org/`.
- Verified:
  - APK SHA-256: `b70c9337f25d586a109aba3e54a2f8aa33427ca6bba72957ca4634c6769f14fe`
  - ZIP SHA-256: `aaa010f691d2d135b6f8826f2cc3e961bd92047b00ec44c98083190ee0fc60e1`
  - canonical APK URL returned HTTP `200`.
  - canonical ZIP URL returned HTTP `200`.
  - website root returned HTTP `200`.
  - GitHub release asset URLs for `Tutor1on1.apk` and `Tutor1on1.zip` returned HTTP `302` to release asset storage.

## Remote server updates (2026-03-31, sync-state2 route deploy)
- Deployed updated API binary to `/opt/family_teacher_remote/bin/family-teacher-api` after the public APK started requiring `/api/teacher/courses/sync-state2` and `/api/enrollments/sync-state2`.
- Restarted `family-teacher-api.service`; current service start time is `Tue 2026-03-31 11:20:20 CST`.
- Backup:
  - MySQL pre-deploy dump: `/home/ecs-user/db_backups/family_teacher_20260331_031758_pre_sync_state2_routes.sql.gz`
  - API binary backup: `/opt/family_teacher_remote/bin/family-teacher-api.20260331_031837.bak`
- Verified:
  - public health endpoint `https://api.tutor1on1.org/health` returned `200 {"status":"ok"}` after restart.
  - unauthenticated `GET https://api.tutor1on1.org/api/teacher/courses/sync-state2` now returns `401 unauthorized` instead of `404`, proving the route is live.
  - unauthenticated `GET https://api.tutor1on1.org/api/enrollments/sync-state2` now returns `401 unauthorized` instead of `404`, proving the second route is live.
  - `scripts/test_auth.ps1 -BaseUrl "https://api.tutor1on1.org"` progressed through register/login/change-password/new-login and stopped only at the expected production recovery-token step because `RECOVERY_TOKEN_ECHO=false` and no `FT_RECOVERY_TOKEN` was provided.

## Remote server updates (2026-03-31, sync download-state incremental aggregate deploy)
- Applied DB migration `remote/db/migrations/0012_sync_download_state.up.sql` on production.
- Deployed updated API binary to `/opt/family_teacher_remote/bin/family-teacher-api`.
- Restarted `family-teacher-api.service`; current service start time is `Tue 2026-03-31 14:25:39 CST`.
- Backup:
  - MySQL pre-deploy dump: `/home/ecs-user/db_backups/family_teacher_20260331_062538_pre_sync_download_state2_agg.sql.gz`
  - API binary backup: `/opt/family_teacher_remote/bin/family-teacher-api.20260331_062538.bak`
- Verified:
  - public health endpoint `https://api.tutor1on1.org/health` returned `200 {"status":"ok"}` after restart.
  - unauthenticated `GET https://api.tutor1on1.org/api/sync/download-state2` now returns `401 unauthorized`, proving the new state2 route is live.
  - unauthenticated `GET https://api.tutor1on1.org/api/sync/download-state1` now returns `401 unauthorized`, proving the new state1 route is live.
  - unauthenticated `GET https://api.tutor1on1.org/api/sync/download-manifest` now returns `401 unauthorized`, proving the compatibility route is live on the same deployment.
  - `scripts/test_auth.ps1 -BaseUrl "https://api.tutor1on1.org"` progressed through register/login/change-password/new-login and stopped only at the expected production recovery-token step because `RECOVERY_TOKEN_ECHO=false` and no `FT_RECOVERY_TOKEN` was provided.

## Remote client artifact refresh (2026-03-31, post sync-state2 fix)
- Republished canonical Android APK to `https://api.tutor1on1.org/downloads/Tutor1on1.apk`.
- Republished canonical Windows ZIP to `https://api.tutor1on1.org/downloads/Tutor1on1.zip`.
- Verified candidate-first upload, remote SHA-256 match, and canonical HTTP 200 for both artifacts.
- Current canonical downloads:
  - APK SHA-256: `89428cd53686fada3737993abf20f668b940754b2ad210b9d91d61ad640cb30b`
  - ZIP SHA-256: `49bb884badd17b93e076dc39662fa335103c0fc1b3fe1a16b6eac3941df33738`

## Remote server updates (2026-03-25, moderation reject fix + production cleanup)
- Added backend reject-state fixes for subject-admin moderation and deployed a freshly cross-compiled Linux API binary to `/opt/family_teacher_remote/bin/family-teacher-api`.
- Restarted `family-teacher-api.service`; current service start time is `Wed 2026-03-25 11:19:49 CST`.
- Verified:
  - health endpoint `https://api.tutor1on1.org/health` returned `{"status":"ok"}` after restart.
  - authenticated live probe `POST /api/subject-admin/teacher-registration-requests/999999/reject` returned `404 teacher request not found`, confirming the deployed handler path is active on production.
  - production cleanup kept only users `admin`/`dennis`/`albert`/`charles`, kept only Dennis's teacher account/courses/bundles, and post-cleanup SQL checks returned zero rows still referencing deleted users/teachers/courses across the audited moderation/enrollment/sync/device tables.
  - bundle storage now contains only `/var/lib/family_teacher_remote/storage/bundles/{11,12,13}` with live files `11/6.zip`, `12/5.zip`, and `13/5.zip`.
- Backup:
  - MySQL clean-state dump: `/home/ecs-user/db_backups/family_teacher_20260325_113025_post_cleanup.sql.gz`
- Follow-up cleanup:
  - `admin` (`user_id=20`) recovery email now points to `tutor1on1.org@gmail.com`.
  - Re-validated `dennis_student` (`user_id=13`) absence across live DB user/device/token/enrollment/progress/session tables; all queried counts returned `0`.
  - Removed the earlier pre-cleanup dumps so the current server keeps only the clean-state post-cleanup backup.

## Remote server updates (2026-03-22, teacher-enforced study-mode quit fix)
- Deployed updated API binary to `/opt/family_teacher_remote/bin/family-teacher-api`.
- Added live route `POST /api/student/study-mode/verify-control-pin` and verified it returns `401 unauthorized` without auth, confirming the new contract is active on the public host.
- Restarted `family-teacher-api.service`; current service start time is `2026-03-22 13:10:30 CST`.
- Verified:
  - health endpoint `https://api.tutor1on1.org/health` returned `{"status":"ok"}` after restart.
  - canonical Android APK `https://api.tutor1on1.org/downloads/family_teacher.apk` now serves SHA-256 `518c6fa9aea0f20398f930c6d4b3f8a1df6a0e3d97f7511b0a706611c31b688f`.
  - canonical Windows ZIP `https://api.tutor1on1.org/downloads/family_teacher.zip` now serves SHA-256 `76c0ebdbfcfbe15f87fd5c7392067ee9a8f1dfa88db94dc04ab208995598a96e`.
  - website static install pages under `https://www.tutor1on1.org/` and `/zh/` returned HTTP 200 and still referenced the canonical download paths.

## Remote server updates (2026-03-24, password recovery + public contact email)
- Updated `/etc/family_teacher_remote/env` to keep `RECOVERY_TOKEN_ECHO=false` while enabling Gmail SMTP delivery:
  - `SMTP_ENABLED=true`
  - `SMTP_HOST=smtp.gmail.com`
  - `SMTP_PORT=587`
  - `SMTP_USERNAME=tutor1on1.org@gmail.com`
  - `SMTP_FROM=tutor1on1.org@gmail.com`
  - `SMTP_FROM_NAME=Tutor1on1`
  - `SMTP_USE_TLS=false`
  - `SMTP_STARTTLS=true`
  - `SMTP_SKIP_VERIFY=false`
- Deployed updated API binary to `/opt/family_teacher_remote/bin/family-teacher-api`.
- Restarted `family-teacher-api.service`; current service start time is `Tue 2026-03-24 15:34:03 CST`.
- Verified:
  - health endpoint `https://api.tutor1on1.org/health` returned `{"status":"ok"}` after restart.
  - live password recovery completed end to end against the public API by changing a fresh account's recovery email, receiving the 6-digit recovery code over Gmail, resetting the password, and logging back in with the new password.
  - canonical Android APK `https://api.tutor1on1.org/downloads/family_teacher.apk` now serves SHA-256 `2ef8e1de1116129ea3c9ecac9425190d04cce0e1d858ae14f2f296b602564b55`.
  - canonical Windows ZIP `https://api.tutor1on1.org/downloads/family_teacher.zip` now serves SHA-256 `17042fd2db8a462e4d1bd0d81d1a6cefcf97293a46474e496b9e5a9ba9113907`.
  - website static pages under `https://www.tutor1on1.org/` and `/zh/` returned HTTP 200 after sync, and deployed `site.js` now appends `tutor1on1.org@gmail.com` in the shared footer as the only public contact channel.

## Remote server updates (2026-03-19, Android + Windows + website release)
- Published canonical Android APK to `https://api.tutor1on1.org/downloads/family_teacher.apk`.
- Published canonical Windows ZIP to `https://api.tutor1on1.org/downloads/family_teacher.zip`.
- Synced the static website under `/var/www/tutor1on1_site`.
- Current canonical downloads:
  - APK SHA-256: `9ef48c7754843a6e55e26dbcf5de463198a319e495d62fb653b201245c954790`
  - ZIP SHA-256: `7ba173c9c38584c422d19d4f73209de7fb3bdf7227945aa21554196155c9d054`

## Remote server updates (2026-03-20, study-mode/device-control backend deploy)
- Applied DB migration `remote/db/migrations/0011_study_mode_device_control.up.sql` on production.
- Deployed updated API binary to `/opt/family_teacher_remote/bin/family-teacher-api`.
- Restarted `family-teacher-api.service`; current service start time is `2026-03-20 12:21:15 CST`.
- Verified:
  - health endpoint `https://api.tutor1on1.org/health` returned `{"status":"ok"}` after restart.
  - new protected route `GET /api/account/devices` returns `401 unauthorized` without auth, confirming the route is live instead of missing/`404`.
  - `powershell -ExecutionPolicy Bypass -File scripts/test_auth.ps1 -BaseUrl "https://api.tutor1on1.org"` passed after deploy.
- Incident lesson: the 2026-03-19 client release published APK/ZIP/site before the matching backend deploy. Future backend-affecting releases must include migration + API deploy in the same turn before handoff.

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
