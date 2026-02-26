# WORKLOG
Last updated: 2026-02-26

## Remote host (active)
- Provider: AliCloud ECS
- Host: `43.99.59.107`
- API service: `family-teacher-api.service`
- Nginx reverse proxy: HTTPS entry, internal file serving via `X-Accel-Redirect`

## Important paths
- App deploy root: `/opt/family_teacher_remote`
- API binary: `/opt/family_teacher_remote/bin/family-teacher-api`
- Env file: `/etc/family_teacher_remote/env`
- Logs: `/var/log/family_teacher_remote/app.log`
- Storage root: `/var/lib/family_teacher_remote/storage`

## Operational requirements
- `STORAGE_ROOT` must be writable by `ftapp` (API user).
- Nginx worker (`nginx`) must be able to read/traverse storage paths (current fix: `nginx` in `ftapp` group).
- API upload max size and Nginx `client_max_body_size` must match.

## Common checks
- Service status: `sudo systemctl status family-teacher-api.service`
- API logs: `sudo tail -n 200 /var/log/family_teacher_remote/app.log`
- Nginx logs: `sudo tail -n 200 /var/log/nginx/access.log`
- Health check: `curl -k https://43.99.59.107/health`

## Deployment steps (quick)
1. Build and replace API binary in `/opt/family_teacher_remote/bin/`.
2. `sudo systemctl restart family-teacher-api.service`
3. Verify health endpoint and log tail.

Historical setup timeline moved to `LOGBOOK.md`.

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

## Root-cause note (2026-02-26, student download import)
- Investigated repeated student error: `Missing file: ...\\contents.txt (or ...\\context.txt)` immediately after marketplace download.
- Verified server bundle integrity:
  - latest DB row for `special_relativity` points to `bundles/3/1772077823.zip`
  - zip contains `contents.txt` and prompt metadata.
- Root cause was client-side race in `CourseBundleService`:
  - used `extractArchiveToDisk(...)` without `await`.
  - `archive` 3.x extraction API is async, so import sometimes started before extraction finished.
- Fix: await extraction in both `extractBundleFromFile` and `extractBundleFromBytes`.
