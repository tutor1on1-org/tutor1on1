# WORKLOG
Last updated: 2026-04-01

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
- Public download root: `/var/lib/family_teacher_remote/public`
- Website static root: `/var/www/tutor1on1_site`

## Local data paths (this machine)
- `getApplicationDocumentsDirectory()` resolves to `C:\Mac\Home\Documents`
- Live local app DB: `C:\Mac\Home\Documents\family_teacher.db`

## Operational requirements
- `STORAGE_ROOT` must be writable by `ftapp` (API user).
- Nginx worker (`nginx`) must be able to read and traverse storage paths.
- API upload max size and Nginx `client_max_body_size` must match.

## Latest verified public artifacts
- Android APK: `https://api.tutor1on1.org/downloads/Tutor1on1.apk`
  - SHA-256: `b70c9337f25d586a109aba3e54a2f8aa33427ca6bba72957ca4634c6769f14fe`
- Windows ZIP: `https://api.tutor1on1.org/downloads/Tutor1on1.zip`
  - SHA-256: `aaa010f691d2d135b6f8826f2cc3e961bd92047b00ec44c98083190ee0fc60e1`
- GitHub Release: `https://github.com/tutor1on1-org/tutor1on1/releases/tag/v1.0.1`
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
