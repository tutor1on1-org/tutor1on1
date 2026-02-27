# DONES
Last updated: 2026-02-27

- Completed marketplace re-download conflict policy for prompt metadata overwrite: newer remote bundles now preserve local prompt/profile edits when local changes were made after previous metadata apply, and report explicit preserved-local messaging.
- Added secure-storage timestamp tracking for prompt metadata apply (`promptMetadataAppliedAt`) to support conflict detection on re-download.
- Finished workflow-critical persistent message coverage for teacher enrollment request actions and teacher-home sync/upload preflight errors (manual dismiss, copyable text).
- Rotated temporary credentials in `SECRETS.md` (MySQL root/app + JWT secret) and documented JWT/token-revocation operational steps in scripts docs.
- Added deterministic auth recovery regression tests (`remote/internal/httpserver/handlers/auth_recovery_test.go`) validating SMTP recovery path and enforcing no token echo when `RECOVERY_TOKEN_ECHO=false`.
- Added canonical remote SSH wrapper script (`scripts/remote_exec.ps1`) with key-only defaults (`ecs-user@43.99.59.107`, `C:\Users\kl\.ssh\id_rsa`, `IdentitiesOnly=yes`).
- Added backup restore verification + incident response runbook (`BACKUP_DRILL.md`) and linked workflow/script usage.
- Implemented teacher progress filtering by `(course, student)` with synced session summaries: `StudentSessionsPage` now supports course filter and renders session summary text/LIT from `chat_sessions`, and teacher home course-student rows open sessions prefiltered by that course.
- Added marketplace search/filter/pagination in `MarketplacePage` (search by subject/teacher/description, grade filter, paged results with prev/next controls) and switched marketplace enrollment/quit/download workflow statuses to persistent, manually dismissible messages.
- Replaced remaining workflow-critical teacher-home snackbars (server sync failure and upload preflight folder-missing) with persistent, manually dismissible status messages.
- Implemented teacher upload preflight UX order on teacher home upload flow: local validation -> semantic hash compare with latest remote bundle -> KP added/deleted/updated confirmation before upload when hashes differ.
- Added blocking server-sync UX on welcome/teacher/student flows: during server sync, UI is greyed out and a bottom progress panel shows current phase (`enrollments -> sessions -> refresh status` where applicable).
- Added P0 regression coverage for enrollment deletion-event replay on login, including cursor forwarding/advance and role-specific cleanup (student removes local assigned course; teacher preserves course while removing only affected student assignment/progress).
- Added P3 contract tests for marketplace identity and visibility invariants (`teacher_id + course_name_key` uniqueness and auto-unpublish when the last bundle version is deleted).
- Added P3 regression coverage for bundle extraction/import ordering and large-archive `InputFileStream` lifecycle handling (`extractBundleFromFile`, `readPromptMetadataFromBundleFile`).
- Confirmed and closed P3 bundle-packaging whitelist TODO: `test/course_bundle_service_test.dart` asserts `createBundleFromFolder` includes only required assets and that irrelevant files do not change semantic hash.
- Added scripted prompt quality checks: prompt scope precedence tests (`system -> course -> student`) and expanded structured-output schema validation tests.
- Added remote preflight checker script (`scripts/preflight_remote_upload_and_storage.ps1`) to verify `STORAGE_ROOT` permissions (`ftapp` write + `nginx` read/traverse) and enforce `BUNDLE_MAX_BYTES == nginx client_max_body_size`.
- Added regression tests for normalized-subject reconciliation in enrollment sync to prevent `_<timestamp>` duplicate local course rows (teacher and student flows).
- Added compatibility test coverage for student quit-request sync when `/api/enrollments/quit-requests` returns `404` on older servers.
- Replaced `integration_test/app_flow_test.dart` placeholder with a deterministic auth-gated flow test (`register teacher -> logout -> login`) using in-memory DB and mocked `path_provider`.
- Added API integration coverage for enrollment gating and bundle download authorization (`remote/internal/httpserver/handlers/enrollment_bundle_api_test.go`) including teacher/private/already-enrolled request gating and download allow/deny for teacher/enrolled/non-enrolled users.
- Added server-side stale-link recovery API tests for `EnsureBundle` (`remote/internal/httpserver/handlers/teacher_courses_ensure_bundle_test.go`): stale `course_id` returns `404` when unresolved, and fallback by `course_name` returns resolved `course_id`.
- Added client-side stale-link regression coverage via `TeacherMarketplaceUploadService` + tests (`test/teacher_marketplace_upload_service_test.dart`), asserting upload publish uses `ensureBundle` returned `course_id` for visibility updates.
- Added end-to-end smoke script `scripts/smoke_teacher_student_flow.ps1` covering teacher upload -> student enroll -> teacher approve -> student download plus local ZIP import-readiness checks.
- Implemented teacher marketplace visibility on teacher home.
- Refined teacher course management UI: course version actions focus on `Reload Course` and `Upload Bundle`.
- Added separate `(course, student, tree)` section for teacher progress-tree access.
- Implemented teacher course deletion flow with confirmation text and remote marketplace deletion.
- Added bundle metadata application guard with `version_id` to prevent older overwrite.
- Fixed student bundle download `403` caused by Nginx file permission mismatch on storage path.

Historical completions were moved to `LOGBOOK.md`.
