# DONES
Last updated: 2026-02-27

- Added remote preflight checker script (`scripts/preflight_remote_upload_and_storage.ps1`) to verify `STORAGE_ROOT` permissions (`ftapp` write + `nginx` read/traverse) and enforce `BUNDLE_MAX_BYTES == nginx client_max_body_size`.
- Added regression tests for normalized-subject reconciliation in enrollment sync to prevent `_<timestamp>` duplicate local course rows (teacher and student flows).
- Added compatibility test coverage for student quit-request sync when `/api/enrollments/quit-requests` returns `404` on older servers.
- Implemented teacher marketplace visibility on teacher home.
- Refined teacher course management UI: course version actions focus on `Reload Course` and `Upload Bundle`.
- Added separate `(course, student, tree)` section for teacher progress-tree access.
- Implemented teacher course deletion flow with confirmation text and remote marketplace deletion.
- Added bundle metadata application guard with `version_id` to prevent older overwrite.
- Fixed student bundle download `403` caused by Nginx file permission mismatch on storage path.

Historical completions were moved to `LOGBOOK.md`.
