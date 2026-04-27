# LOGBOOK
Historical timeline. Keep active runbook details in `WORKLOG.md`. Entries that mention row-level session/progress/enrollment sync remain historical delivery records only.

## 2026-04-27
- Fixed production `course list failed` for teacher courses without bundle versions, reproduced on `dennis` / `Liu_math`; deployed rebuilt Linux amd64 API binary SHA-256 `7ab55f5d961d0c64aad739a56e6d7eaa34ba158a2208cebdfa6029e86d956321`, restarted `family-teacher-api.service`, verified health, and confirmed `/api/teacher/courses` returns `Liu_math` with empty latest-bundle fields instead of 500.
- Fixed Windows enrollment-sync temp bundle cleanup failures where `bundle_<course>_*.zip` could stay locked after login sync. ZIP archive readers now clear lazy entry streams after use, scaffold extraction no longer returns lazy `ArchiveFile` entries beyond archive lifetime, and temporary enrollment bundle deletion is treated as cleanup warning instead of sync failure.
- Added regression coverage for immediate deletion after `extractBundleScaffoldFromFile`, recorded the lesson in `BUGS.md`, cleared stale local `bundle_math_deep_*.zip` temp files, and validated with targeted bundle/enrollment tests, `flutter analyze`, `scripts/validate_project.ps1 -NoPostHook`, `flutter build apk --config-only`, `flutter build apk --release`, and `flutter build windows --release`.

## 2026-04-26
- Added one-sentence approval email notifications for enrollment, quit-course, teacher-registration, and course-upload approval requests, including subject-admin approver notifications and applicant decision notifications when SMTP is enabled.
- Validated with targeted handler tests, full `go test ./...` under `remote/`, and `scripts/validate_project.ps1 -NoPostHook`; built local release artifacts with scripts: Android APK SHA-256 `273bd41505e5e67e3ed63fc8a6a6823082787fad519edd0acb2b4db3f4fead0b`, Windows ZIP SHA-256 `0d717211d9202e9d290c08eb514d8dc5497cbaaacceeb7b6de87c89981767004`.
- Deployed the rebuilt Linux amd64 API binary to production with SHA-256 `593745ad71993cc8e0d886809d7778ef74735c92ddfc34e64b2ea35901544d44`, kept backup `/opt/family_teacher_remote/bin/family-teacher-api.bak_20260426_1812_pre_approval_email`, restarted `family-teacher-api.service`, verified `https://api.tutor1on1.org/health`, and checked the service log tail.

## 2026-04-25
- Simplified the bundled `learn` tutor prompt to plain student-visible text using `conversation_history`, `lesson_content`, compact `student_context`, and `error_book_summary`, with no JSON contract.
- Updated runtime handling so `learn` no longer loads a structured schema, no longer retries on missing JSON keys, streams/persists raw visible text, and still closes the learn turn cleanly; `review` remains the structured JSON prompt.
- Added prompt asset/session regressions for the plain learn path and validated with targeted prompt/session tests plus `scripts/validate_project.ps1 -NoPostHook`.
- Split review into `review_init` and `review_cont`: init emits one plain student-visible question, continuation emits `{text,mistakes,finished,difficulty_adjustment}` JSON, and `next_action`/prompt-chosen difficulty were removed from the review contract.
- Moved per-KP review difficulty ownership into the app with persisted `current_review_difficulty`/`question_level`, clamped question-bank selection to available `easy/medium/hard` files, and added hard-only coverage. Validated with targeted prompt/schema/session tests, `flutter analyze`, and local `flutter build windows --release`; no publish was run.

