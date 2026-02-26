# DONES
Last updated: 2026-02-26

- Implemented teacher marketplace visibility on teacher home.
- Refined teacher course management UI: course version actions focus on `Reload Course` and `Upload Bundle`.
- Added separate `(course, student, tree)` section for teacher progress-tree access.
- Implemented teacher course deletion flow with confirmation text and remote marketplace deletion.
- Added bundle metadata application guard with `version_id` to prevent older overwrite.
- Fixed student bundle download `403` caused by Nginx file permission mismatch on storage path.

Historical completions were moved to `LOGBOOK.md`.
