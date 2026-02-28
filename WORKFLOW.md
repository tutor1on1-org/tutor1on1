# WORKFLOW
Last updated: 2026-02-27

## Standard workflow
1. Understand scope and locate the true failing/target layer.
2. Implement minimal, correct change at root cause.
3. Validate directly on changed layer, then run adjacent-layer regression checks.
4. Run `flutter build windows --release` before updating `DONEs.md`.
5. If backend under `remote/` changed, rebuild binary and restart service before reporting done.
6. Update memory docs intentionally; memory hook will auto-consolidate only files whose line count delta is greater than `10` since its last snapshot.
7. Update docs (`BUGS.md`, `LOGBOOK.md`, `TODOS.md`, `DONEs.md`) as applicable.
8. After feature changes are committed, run `powershell -ExecutionPolicy Bypass -File scripts/validate_project.ps1 -NoPostHook` as the validation gate.

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

## Backup and incident workflow
1. Run the restore drill from `BACKUP_DRILL.md` monthly and after schema changes.
2. Verify restored DB via auth + enrollment/download smoke scripts before marking drill successful.
3. Keep drill evidence (artifact id, restore duration, smoke outputs, owner).
4. During incidents, follow the `BACKUP_DRILL.md` incident checklist from declaration through postmortem.

## Documentation workflow
- `AGENTS.md` stays minimal and only points to docs.
- `update memory` should focus on docs that changed meaningfully; pre-push memory hook targets only memory markdown files with line-count delta `>10`.
- Keep `README.md` aligned with current architecture and final product aim.
- Keep `SCRIPTS.md` command-accurate; remove stale commands immediately.
- Keep `LOGBOOK.md` chronological (history), and `WORKLOG.md` operational (active runbook).

## Hooks workflow
- Install tracked hooks once per clone: `powershell -ExecutionPolicy Bypass -File scripts/install_githooks.ps1`.
- Pre-push hook runs `scripts/hook_memory_update.ps1` first, then project validation gate, and blocks push on failures.
- If memory hook writes updates, pre-push blocks push until those memory files plus snapshot are committed.
- Direct runs of `scripts/hook_memory_update.ps1` auto-commit and auto-push memory updates when changes are applied.
- `scripts/post_validate_hook.ps1` remains an optional manual path.