## 2026-04-13
- Added student local-wins sync recovery: the client now exposes `Take This Device Copy`, force-pushes local `student_kp` sessions/progress with explicit `overwrite_server=true`, and resolves local delete conflicts through the new backend `/api/artifacts/delete` route.
- Validated with `flutter test test\session_sync_service_test.dart test\student_server_copy_service_test.dart`, `flutter analyze`, and `go test ./internal/httpserver/handlers ./internal/artifactsync`; deployed the rebuilt Linux amd64 API binary with SHA-256 `2d81f98f5e14df2a70d701b8729c7bcff2320d7ee5ff451056b24bde5ece4551`, kept backup `/opt/family_teacher_remote/bin/family-teacher-api.bak_20260413_1744_pre_client_copy`, restarted `family-teacher-api.service`, verified `https://api.tutor1on1.org/health`, and confirmed unauthenticated `POST /api/artifacts/delete` returns `401`.
- Published public client `v1.0.28` through `scripts/release_public.ps1` and verified live endpoints: Android APK SHA-256 `94444fe59ff796896ca1f310c275ffea8aed00ac5e93acd1fba61e16cccdb92c`, Windows ZIP SHA-256 `a174de33767f4b76e89d860df3c792f255d6e288f4973c5e5a5c0b4c30024c19`, GitHub Release `https://github.com/tutor1on1-org/tutor1on1/releases/tag/v1.0.28`, `https://api.tutor1on1.org/downloads/Tutor1on1.apk`, `https://api.tutor1on1.org/downloads/Tutor1on1.zip`, and `https://www.tutor1on1.org/site.js`.
- Fixed student tutor-chat `HandshakeException: Connection terminated during handshake` fragility by retrying LLM streaming sends with a recreated streamed `http.Request`; added `test\llm_service_test.dart` coverage for first-send handshake failure recovery and validated with `flutter analyze`, `flutter test`, and `scripts\publish_android_release.ps1 -SkipPubGet -SkipUpload` (local APK SHA-256 `b86842a2526e6921c7db005d823bae2cd655d0a86204396a72b5d29c8daf42fc`).
- Reworked prompt inheritance from append fragments to full prompt overrides: Prompt Settings now edits/previews/diffs the same effective full prompt used at runtime, unmodified scopes inherit from the nearest active parent override, and schema v31 deletes legacy prompt-template rows instead of reinterpreting old append content. Validated the targeted prompt/migration path with `flutter test test\prompt_scope_precedence_test.dart test\prompt_editor_dialog_test.dart test\migration_test.dart --no-pub` and `flutter analyze --no-pub`.

## 2026-04-12
- Fixed marketplace course/bundle deletion when moderation requests, subject labels, quit requests, or artifact manifest rows still reference the course/bundle: full-course delete, single bundle-version delete, and automatic bundle prune now clear dependent rows inside the same transaction before deleting bundle versions or the course row.
- Validated with `go test ./internal/httpserver/handlers` and `go test ./...` under `remote/`; deployed the rebuilt Linux amd64 API binary for commit `bb780e8` to `/opt/family_teacher_remote/bin/family-teacher-api`, restarted `family-teacher-api.service`, verified remote SHA-256 `58a4232fe17200dfdaaf149fc0e540f4502e4d70570d39e9c13f4120b8e0a979`, and confirmed `https://api.tutor1on1.org/health` returns `{"status":"ok"}`.

## 2026-04-05
- Fixed the client enrollment `state2` parity bug that could raise `Stored student enrollment sync state drifted from canonical local state1` on the next due sync after login or `Take server copy`: local enrollment sync state now uses the same manifest contract as the server (`artifact_state2_v1` over sorted `artifact_id|sha256` lines), while teacher-only pending uploads still use synthetic local-only artifact ids to force the intended upload path.
- Added due-interval regression coverage so student and teacher clean-second-sync checks no longer pass trivially inside the 60-second cooldown window.
- Revalidated with `flutter test test/enrollment_sync_service_test.dart`, `flutter analyze`, `flutter test`, and the full `scripts/release_public.ps1` flow.
- Published public client `v1.0.7` and verified live endpoints: Android APK SHA-256 `a4baa5d899b04ea216df91e2b0c3e92e62887b74b0c38a5b5d29c497857d07b0`, Windows ZIP SHA-256 `ad3f83187cb311d423dfab393003b1c164ebe6352a8048ca11f17fcda75fce21`, GitHub Release `https://github.com/tutor1on1-org/tutor1on1/releases/tag/v1.0.7`, `https://api.tutor1on1.org/downloads/Tutor1on1.apk`, `https://api.tutor1on1.org/downloads/Tutor1on1.zip`, and `https://www.tutor1on1.org/`.

## 2026-04-01
- Completed the production hard cutover from legacy row-level sync to artifact-manifest sync. Created backup `/home/ecs-user/db_backups/family_teacher_20260401_195705_artifact_cutover_pre.sql.gz`, confirmed the legacy student credential set as `albert` and `charles` with real logins, then ran `artifact_cutover` to convert `39` legacy sessions plus `3127` progress rows into `3157` canonical artifacts across `2` students while dropping the retired sync tables.
- During cutover, found `/var/lib/family_teacher_remote/storage/student_kp` owned by `root:root`; fixed ownership to `ftapp:ftapp`, reran the cutover, and verified the live artifact storage path is writable by the API user.
- Verified the post-cutover runtime contract on production: `family-teacher-api.service` healthy at `https://api.tutor1on1.org/health`, new artifact route `/api/artifacts/sync/state2` requires auth (`401` unauthenticated), and retired row-sync routes `/api/session/sync`, `/api/progress/sync`, and `/api/sync/download` now return `404`.
- Updated `scripts/smoke_teacher_student_flow.ps1` for moderated servers so it can use `FT_SMOKE_ADMIN_USERNAME` / `FT_SMOKE_ADMIN_PASSWORD` to approve fresh teacher-registration and course-upload requests, then re-ran the live smoke flow successfully through teacher publish, student enrollment, approval, and bundle download.
- Finished the public release/publish chain for `v1.0.1`: Android APK published at SHA-256 `7c76d548f3ced5b69f71a65ef9fe3bf5d3e7a831a635a62ba57122ef5cbe4f15`, Windows ZIP published at SHA-256 `f355e03827c9f2112ec4fa905c83efc9f358832cd10419fa87061fa5d3864959`, GitHub Release assets refreshed at `https://github.com/tutor1on1-org/tutor1on1/releases/tag/v1.0.1`, website static content re-synced, Windows publish candidate/canonical URL checks gained retry handling, and the GitHub release retry path now preserves already-built Android/Windows artifacts during GitHub-only reruns.

