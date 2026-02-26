# LOGBOOK
Historical archive. Keep active instructions in `AGENTS.md` and operational runbook in `WORKLOG.md`.

## 2026-02-06
- Prompt repository and template validator updated to support new prompt names/variables.
- New session behavior changed: app can send empty student input to trigger first tutor message.
- Runtime switched to `learn_init`/`learn_cont`, `review_init`/`review_cont`, `summary` while keeping legacy compatibility.
- Structured prompt data model and teacher text formatting tasks completed.

## 2026-02-16
- Prompt scope behavior clarified: teacher default edits base system prompt override; course/student remain additive templates.

## 2026-02-22
- Prompt loading flow clarified: bundled prompt text + optional teacher override + course/student appends.
- Session service selects prompt variants by turn state.
- Prompt template validator requires placeholders for required variables.

## 2026-02-25 (development learnings)
- Structured tutor prompts must return valid JSON including `teacher_message`.
- MySQL root password behavior changed `sudo mysql` usage; app users needed for `localhost` and `127.0.0.1`.
- Nginx config writing from PowerShell requires preserving `$host`.
- `go mod tidy` with GOPATH inside repo can break module layout.
- Authenticated downloads use Nginx `X-Accel-Redirect` internal alias.
- API and Nginx upload size limits should match.
- Auth migrated to username + recovery email workflows.
- Recovery email supports SMTP; `RECOVERY_TOKEN_ECHO` is dev-only.
- Auth endpoints got per-IP rate limiting and anti-enumeration recovery responses.
- Marketplace role checks and public-visibility catalog filtering were added.
- Bundle zip/path validation and stream download handling were added.
- Drift migration guard pattern documented for create-table/add-column sequencing.

## 2026-02-25 to 2026-02-26 (remote server timeline)
- Provisioned AliCloud host, installed Go/MySQL/Nginx, created service accounts and directories.
- Deployed API systemd service and HTTPS reverse proxy.
- Added and later removed OSS path; finalized filesystem storage for bundles.
- Added marketplace APIs, enrollment workflow, auth recovery/rate limits, and session sync deployment.
- Added backup/logrotate and operational service checks.
- Fixed student bundle download `403` by adjusting storage file read permissions for Nginx (`nginx` added to `ftapp` group).

## Historical references migrated from
- `AGENTS.md` experience-learned timeline entries.
- `WORKLOG.md` chronological deployment/setup notes.
- `DONES.md` old completion history.
- `BUGS.md` legacy resolved items.
