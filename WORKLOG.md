# WORKLOG
Last updated: 2026-04-11

Active remote runbook and host details only. Historical deployment timeline lives in `LOGBOOK.md`.

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
- Student artifact root: `/var/lib/family_teacher_remote/storage/student_kp`
- Public download root: `/var/lib/family_teacher_remote/public`
- Website static root: `/var/www/tutor1on1_site`

## Local data paths (this machine)
- `getApplicationDocumentsDirectory()` resolves to `C:\Mac\Home\Documents`
- Live local app DB: `C:\Mac\Home\Documents\family_teacher.db`

## Operational requirements
- `STORAGE_ROOT` must be writable by `ftapp` (API user).
- `student_kp` must stay owned by `ftapp:ftapp` so per-KP artifact writes do not fail during cutover or live sync.
- Nginx worker (`nginx`) must be able to read and traverse storage paths.
- API upload max size and Nginx `client_max_body_size` must match.
- Artifact-manifest sync uses the server copy as canonical; if local sync state disagrees, reset/rebuild local state from server instead of preserving both copies.

## Current production sync state
- Production runtime sync is artifact-manifest only; retired row-level routes `/api/session/sync`, `/api/progress/sync`, and `/api/sync/download` should stay `404`.
- `/api/artifacts/sync/state2` is the active artifact route and should require auth (`401` when unauthenticated).
- Latest pre-cutover backup: `/home/ecs-user/db_backups/family_teacher_20260401_195705_artifact_cutover_pre.sql.gz`

## Latest verified public artifacts
- Version: `v1.0.7`
- Android APK: `https://api.tutor1on1.org/downloads/Tutor1on1.apk`
  - SHA-256: `a4baa5d899b04ea216df91e2b0c3e92e62887b74b0c38a5b5d29c497857d07b0`
- Windows ZIP: `https://api.tutor1on1.org/downloads/Tutor1on1.zip`
  - SHA-256: `ad3f83187cb311d423dfab393003b1c164ebe6352a8048ca11f17fcda75fce21`
- GitHub Release: `https://github.com/tutor1on1-org/tutor1on1/releases/tag/v1.0.7`
- Website root: `https://www.tutor1on1.org`

## Common checks
- SSH smoke: `ssh ecs-user@tutor1on1.org "hostname && whoami"`
- Service status: `sudo systemctl status family-teacher-api.service`
- API logs: `sudo tail -n 200 /var/log/family_teacher_remote/app.log`
- Nginx logs: `sudo tail -n 200 /var/log/nginx/access.log`
- Health check: `curl https://api.tutor1on1.org/health`

## Deployment quick path
1. Build and replace the API binary in `/opt/family_teacher_remote/bin/`.
2. `sudo systemctl restart family-teacher-api.service`
3. Verify `/health`, auth, and current bundle/artifact delivery paths.

## SSH notes
- Default remote user is `ecs-user`, not `root` or local Windows usernames.
- Always try the explicit key path first: `-i C:\Users\kl\.ssh\id_rsa -o IdentitiesOnly=yes`.
- Default remote host for manual ops is `tutor1on1.org`, so prefer `ssh ecs-user@tutor1on1.org`.
- If `ssh ecs-user@tutor1on1.org` fails to log in, stop and report the failure instead of retrying other usernames or host variants.
- If SSH fails with `Permission denied (publickey,...)`, verify the remote user before blaming the key.
- If SSH fails with `banner exchange: Connection to UNKNOWN port -1: Connection refused` and `Test-NetConnection 43.99.59.107 -Port 22` reports `TcpTestSucceeded=False`, port `22` is closed or blocked from the current network.

## TLS notes
- Canonical public API origin is `https://api.tutor1on1.org`.
- Public TLS is managed by `certbot` on the host with the nginx plugin.
- Port `80/tcp` must stay open in both Alibaba security group and host firewall for HTTP-01 issuance and renewal.
