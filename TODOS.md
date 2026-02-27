# TODOS
Last updated: 2026-02-27

## P0 Reliability
- Add end-to-end smoke script: teacher upload -> student enroll -> teacher approve -> student download -> client import verify.
- Add API integration tests for enrollment gating and bundle download authorization.
- Add regression tests for server-authoritative course sync and deletion-event replay on login across multi-device state.
- Add stale-link recovery coverage: stale `course_id` returns `404`, `ensureBundle` falls back by `course_name`, and client reuses returned `course_id` for publish/visibility.

## P1 Product completion
- Implement teacher progress filtering by `(course, student)` with synced session summaries.
- Add marketplace search/filter/pagination.
- Define and implement remote/local conflict policy for re-download and prompt metadata overwrite.
- Enforce persistent, manually dismissible UI status messages for workflow-critical states.
- Implement teacher upload preflight UX order: local validation -> semantic hash compare -> KP added/deleted/updated confirmation.

## P2 Security and operations
- Rotate temporary credentials in `SECRETS.md`.
- Rotate JWT signing secret and replace any exposed long-lived tokens.
- Disable `RECOVERY_TOKEN_ECHO` in production and validate SMTP recovery path.
- Add backup restore verification drill and incident checklist.
- Script remote ops defaults to canonical key-only SSH tuple (`ecs-user@43.99.59.107`, `C:\\Users\\kl\\.ssh\\id_rsa`, `IdentitiesOnly=yes`).

## P3 Quality engineering
- Replace placeholder `integration_test/app_flow_test.dart` with real scenario coverage.
- Add regression tests around bundle extraction/import ordering.
- Add regression tests for `InputFileStream` lifecycle and `try/finally` cleanup with awaited futures.
- Add scripted checks for prompt scope precedence and structured output validation.
- Add bundle packaging whitelist tests so semantic hash only tracks required assets.
- Add contract tests for marketplace uniqueness key `(teacher_id + course_name_key)` and auto-unpublish when last bundle version is deleted.
