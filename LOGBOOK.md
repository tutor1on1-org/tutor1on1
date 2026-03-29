# LOGBOOK
Historical timeline. Keep active runbook details in `WORKLOG.md`.

## 2026-03-29
- Reworked teacher-configurable tutor prompts end to end: `learn` / `review` now resolve through teacher default, course, student-global, and student-course scopes with bundled assets only as fallback; Prompt Settings gained student-global scope plus full resolved preview/diff; teacher save and sync-import now block malformed, unknown, missing, or non-English placeholder variables; prompt metadata sync now carries teacher-global and student-global data through bundle metadata for no-rebuild updates; backend prompt-metadata path compatibility now covers both `_family_teacher` and `_tutor1on1` bundle entries.

## 2026-03-25
- Added OpenRouter as a built-in text-model provider, updated the bundled Claude / Gemini / Grok defaults to current official model families, and corrected the OpenAI-compatible compatibility layer so OpenRouter reasoning uses its own request shape and reasoning-token fields instead of being treated as raw OpenAI.
- Replaced the remaining obvious `Family Teacher` user-facing branding with `Tutor1on1` in recovery email subjects, root/client README titles, remote README title, and local skills/index docs. Deliberately preserved internal `family_teacher*` identifiers where they still represent real DB names, filesystem paths, legacy cleanup patterns, or Go module/package names.
- Renamed the public Windows desktop executable inside the published ZIP to `tutor1on1.exe`, updated all public install pages/localized Windows instructions to reference the new executable name, and bumped the public client version to `1.0.1+2` with GitHub Release tag `v1.0.1`.
- Added public GitHub Release publishing to the release toolchain with new `public_release/publish_github_release.ps1`, wired it into `scripts/release_public.ps1`, and fixed the Windows packaging edge case where NTFS case-insensitive cleanup would delete the rebuilt lowercase executable when comparing against legacy `Tutor1on1.exe`.
- Published the refreshed public client artifacts and verified their live endpoints/hashes: Android APK `80fd36ad8534dcf7431b1982ed00cd4f27e53b20985aaf1a4156da71122f12ab`, Windows ZIP `766352fbe1ff6e959741c42b94918dc144722e1a1fe7cd5c422e64688cf3d445`, GitHub Release `https://github.com/tutor1on1-org/tutor1on1/releases/tag/v1.0.1`, and website sync at `https://www.tutor1on1.org`.
- Hardened validation after spotting a false-green release precheck: `scripts/validate_project.ps1` now throws on non-zero step exits, and the helper scripts under `tool/` were updated from stale `package:family_teacher/...` imports to `package:tutor1on1/...` so `flutter analyze` no longer reports those tool-only package errors.
- Fixed the backend subject-admin reject bug: non-admin teacher-registration/course-upload rejects now enforce subject-label access checks and resolve the underlying request rows to `rejected` instead of only recording a vote.
- Added targeted backend regression coverage in `remote/internal/httpserver/handlers/moderation_reject_test.go` for subject-admin teacher-registration reject success, subject-label authorization failure, and subject-admin course-upload reject success.
- Validated the backend with `go test ./...`, cross-compiled the Linux API binary locally because the remote source tree under `/opt/family_teacher_remote` was stale/incomplete for an in-place rebuild, uploaded the new binary, restarted `family-teacher-api.service`, and verified both public health and an authenticated live reject-route probe.
- Removed all production users except `admin`, `dennis`, `albert`, and `charles`, deleted stray teacher-registration test requests/votes and other dependent rows, and cleaned orphan bundle storage so only live bundle directories `11/12/13` remain under `/var/lib/family_teacher_remote/storage/bundles`.
- Updated the `admin` recovery email to `tutor1on1.org@gmail.com`, re-checked that `dennis_student` (`user_id=13`) no longer exists in live user/device/token/enrollment/progress/session tables, created a clean replacement backup at `/home/ecs-user/db_backups/family_teacher_20260325_113025_post_cleanup.sql.gz`, and removed the earlier pre-cleanup backups so no server-side backup copy of `dennis_student` remains.

## 2026-03-24
- Completed the public password-recovery UX: login now exposes `Forgot password?`, recovery mail uses a 6-digit code, reset dialogs explicitly tell users to check Spam, and the logged-in Settings page now shows the masked current recovery email plus a current-password-gated change flow.
- Wired production recovery mail to Gmail SMTP (`tutor1on1.org@gmail.com`) with `RECOVERY_TOKEN_ECHO=false`, redeployed the API binary, restarted `family-teacher-api.service`, and re-verified public `/health` plus a live end-to-end regression that updated the recovery email on a fresh account, received the 6-digit code, reset the password, and logged back in.
- Added `tutor1on1.org@gmail.com` as the only public website contact path through shared `web/site.js`, then published fresh artifacts and verified canonical URLs/hashes: Android APK `2ef8e1de1116129ea3c9ecac9425190d04cce0e1d858ae14f2f296b602564b55`, Windows ZIP `17042fd2db8a462e4d1bd0d81d1a6cefcf97293a46474e496b9e5a9ba9113907`, plus website static sync with public `www.tutor1on1.org` page checks.

## 2026-03-23
- Fixed the student session footer/quit root causes together: the tutor footer now keeps the `easy/medium/hard/percent` badge visible by making the desktop control strip scroll-safe and the model dropdown expand safely, while study-mode quit gating now clears stale same-student runtime state and refreshes the live heartbeat decision before prompting for a teacher PIN.
- Added regression coverage for the real failure modes: `test/tutor_session_page_footer_test.dart` renders the student tutor footer at constrained width and asserts the badge plus model selector both stay visible, and `test/study_mode_controller_test.dart` now covers same-student auth sync clearing stale study-mode enforcement.
- Published fresh public artifacts and verified hashes/URLs: Android APK `154e259358a307d67a6d944e1bb248f4bd6dfe3a6ce882e6202c577e2b67a130`, Windows ZIP `2fc8e004d93a1a9c880ed26baf5338c5e3bdce3abc027958fa193d684cec49b1`, plus website static sync for install-page link checks.
- Fixed student course-sync identity handling: session download no longer binds `remoteCourseId` on subject-only fallback reuse, and enrollment sync now trusts an existing student remote-course link only when local bundle identity exists; weak links are replaced by a fresh server import plus student-data migration.
- Added regression coverage for the Albert-style stale-link case where a weakly linked local course must be replaced instead of overridden in place.
- Published fresh public artifacts and verified hashes/URLs: Android APK `b285ea040045a526e31134585472679239f54322d5bd13c4b1a117ae1cfcd537`, Windows ZIP `4288d496ce071a1fd11947ff3530074b25726bba0e08cd87ff870b829c2506f0`, plus website static sync for install-page link checks.

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
# 2026-03-25
- Unified public release version sourcing: `scripts/public_release_version_utils.ps1` now drives GitHub release tag/name parsing and website `web/site.js` sync from `pubspec.yaml`; release and website publish scripts run the sync automatically, and the client GUI now shows app version and public release tag in welcome/settings.
