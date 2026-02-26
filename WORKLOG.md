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
