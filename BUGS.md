# BUGS
Last updated: 2026-03-08

## Active watch
- Student import race after bundle download (monitoring): fixed by awaiting archive extraction in client bundle service (`f77e7e0`); keep watching for recurrence in production-like flow.

## Lessons learned (do not repeat)
1. Archive extraction race
- Symptom: intermittent `Missing file: ...contents.txt (or ...context.txt)` right after download.
- Root cause: `extractArchiveToDisk(...)` is async and was called without `await`.
- Prevention: always await extraction before any import/validation step.

2. Drift migration sequencing
- Symptom: duplicate-column failures during upgrades.
- Root cause: `addColumn` executed even when table was created mid-upgrade.
- Prevention: guard `addColumn` with `from >= <tableCreateVersion>` when table creation is conditional.

3. Bundle validity drift between client and server
- Symptom: invalid bundles can appear as latest downloadable versions.
- Root cause: relying on client-only validation.
- Prevention: enforce required bundle files and lecture-reference checks on server upload path too.

4. Tutor output parsing failures
- Symptom: invalid LLM response rendered as unusable content.
- Root cause: non-JSON or missing required fields.
- Prevention: require valid structured JSON and `teacher_message`; surface parse errors explicitly.

5. Authenticated download 403 on server
- Symptom: API approved download but Nginx denied file read.
- Root cause: Nginx worker lacked storage read/traverse permission.
- Prevention: ensure `nginx` can traverse/read `STORAGE_ROOT` (group membership and permissions).

6. Remote shell automation instability
- Symptom: non-interactive SSH commands fail intermittently.
- Root cause: missing `PATH` entries in some ECS sessions.
- Prevention: use absolute tool paths in automation scripts.

7. Bundle ZIP lazy-read stream lifecycle
- Symptom: student download/import fails with `FormatException: Filter error, bad data` on valid bundles (more visible on larger bundles).
- Root cause: `InputFileStream` was closed immediately after `ZipDecoder().decodeBuffer(...)`; archive entries are lazy-read later during validation/extraction, so reads occurred on a closed file handle.
- Prevention: keep `InputFileStream` open for the full lifetime of archive entry access and close in `finally` only after extraction/metadata/validation completes. Add regression test with a >1 MB zip to catch premature stream closure.

8. Student course duplication on re-download
- Symptom: student sees version-like duplicate course names and progress appears split across versions after downloading updates.
- Root cause: manual marketplace download imported as a fresh local course using extracted folder basename (timestamp/version-like), replacing remote link and orphaning old local progress.
- Prevention: resolve existing `remoteCourseId -> courseVersionId`, then import with `override` mode and explicit server `course_subject` as course name.

9. Session sync rate-limit bursts
- Symptom: `Session sync failed: rate limit exceeded` during login/startup sync.
- Root cause: progress sync uploaded one request per progress row; large local progress sets exceeded sync API rate limits.
- Prevention: upload progress entries in a single batch request (`/api/progress/sync/upload-batch`) and process server-side in one transaction.

10. Teacher catalog shrink after quit approvals
- Symptom: teacher local course list drops courses after student quit approval/deletion events, while marketplace still has them.
- Root cause: teacher-side deletion-event replay removed student data and then deleted the whole local course when assignment count reached zero.
- Prevention: for teacher replay, never delete course definitions from assignment count checks; only remove the specific student-course data.

11. Suffix-duplicate local courses from sync fallback
- Symptom: local lists show `{name}_{version_id}` duplicates and stale unlinked rows; clicking versions can fail with "No remote bundle found".
- Root cause: when `remoteCourseId` mapping was missing, sync/import created fresh placeholder courses using suffix-tainted subject names instead of reconciling by normalized name.
- Prevention: reconcile by normalized subject (strip trailing `_<timestamp>`), relink to remote course, and migrate stale student data to canonical course IDs before deleting duplicates.

12. Local plugin override interface drift
- Symptom: `flutter build windows --release` fails with override signature errors in `packages/record_linux` after dependency resolution updates.
- Root cause: local path override implemented an outdated platform-interface method signature (`hasPermission(String)`), while `record_platform_interface` required `hasPermission(String, {bool request = true})`.
- Prevention: keep all local package overrides in lockstep with platform-interface method signatures whenever dependencies are refreshed; verify with release build gate.

13. Windows secure-storage sync state contention
- Symptom: session sync becomes very slow and can fail with `PathAccessException ... flutter_secure_storage.dat ... used by another process`.
- Root cause: thousands of per-item sync states were stored in `flutter_secure_storage`; on Windows the plugin reads/decrypts and rewrites the whole encrypted file for each key operation, which creates heavy local I/O and file-lock races under large sync sets.
- Prevention: keep secure storage for low-cardinality secrets only, store high-cardinality sync metadata/state in SQLite, and use manifest+fetch sync so normal download sync does not depend on per-row cursor chatter.
