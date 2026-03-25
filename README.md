# Tutor1on1

## Final aim
Build a production-ready family teaching platform where teachers publish structured courses and students learn through guided LLM tutoring, with reliable enrollment, bundle delivery, and multi-device progress sync.

## Project description
Tutor1on1 is a Flutter desktop app with a Go remote API.

- Teacher side: manage local course versions, upload bundles to marketplace, approve enrollments, review student progress.
- Student side: browse public catalog, request enrollment, download approved bundles, and study/review with tutor sessions.
- Sync model: end-to-end encrypted session text and progress events.

## Logical flow
1. Teacher prepares or reloads a local course version.
2. Teacher uploads a validated bundle to marketplace.
3. Student finds public course and submits enrollment request.
4. Teacher approves request.
5. Student downloads approved bundle and imports it locally.
6. Student learning sessions sync to remote; teacher reviews progress and sessions.

## Architecture
### Client (Flutter)
- UI and app state in `lib/`.
- Local persistence via Drift/SQLite.
- Course import/export and prompt handling.
- Auth/session logic and remote API integration.

### Remote API (Go)
- Fiber HTTP server in `remote/`.
- MySQL persistence for users, courses, enrollments, bundle metadata, sync events.
- Authenticated bundle download path with Nginx `X-Accel-Redirect`.
- Upload-side bundle validation and version controls.

### Storage and sync
- Bundle files stored on server filesystem (`STORAGE_ROOT`).
- Session payloads remain ciphertext (E2EE model).
- Sync supports multi-device continuity for teacher/student workflows.

## Repository layout
- `lib/` - Flutter app code.
- `remote/` - Go backend.
- `assets/` - prompts, schemas, and bundled assets.
- `test/` and `integration_test/` - automated checks.
- `scripts/` and `tool/` - utilities.

## Document map
- `AGENTS.md` - docs index.
- `WORKFLOW.md` - execution workflow and quality gate.
- `SCRIPTS.md` - concrete commands.
- `BUGS.md` - lessons learned and watch items.
- `TODOS.md` - priority queue.
- `WORKLOG.md` - active server runbook.
- `LOGBOOK.md` - historical timeline.
