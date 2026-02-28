# Memory Hook Sub-Agent (Layman Steps)

1. Triggered by
- Run this hook after memory markdown files change: `powershell -File scripts/hook_memory_update.ps1`.
- It starts only when a memory markdown file changed by more than 10 lines since the last snapshot, or when you force a target (for example `-ForceTargets workflows.md`).
- Pre-push does not run this hook.

2. Read files as variables
- Reads main rules file: `C:\family_teacher\app\AGENTS.md` as `{agents_md}`.
- Reads changed target memory files as `{target_files}` (full content per file).
- Reads other memory files as `{other_memory_files}` (file names only, no content).
- Reads target list as `{targets}`.

3. Call Codex with arguments + session_id handling
- Hook builds sub-agent prompt file `C:\family_teacher\app\scripts\memory_hook_agent\AGENTS.md` every run by combining:
  - template: `C:\family_teacher\app\scripts\memory_hook_agent\AGENTS.template.md`
  - full text of root: `C:\family_teacher\app\AGENTS.md`
- Codex runs from sub-agent project folder: `C:\family_teacher\app\scripts\memory_hook_agent`.
- The script sends `{targets}`, `{agents_md}`, `{target_files}`, `{other_memory_files}` to Codex as one JSON input message.
- Session id is stored in tracked file `C:\family_teacher\app\scripts\memory_hook_agent\memory_hook_state.json`.
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
