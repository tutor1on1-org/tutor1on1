# Project Memory - family_teacher

## Work routine
- After a code change, before updating `DONEs.md`, run `flutter build windows --release` (timeout 10 minutes). If it fails, fix the root cause from the error. Max 3 retries for the same error.
- If build is working, commit and push with a clear message.

## Current product state
- Flutter app + remote Go API for family teaching.
- Roles: `teacher` and `student`.
- Teacher flow: load/reload local course versions, upload bundle to marketplace, approve enrollment requests, review student sessions/progress.
- Student flow: browse public marketplace, request enrollment, download approved bundles, study with LLM tutor.
- Session sync uses end-to-end encrypted text payloads and supports multi-device sync.

## Critical implementation notes
- Prompt scope behavior: teacher scope overrides base system prompt per prompt name; course/student scopes are additive append templates.
- Session prompt selection: `learn_init`/`learn_cont` and `review_init`/`review_cont` are selected by session turn state and label.
- Structured tutor output must be valid JSON and include `teacher_message`; invalid output should be surfaced as an error, not rendered raw.
- Bundle prompt metadata is in `_family_teacher/prompt_bundle.json`; apply only when incoming `version_id` is newer.
- Drift migrations that create a table mid-upgrade must guard later `addColumn` with `from >= <createVersion>` to avoid duplicate-column failures.

## Remote ops notes
- Keep `GOPATH` and `GOMODCACHE` outside repo (example: `/var/lib/family_teacher_remote/go`) to avoid module-cache corruption in project tree.
- For authenticated bundle downloads, API checks auth and returns `X-Accel-Redirect`; Nginx serves files from internal alias.
- Nginx worker must have read/traverse permission on `STORAGE_ROOT` (current host: `nginx` user is in `ftapp` group).
- Keep API upload limit and Nginx `client_max_body_size` aligned.

## References
- `README.md` for current architecture and flows.
- `BUGS.md` for active issues only.
- `TODOS.md` for prioritized next tasks.
- `DONEs.md` for recent completed work.
- `PLANS.md` for roadmap and sequence.
- `WORKLOG.md` for current server runbook.
- `LOGBOOK.md` for historical timeline and archived notes.
- `SECRETS.md` for temporary credentials (rotate later).
