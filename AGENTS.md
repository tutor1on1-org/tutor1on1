# Project Memory - family_teacher

## Summary Docs Check (2026-01-31)
- README.md exists but is Flutter boilerplate (no project-specific summary found).

## Project Summary (2026-01-31)
- Flutter app for a "family teacher" MVP with LLM-backed tutoring, skill trees, and student progress tracking.
- Architecture: `lib/main.dart` boots app with single-instance guard, then `AppBootstrap` builds `AppServices` and wires Providers (auth + settings).
- Local persistence: Drift/SQLite database in app documents directory with tables for users, courses/skill tree, assignments, chat sessions/messages, LLM calls, and prompt templates.
- Core services include LLM orchestration, prompt storage/validation, session management, STT/TTS, logging, backup, and settings.
- UI is role-based (admin/teacher/student) with pages for skill trees, course versions, prompt settings, logs, and tutoring sessions.

## Folder Map (Key Areas)
- `lib/`: main entry, app bootstrap, providers, UI pages/widgets, services, DB layer, models, LLM logic, security helpers, l10n.
- `assets/`: prompts, schemas, textbooks, teacher assets.
- `android/`, `ios/`, `windows/`, `macos/`, `linux/`, `web/`: platform scaffolding.

## Android Support Status (2026-01-31)
- Android scaffold exists under `android/`; `AndroidManifest.xml` includes microphone permission.
- Windows-only behavior is guarded by `Platform.isWindows` but still present (window manager, screen lock, Windows font).
- Desktop-specific deps still listed (`window_manager`, `just_audio_windows`, `record_linux` override); need Android build validation to confirm no conflicts.
- Android build/run not executed in this review.

## Bugs / Issues Encountered
- 2026-01-31: `flutter build apk` failed with `ZipException: zip END header not found`.
  Root cause: corrupted/incomplete Gradle distribution zip at
  `C:\Users\kl\.gradle\wrapper\dists\gradle-8.14-all\c2qonpi39x1mddn7hk5gh9iqj\gradle-8.14-all.zip`
  (size ~19MB, likely truncated). Deleting the zip (and `.lck`) should trigger re-download.
- 2026-01-31: `:app:processReleaseResources` failed with
  `java.nio.charset.MalformedInputException: Input length = 1`.
  Checked UTF-8 validity for all XML in `android/app/src` and all Android plugin
  manifests/resources listed in `.flutter-plugins-dependencies` (no invalid UTF-8 found).
  Likely source is a generated resource under build intermediates or a dependency
  resource not covered; need gradle `--info/--debug` or inspect build intermediates.
- 2026-01-31: Attempted `flutter build apk -v` failed due to Flutter SDK permissions:
  `CreateFile failed 5` at `C:\work\flutter` when Flutter tried to run `git log`.
  SDK location needs read/write permissions for current user.
