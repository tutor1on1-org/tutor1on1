# BUGS
Last updated: 2026-02-26

## Open
- ECS shell environment can have empty `PATH` in some non-login SSH commands. Use absolute paths or fix profile scripts.
- Marketplace download/import intermittent failure (`Missing file: ...contents.txt or ...context.txt`) on student side:
  - Root cause: `extractArchiveToDisk(...)` was async and not awaited in `CourseBundleService`.
  - Fix shipped: `f77e7e0` (await extraction in both extract paths).
  - Validation done: repeated scripted extract->preview import checks passed; server latest bundle verified includes `contents.txt`.
  - Keep as monitoring item until no recurrence in real user flow.

## Closed / historical
- Moved to `LOGBOOK.md`.
