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
