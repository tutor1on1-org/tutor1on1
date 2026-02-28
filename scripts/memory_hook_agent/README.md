# Memory Hook Sub-Agent (Layman Steps)

1. Triggered by
- Usually before push: `.githooks/pre-push` runs `scripts/hook_memory_update.ps1 -SkipGitOps`.
- Can also be run manually: `powershell -File scripts/hook_memory_update.ps1`.
- It starts only when a memory markdown file changed by more than 10 lines since the last snapshot, or when you force a target (for example `-ForceTargets workflows.md`).

2. Read files as variables
- Reads main rules file: `C:\family_teacher\app\AGENTS.md` as `{agents_md}`.
- Reads changed target memory files as `{target_files}` (full content per file).
- Reads other memory files as `{other_memory_files}` (full content per file).
- Reads target list as `{targets}`.

3. Call Codex with arguments + session_id handling
- System prompt comes from `C:\family_teacher\app\scripts\memory_hook_agent\AGENTS.md`.
- The script sends `{targets}`, `{agents_md}`, `{target_files}`, `{other_memory_files}` to Codex as one JSON input message.
- Session id is stored in `C:\family_teacher\app\.git\memory_hook_state.json`.
- If session id exists, script calls `codex exec --json resume {session_id}`.
- If no session id (or resume fails), script starts a new session with `codex exec --json --output-schema ...`.
- When Codex returns a new thread id, script saves it for next run.

4. Codex returns JSON with fields
- `updated_files`: list of full replacement content for target files.
- `append_suggestions`: list of text blocks to append to other memory files.
- `notes`: short summary.

5. Update target files
- For each item in `updated_files`, script replaces the whole target file content.
- It rejects any `updated_files.path` that is not in the target list.

6. Append other files
- For each item in `append_suggestions`, script appends text to that file.
- It only allows known memory files and blocks appending to target files.
- Invalid paths or duplicates cause the hook to fail.

7. Git behavior
- The hook updates `scripts/memory_line_snapshot.json` after a real apply run.
- Manual/direct run (default): auto `git add`, `git commit`, and `git push` memory changes.
- Pre-push run uses `-SkipGitOps`, so it does not auto-commit/push there.