## 2026-03-30
- Fixed the fresh-device progress replay bug: downloading/importing server progress now also stamps the local progress-upload sync ledger, so the next normal sync does not re-upload that server data from scratch on a new install.
- Extended blocking sync overlay progress details to include transferred MB alongside counts for large session/progress download/import and upload stages, and added extra yield points in heavy session/progress loops so the overlay keeps repainting during long sync work.
- Fixed login-time sync responsiveness: teacher/student home screens now route startup sync through one shared core coordinator, login overlays can show staged progress with optional determinate counts, large JSON decodes move to a background isolate, chapter-cache upload reads only requested pending chapter snapshots, and session import writes chat messages in one Drift batch.
- Published refreshed public client artifacts for the sync-responsiveness fix and verified live endpoints/hashes: Android APK `e3f47f804934c0be87c993ac81231542529a9bf724e2f10302def696aea57244`, Windows ZIP `6c421196e594ce299b373bf2871707c9025a319f9810fab08d507337d98ef9ce`, GitHub Release `https://github.com/tutor1on1-org/tutor1on1/releases/tag/v1.0.1`, and website install/home pages at `https://www.tutor1on1.org`.

## 2026-03-29
- Reworked teacher-configurable tutor prompts end to end: `learn` / `review` now resolve through teacher default, course, student-global, and student-course scopes with bundled assets only as fallback; Prompt Settings gained student-global scope plus full resolved preview/diff; teacher save and sync-import now block malformed, unknown, missing, or non-English placeholder variables; prompt metadata sync carries teacher-global and student-global data through bundle metadata; backend prompt-metadata path compatibility covers both `_family_teacher` and `_tutor1on1` bundle entries.
- Added an explicit teacher-side `Pull Latest Server` action on course rows and corrected sync conflict wording to say `bundle` instead of `course`, because newer server bundle versions can now come from prompt/profile metadata changes even when the course tree itself was untouched.

## 2026-03-25
- Added OpenRouter as a built-in text-model provider, updated the bundled Claude / Gemini / Grok defaults to current official model families, and corrected OpenRouter reasoning request/response handling.
- Replaced obvious `Family Teacher` user-facing branding with `Tutor1on1` in recovery email subjects, README titles, remote README title, and local skills/index docs while preserving internal `family_teacher*` identifiers that still represent real DB names, filesystem paths, legacy cleanup patterns, or Go module/package names.
- Renamed the public Windows desktop executable inside the published ZIP to `tutor1on1.exe`, updated public install pages/localized Windows instructions, and bumped the public client version to `1.0.1+2` with GitHub Release tag `v1.0.1`.
- Added public GitHub Release publishing to the release toolchain, wired it into `scripts/release_public.ps1`, fixed the NTFS case-insensitive packaging cleanup edge case, and unified public release version sourcing around `pubspec.yaml`.
- Published refreshed public client artifacts and verified live endpoints/hashes: Android APK `80fd36ad8534dcf7431b1982ed00cd4f27e53b20985aaf1a4156da71122f12ab`, Windows ZIP `766352fbe1ff6e959741c42b94918dc144722e1a1fe7cd5c422e64688cf3d445`, GitHub Release `https://github.com/tutor1on1-org/tutor1on1/releases/tag/v1.0.1`, and website sync at `https://www.tutor1on1.org`.
- Hardened validation after a false-green release precheck: `scripts/validate_project.ps1` now throws on non-zero step exits, and helper scripts under `tool/` were updated from stale `package:family_teacher/...` imports to `package:tutor1on1/...`.
- Fixed the backend subject-admin reject bug, added targeted backend regression coverage in `remote/internal/httpserver/handlers/moderation_reject_test.go`, validated with `go test ./...`, deployed the Linux API binary, restarted `family-teacher-api.service`, and verified public health plus an authenticated live reject-route probe.
- Cleaned production data so only users `admin`, `dennis`, `albert`, and `charles` remain, removed stray teacher-registration test requests/votes and orphan bundle storage, updated the `admin` recovery email to `tutor1on1.org@gmail.com`, and kept clean backup `/home/ecs-user/db_backups/family_teacher_20260325_113025_post_cleanup.sql.gz`.

