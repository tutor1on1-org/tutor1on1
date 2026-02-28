# WORKFLOW
Last updated: 2026-02-28

## Standard workflow
1. Understand scope and locate the true failing/target layer.
2. For bugs, reproduce with evidence first (logs, repro script, or minimal failing test).
3. Implement the minimal correct root-cause change.
4. Validate changed path first, then adjacent regressions, then end-to-end path when feasible.
5. Run `flutter build windows --release` before updating `DONEs.md`.
6. If backend under `remote/` changed, rebuild binary and restart service before reporting done.
7. Update memory docs intentionally; the memory hook auto-consolidates only memory markdown files whose line-count delta is `>10` from `scripts/memory_line_snapshot.json`.
8. Update docs (`BUGS.md`, `LOGBOOK.md`, `TODOS.md`, `DONEs.md`) as applicable.
9. Run `powershell -ExecutionPolicy Bypass -File scripts/validate_project.ps1 -NoPostHook`.
10. Commit and push in the same turn after validation unless the user explicitly says not to push.

## Bug-fix discipline
1. Reproduce with evidence (logs, script, or minimal failing test).
2. Pinpoint root cause, not symptom.
3. Apply fix without workaround/bypass unless explicitly approved.
4. Validate:
   - failing path now passes,
   - adjacent path still passes,
   - end-to-end path checked when feasible.
5. Record lesson in `BUGS.md` with root cause and prevention rule.
6. For ZIP/archive handling with `InputFileStream`, keep the stream open until all lazy reads (validation/extraction/metadata parsing) finish; close only in `finally`.
7. In `try/finally`, do not return un-awaited futures that depend on temp files/resources cleaned up in `finally`; await completion before cleanup.

## Validation baseline
- Prefer automated checks (`flutter test`, `go test`, scripted API checks).
- In this workspace, run desktop integration tests with an explicit target (example: `flutter test integration_test/app_flow_test.dart -d windows`).
- For authenticated multipart API smoke paths on Windows PowerShell, prefer `curl.exe`.
- Keep user-facing errors persistent and copyable for important failures.
- Do not silently swallow errors; fail fast and fix root issue.
- For teacher bundle upload: validate local folder first, compare local semantic hash with latest remote hash, and require explicit confirmation after showing KP added/deleted/updated counts when hash differs.
- Bundle packaging must include only required course assets and prompt text assets; exclude unrelated files to avoid false-positive version/hash changes.

## Remote ops workflow
1. Build backend artifact.
2. Deploy binary to server path.
3. Restart `family-teacher-api.service`.
4. Verify health endpoint and log tails.
5. Re-check storage permissions and body-size alignment if upload/download behavior changed.
6. Use key-only SSH for remote ops (`-i C:\\Users\\kl\\.ssh\\id_rsa -o IdentitiesOnly=yes`).

## Backup and incident workflow
1. Run the restore drill from `BACKUP_DRILL.md` monthly and after schema changes.
2. Verify restored DB via auth + enrollment/download smoke scripts before marking drill successful.
3. Keep drill evidence (artifact id, restore duration, smoke outputs, owner).
4. During incidents, follow the `BACKUP_DRILL.md` incident checklist from declaration through postmortem.

## Documentation workflow
- `AGENTS.md` stays minimal and only points to docs.
- `update memory` should focus on docs that changed meaningfully; memory hook targets only memory markdown files with line-count delta `>10`.
- Keep `README.md` aligned with current architecture and final product aim.
- Keep `SCRIPTS.md` command-accurate; remove stale commands immediately.
- Keep `LOGBOOK.md` chronological (history), and `WORKLOG.md` operational (active runbook).
- When memory-hook behavior changes, update `scripts/memory_hook_agent/README.md` in the same change.

## Hooks workflow
- Install tracked hooks once per clone: `powershell -ExecutionPolicy Bypass -File scripts/install_githooks.ps1`.
- Tracked pre-push runs `scripts/validate_project.ps1 -NoPostHook` and blocks push on failures.
- Run `scripts/hook_memory_update.ps1` after memory markdown edits (or force targets manually) to consolidate memory docs.
- Direct runs of `scripts/hook_memory_update.ps1` auto-commit and auto-push memory updates when changes are applied.
- `scripts/post_validate_hook.ps1` remains an optional manual path.
