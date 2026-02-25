# Project Memory - family_teacher

## Work routine
- After a code change, before updating DONES.md, run flutter build windows --release (timeout = 10min). make sure it works. If not, use the error message to fix your code. Max retry 3 times for the same error. 
- If build is working, do git commit and push, you fill in the commit message. 

## Snapshot (2026-02-06)
- Flutter app for a "family teacher" MVP with LLM-backed tutoring, skill trees, and student progress tracking.
- Boot flow: `lib/main.dart` -> `AppBootstrap` -> `AppServices` -> Providers with role-based routing.
- Sessions: `SessionService` renders prompts (assets plus templates), calls `LlmService`, stores chat messages and summaries, and updates progress.
- Course management: `CourseService` loads course folders into a skill tree and validates required lecture files.
- Persistence: Drift/SQLite database with users, courses, sessions, progress, LLM calls, and prompt templates.
- Optional STT/TTS support for tutoring sessions.

## Key Areas
- `lib/`: app bootstrap, services, DB, models, UI, LLM.
- `assets/`: prompts, schemas, textbooks, teacher assets.
- `android/`, `ios/`, `windows/`, `macos/`, `linux/`, `web/`: platform scaffolding.

## Platform Notes (2026-02-06)
- Windows-only behavior is guarded by `Platform.isWindows`, but desktop deps remain in `pubspec.yaml`.
- Android scaffold exists; build validation required to confirm compatibility.

## References
- `README.md` for overview and logical flow.
- `BUGS.md` for known issues and build failures.
- `TODOS.md` for prompt-architecture TODOs.
- `DONES.md` for job in progress and finished. After a job is finished, remove from TODOS.
- `PLANS.md` for major roadmap and tech choices.
- `WORKLOG.md` for server setup and deployment actions.
- `SECRETS.md` for temporary credentials (to rotate later).

## Experience Learned (2026-02-16)
- Prompt scope behavior is now explicit: teacher default scope edits the base system prompt override (per prompt), while course/student scopes remain additive append templates.

## Experience Learned (2026-02-22)
- Prompt loading flow: `PromptRepository` loads bundled prompt text from `assets/prompts/<name>.prompt.txt` (fallback `.txt`), optionally overrides the system prompt per teacher, then appends course/student scoped templates; `SessionService` selects `learn_init/learn_cont` or `review_init/review_cont` based on prior `turn_state`, renders variables via `PromptRenderer`, and uses `summary` + `summarize` schema for final summaries; legacy `learn/review/summarize` prompts remain available.
- PromptTemplateValidator required variables must appear as placeholders in system prompts; missing placeholders trigger validation warnings and drop context from renders.

## Experience Learned (2026-02-25)
- Structured tutor prompts must return valid JSON with required keys (especially `teacher_message`), otherwise surface an error instead of displaying raw JSON.

## Experience Learned (2026-02-25)
- After setting a MySQL root password, `sudo mysql` no longer works without `-p`; create app users for both `localhost` and `127.0.0.1` to cover socket vs TCP connections.

## Experience Learned (2026-02-25)
- When writing Nginx configs from PowerShell, `$host` must be preserved (use a single-quoted here-string + base64) to avoid invalid directives; remove the default `server` block in `nginx.conf` to prevent 80/443 conflicts.

## Experience Learned (2026-02-25)
- Running `go mod tidy` inside the repo with `GOPATH` under the repo creates `go/pkg/mod` inside the module, which breaks `go list`; set `GOPATH` and `GOMODCACHE` outside the repo (e.g., `/var/lib/family_teacher_remote/go`).

## Experience Learned (2026-02-25)
- For authenticated file downloads on a single host, use Nginx `X-Accel-Redirect` with an internal `alias` (e.g., `/_files/`) to keep access checks in the API and serve files efficiently.

## Experience Learned (2026-02-25)
- When accepting large uploads, set both API `BodyLimit` and Nginx `client_max_body_size` to the same max (and keep `STORAGE_ROOT` on a writable filesystem).

## Experience Learned (2026-02-25)
- Auth UI now uses username/password with separate teacher/student registration; recovery email is used for 2FA/recovery only, `AuthController` requires `SecureStorageService`, and l10n labels now reflect username + password (including reset-password text).

## Experience Learned (2026-02-25)
- Auth now uses username + recovery email (email is for 2FA/recovery only); recovery flows are exercised via `scripts/test_auth.ps1`.

## Experience Learned (2026-02-25)
- Recovery email delivery uses SMTP when enabled; `RECOVERY_TOKEN_ECHO` should be true only for dev/testing, and recovery requests should fail if SMTP is disabled without echo.

## Experience Learned (2026-02-25)
- Auth endpoints now have per-IP rate limiting; request-recovery avoids account enumeration by returning consistent responses.

## Experience Learned (2026-02-25)
- Marketplace APIs require role checks (teacher account for publish/approvals) and only list `course_catalog_entries` with `visibility='public'` for the public catalog.
