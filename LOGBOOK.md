# LOGBOOK
Historical timeline. Keep active runbook details in `WORKLOG.md`.

## 2026-02-06
- Prompt repository and template validator expanded for new prompt names and variables.
- Session behavior changed to allow empty first student input to trigger first tutor response.
- Runtime prompt routing moved to `learn_init`/`learn_cont`, `review_init`/`review_cont`, and `summary` with legacy compatibility.

## 2026-02-16
- Prompt scope behavior clarified: teacher-scope defaults override base system prompt; course/student scopes remain additive appends.

## 2026-02-22
- Prompt loading order clarified: bundled prompt + optional teacher override + additive course/student text.
- Session service prompt variant selection tied to turn state.
- Prompt validator enforces required placeholders.

## 2026-02-25
- Added auth upgrades: username login, recovery email flow, anti-enumeration responses, and per-IP rate limiting.
- Added marketplace role checks and public visibility filtering.
- Added bundle zip/path validation and stream download handling.
- Documented Drift migration guard pattern for create-table/add-column sequence.

## 2026-02-25 to 2026-02-26
- Provisioned and configured AliCloud ECS host with Go/MySQL/Nginx and service accounts.
- Deployed API service + HTTPS reverse proxy.
- Finalized filesystem bundle storage and operational checks.
- Added backup/logrotate and basic service smoke checks.
- Fixed student bundle download `403` by aligning Nginx file read permissions (`nginx` user in `ftapp` group).

## 2026-02-26
- Investigated student import failures after download; validated server bundle integrity.
- Root cause identified on client: async archive extraction was not awaited.
- Added server-side upload validation for required files and lecture references.
- Added upload hash dedupe, version retention (latest 5), and teacher bundle-version APIs.
- Reorganized top-level docs: `AGENTS.md` reduced to doc index; operational/process content moved into `README.md`, `WORKFLOW.md`, `SCRIPTS.md`, `BUGS.md`, and `LOGBOOK.md`.

## 2026-02-27
- Added P0 regression tests for normalized-subject reconciliation (`_<timestamp>` stripping) in enrollment sync for both teacher and student paths.
- Added compatibility coverage for older servers where `/api/enrollments/quit-requests` returns `404` (now asserted to resolve as empty list).
- Updated local `packages/record_linux` override to match `record_platform_interface` permission method signature and restored Windows release build success.