## 2026-03-24
- Completed the public password-recovery UX: login exposes `Forgot password?`, recovery mail uses a 6-digit code, reset dialogs tell users to check Spam, and Settings shows the masked current recovery email plus a current-password-gated change flow.
- Wired production recovery mail to Gmail SMTP (`tutor1on1.org@gmail.com`) with `RECOVERY_TOKEN_ECHO=false`, redeployed the API binary, restarted `family-teacher-api.service`, and verified a live end-to-end recovery flow against `https://api.tutor1on1.org`.
- Added `tutor1on1.org@gmail.com` as the only public website contact path through shared `web/site.js`, then published fresh Android/Windows artifacts and website static sync.

## 2026-03-23
- Fixed student session footer/quit regressions: the tutor footer keeps the `easy/medium/hard/percent` badge visible while study-mode quit gating clears stale same-student runtime state and refreshes the live heartbeat decision before prompting for a teacher PIN.
- Fixed student course-sync identity handling: subject-only session fallback no longer binds `remoteCourseId`, enrollment sync trusts existing student remote-course links only when local bundle identity exists, and weak links are replaced by fresh server import plus student-data migration.
- Added regression coverage for constrained footer rendering, same-student study-mode clearing, and the Albert-style stale-link case, then published fresh public artifacts and website static sync.

## 2026-03-22
- Fixed teacher-enforced study mode root cause: the student quit gate now comes from one runtime study-mode controller, the global `X` means app quit only, logout/current-device deletion share the same teacher gate, and PIN verification moved back to the server.
- Deployed `POST /api/student/study-mode/verify-control-pin`, verified public health and unauthenticated `401`, and published fresh public artifacts plus website static sync.
- Fixed structured tutor-message spacing by preserving whitespace-only fragments and limiting seam normalization to duplicated explicit boundary whitespace instead of guessing spaces from alphanumeric boundaries.

## 2026-03-21
- Fixed reasoning/session-output fragment seam handling so streamed `think` text and relay-exported session messages no longer double spaces or collapse word boundaries at chunk joins.
- Documented the Windows hotfix publish procedure in `WORKFLOW.md` and recorded seam-normalization rules in `BUGS.md` / `LESSONS.md`.

## 2026-03-08
- Reworked session/progress download sync to manifest+fetch, moved sync metadata/state off Windows secure storage into Drift/SQLite, added client/backend coverage for sync manifest/fetch behavior, deployed the backend, and published canonical Windows ZIP `https://api.tutor1on1.org/downloads/family_teacher.zip` with SHA-256 `8e344223866c82c37d742b192f1e5f94c86dff3de4b035acc780a664504807d2` after the Explorer-compatible packaging republish.

## 2026-02-27
- Added Codex-based memory update hook (`scripts/hook_memory_update.ps1`) with line-count delta trigger, target-only file updates, and append suggestions for other memory docs; updated pre-push to run memory update before validation and block until hook-produced memory changes are committed.
- Added student-intent aware tutor interaction, improved REVIEW continuation schema, enhanced error-book prompt context, removed legacy prompt surfaces/dead branches, completed analyzer cleanup, added sync/enrollment regression tests, added marketplace prompt metadata conflict handling, added auth recovery SMTP tests, added `scripts/remote_exec.ps1`, added `BACKUP_DRILL.md`, rotated temporary local secrets, and hardened structured tutor-chat logging/retry behavior.

## 2026-02-26
- Investigated student import failures after download; server bundle integrity was valid, and the client root cause was async archive extraction not being awaited.
- Added server-side upload validation for required files and lecture references, upload hash dedupe, latest-5 version retention, and teacher bundle-version APIs.
- Reorganized top-level docs so `AGENTS.md` is only a doc index and operational/process content lives in linked docs.

## 2026-02-25 to 2026-02-26
- Provisioned and configured AliCloud ECS host with Go/MySQL/Nginx and service accounts, deployed API service + HTTPS reverse proxy, finalized filesystem bundle storage and operational checks, added backup/logrotate and smoke checks, and fixed student bundle download `403` by aligning Nginx file read permissions.

## 2026-02-25
- Added auth upgrades, marketplace role checks/public visibility filtering, bundle zip/path validation, stream download handling, and documented the Drift migration guard pattern for create-table/add-column sequencing.

## 2026-02-22
- Clarified prompt loading order, tied session prompt variant selection to turn state, and enforced required prompt placeholders.

## 2026-02-16
- Clarified that teacher-scope defaults override the base system prompt while course/student scopes remain additive appends.

## 2026-02-06
- Expanded prompt repository/template validator for new prompt names and variables, allowed empty first student input to trigger the first tutor response, and moved runtime prompt routing to `learn_init` / `learn_cont`, `review_init` / `review_cont`, and `summary` with legacy compatibility.
