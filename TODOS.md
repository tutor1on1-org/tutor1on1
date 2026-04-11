# TODOS
Last updated: 2026-04-11

## Source of truth
- Current sync model is zip-artifact manifest sync. The server copy is canonical; do not add fallback/merge recovery when local sync state disagrees. For user recovery, wipe local state and rebuild from the server.
- After any sync-model pivot, align active reference docs in the same turn: `README.md`, `PLANS.md`, `PUBLIC_CLIENT_README.md`, `LEGAL/*`, and `WORKLOG.md`; mark old row-level sync content historical instead of leaving retired architecture as active guidance.

## P0 Reliability
- [ ] Audit active docs for retired row-level session/progress/enrollment sync claims and update them to artifact-manifest sync or explicitly mark them historical.
  - Scope: `README.md`, `PLANS.md`, `PUBLIC_CLIENT_README.md`, `LEGAL/*`, `WORKLOG.md`.
- [ ] Keep student/server-copy recovery strict: local state that disagrees with server must be reset from server rather than merged.
  - Scope: `lib/services/student_server_copy_service.dart`, student Settings recovery path, student home sync path.
- [ ] Verify teacher fresh-device login creates teacher-home student/course scaffolds from active server enrollments even when `student_kp` payload download is deferred.
  - Scope: `lib/services/enrollment_sync_service.dart`, artifact sync state2 fast paths, teacher home student/course list queries.
- [ ] Ensure artifact cutover/repair recovers progress from durable session evidence when explicit progress rows are missing before rebuilding canonical `student_kp` artifacts.
  - Scope: `remote/cmd/artifact_cutover`, artifact repair tooling, regression coverage.
- [ ] Enforce dotted numeric KP ordering across parser, UI lists, and persisted `course_nodes.order_index`.
  - Scope: shared dotted comparator, course parser children, search/detail lists, import persistence; include `1.1`, `1.2`, `1.10`, `1.11` regression coverage.

## P1 Product completion
- [ ] Keep teacher login responsive by limiting the blocking path to data needed for first home render; move full `student_kp` backfill to background sync with visible failure handling.
  - Scope: `HomeSyncCoordinator`, `SessionSyncService`, teacher home startup flow.
- [ ] Keep remote course import scaffold-only on login and defer full lecture/question materialization until an explicit action needs it.
  - Scope: course bundle import, cached canonical bundle reads, lazy lecture/question loading.
- [ ] Avoid duplicate course artifact rebuilds during remote import.
  - Scope: `applyCourseLoad()`, `storeImportedContentBundle()`, cached upload/hash seeding.
- [ ] Preserve prompt metadata integrity during sync.
  - Scope: validate downloaded prompt metadata before clearing active scope rows, fail loudly on invalid contracts, and reuse matching `(scope, content, created_at)` history rows instead of duplicating them.

## P2 Security and operations
- [ ] Make auth device identity durable across secure-storage resets and enforce server-side least-recently-used device eviction at the device cap.
  - Scope: local non-sensitive `device_key` backup, secure-storage restore path, server account-device insertion path, refresh-token revocation for evicted devices.
- [ ] Keep first-party API traffic direct on desktop so launcher proxy environment variables cannot slow or break `api.tutor1on1.org` sync/login calls.
  - Scope: `AuthApiService`, `MarketplaceApiService`, `ArtifactSyncApiService` HTTP client construction.
- [ ] Keep public macOS downloads hidden until there is a signed/notarized `Developer ID Application` release.
  - Scope: website install pages, `web/site.js`, release scripts.

## P3 Quality engineering
- [ ] Keep regression tests for enrollment `state2` parity and due-interval clean-second-sync behavior.
  - Scope: `test/enrollment_sync_service_test.dart`.
- [ ] Keep regression tests for no-upload-after-force-pull and MB-bearing sync progress reporting.
  - Scope: `test/session_sync_service_test.dart`.
- [ ] Keep bootstrap/loading-shell tests that verify startup scaffolds do not require localizations before `MaterialApp` localizations are mounted.
  - Scope: startup shell widgets and localization fallback helpers.
