# Tutor1on1

## Final aim
Build a production-ready family teaching platform where teachers publish structured courses and students learn through guided LLM tutoring, with reliable enrollment, bundle delivery, and zip-artifact sync as the only canonical cross-device/server sync model.

## Project description
Tutor1on1 is a Flutter desktop app with a Go remote API.

- Teacher side: manage local course versions, upload bundles to marketplace, approve enrollments, and publish updated course artifacts.
- Student side: browse public catalog, request enrollment, download approved bundles, and study/review locally with tutor sessions.
- Sync model: canonical sync equality is the persisted zip-artifact manifest only. Session/progress rows are not part of canonical server/client sync equality.

## Logical flow
1. Teacher prepares or reloads a local course version.
2. Teacher uploads a validated bundle to marketplace.
3. Student finds public course and submits enrollment request.
4. Teacher approves request.
5. Student downloads approved bundle and imports it locally.
6. Client/server sync compares persisted artifact manifests, transfers only changed zip artifacts, verifies parity, and leaves local learning/session state outside the canonical sync contract.

## Architecture
### Client (Flutter)
- UI and app state in `lib/`.
- Local persistence via Drift/SQLite.
- Course import/export and prompt handling.
- Auth/session logic and remote API integration.
- Local artifact store and persisted artifact manifest/state cache.

### Remote API (Go)
- Fiber HTTP server in `remote/`.
- MySQL persistence for users, courses, enrollments, artifact manifests, and bundle metadata.
- Authenticated bundle download path with Nginx `X-Accel-Redirect`.
- Upload-side bundle validation, artifact storage, and manifest updates.

### Storage and sync
- Bundle files stored on server filesystem (`STORAGE_ROOT`).
- Server and client each persist canonical artifact `state1/state2` derived from the artifact manifest only.
- Normal sync is `compare state2 -> fetch state1 -> diff by artifact_id -> transfer changed zips only -> parity verify`.
- Row-level session/progress/enrollment sync is a retired design, not the active runtime model.

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
