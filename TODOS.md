# TODOS
Last updated: 2026-02-26

## P0 Stability
- Add API integration test for student bundle download authorization (`approved` succeeds, others fail).
- Add deployment smoke test script covering: teacher upload -> student enroll -> teacher approve -> student download.
- Add preflight check for storage permissions (`nginx` read access to `STORAGE_ROOT`).

## P1 Product completion
- Add teacher-side filtered progress view by `(course, student)` with synced session summaries.
- Add marketplace search/filter (teacher, subject, grade) and pagination.
- Add remote/local conflict handling policy for course re-download and prompt metadata overwrite.

## P2 Security/ops
- Rotate temporary secrets in `SECRETS.md` and disable `RECOVERY_TOKEN_ECHO` in production.
- Enable SMTP production mode for recovery flow and add failure alerting.
- Add automated DB backup verification restore test.
