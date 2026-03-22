# LOGBOOK
Historical timeline. Keep active runbook details in `WORKLOG.md`.

## 2026-03-22
- Fixed teacher-enforced study mode root cause: the student quit gate now comes from one runtime study-mode controller instead of persistent app settings or tutor-page mode, the global `X` always means app quit, logout/current-device deletion share the same teacher gate, and PIN verification moved back to the server instead of using cached `control_pin_hash` on the student device.
- Deployed the matching backend route change (`POST /api/student/study-mode/verify-control-pin`) to `family-teacher-api.service`, verified public health returned `{"status":"ok"}`, confirmed the new route returns `401` without auth, and recorded the live restart timestamp `2026-03-22 13:10:30 CST`.
- Published fresh public artifacts and verified hashes/URLs: Android APK `518c6fa9aea0f20398f930c6d4b3f8a1df6a0e3d97f7511b0a706611c31b688f`, Windows ZIP `76c0ebdbfcfbe15f87fd5c7392067ee9a8f1dfa88db94dc04ab208995598a96e`, plus website static sync for install-page link checks.
- Refined the structured tutor-message spacing diagnosis: the actual shared bug was dropping whitespace-only fragments during extraction, which showed up most clearly around number-adjacent seams; the earlier alphanumeric seam heuristic was only masking that loss and could also create bogus mid-word spaces.
- Updated the shared extractor so standalone whitespace fragments survive, and extended regression coverage for standalone-space, number-boundary, mid-word, and duplicated-whitespace seam cases.
- Fixed the tutor-message spacing regression introduced by the 2026-03-21 JSON spacing hotfix: structured JSON fragment reassembly no longer inserts guessed spaces inside split words and now only dedupes overlapping explicit boundary whitespace.
- Validated the hotfix with `flutter test test/llm_reasoning_support_test.dart`, `dart analyze lib/llm/llm_reasoning_support.dart lib/llm/llm_service.dart test/llm_reasoning_support_test.dart`, and `powershell -ExecutionPolicy Bypass -File scripts/validate_project.ps1 -NoPostHook`.
- Published fresh public artifacts and verified hashes/URLs: Android APK `b857ff4342a06384163f033268247f0df5506771f08ad6a3224b6408576d741a`, Windows ZIP `63b9d3dacaf129adf10e69c282fef2899718ab8e12c91ca0c10f986be883f722`, plus website static sync for install-page link checks.

## 2026-03-21
- Fixed reasoning/session-output fragment seam handling so streamed `think` text and relay-exported session messages no longer double spaces or collapse word boundaries at chunk joins.
- Documented a concrete Windows hotfix publish procedure in `WORKFLOW.md` and recorded the seam-normalization rule in `BUGS.md` / `LESSONS.md`.

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
- Added Codex-based memory update hook (`scripts/hook_memory_update.ps1`) with trigger `line-count delta >10` versus tracked snapshot (`scripts/memory_line_snapshot.json`), target-only file updates, and append suggestions for other memory docs.
- Added dedicated memory-hook session lifecycle (create if missing, resume if present) using local `.git/memory_hook_state.json` and sub-agent prompt source `scripts/hook_memory_update_prompt.txt`.
- Updated tracked pre-push hook to run memory update first, then validation, and block push until hook-produced memory changes are committed.
- Added student-intent aware tutor interaction: chat UI now sends explicit `student_intent` hints into prompt context and REVIEW_CONT schema/prompt now require `answer_state` for clearer final-answer transitions.
- Enhanced error-book signal quality by aggregating historical REVIEW `error_book_update` entries into prompt context and surfacing top recurring mistake tags in tutor-session UI.
- Removed legacy prompt exposure and dead compatibility branches from active app paths (`learn/review/summarize` prompt UI/managed metadata cleanup; session legacy render branch removal) and deleted unused bundled legacy prompt files.
- Completed analyzer cleanup pass to zero issues by updating deprecated dropdown APIs, removing redundant null-check patterns, and cleaning tool-script imports/casts.
- Added P0 regression tests for normalized-subject reconciliation (`_<timestamp>` stripping) in enrollment sync for both teacher and student paths.
- Added compatibility coverage for older servers where `/api/enrollments/quit-requests` returns `404` (now asserted to resolve as empty list).
- Updated local `packages/record_linux` override to match `record_platform_interface` permission method signature and restored Windows release build success.
- Added marketplace prompt metadata re-download conflict handling to preserve local prompt/profile edits when newer remote metadata arrives.
- Added auth recovery SMTP-path regression tests with fake SMTP server; enforced no token leak in response when `RECOVERY_TOKEN_ECHO=false`.
- Added `scripts/remote_exec.ps1` for canonical key-only SSH defaults and added `BACKUP_DRILL.md` restore/incident runbook.
- Rotated temporary local secrets in `.env` and updated operational docs for rotation/revocation and drill workflow.
- Added tutor-chat reliability hardening: structured schemas for learn/review prompts, single-flight request dedupe, retry telemetry fields in LLM logs, and summary cache short-circuit when context is unchanged.

## 2026-03-08
- Reworked session/progress download sync to a manifest+fetch model: client requests compact indexes first, then fetches only missing/stale payloads.
- Moved sync metadata/state off Windows secure storage and into local Drift/SQLite tables to remove `flutter_secure_storage.dat` contention during large syncs.
- Added client API coverage for `/api/sync/download-manifest` and `/api/sync/download-fetch`, plus backend handler coverage for ETag and fetch response behavior.
- Deployed updated backend to `family-teacher-api.service`, verified local and public `/health`, built Windows release, and published canonical `https://43.99.59.107/downloads/family_teacher.zip`.
- Published initial manifest+fetch release ZIP, then a teacher-course-sync republish, then an Explorer-compatible republish after replacing `tar -a`; canonical SHA settled at `8e344223866c82c37d742b192f1e5f94c86dff3de4b035acc780a664504807d2`.
