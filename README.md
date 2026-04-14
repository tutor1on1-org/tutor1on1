# Tutor1on1

Tutor1on1 is a family teaching platform for building structured courses, publishing them to approved students, and running guided LLM tutoring sessions against those courses.

The project contains a Flutter client and a Go remote API. The client owns the local learning experience: teacher course preparation, student study sessions, prompt execution, speech features, local persistence, and artifact sync. The remote API owns accounts, teacher approval, marketplace visibility, enrollments, bundle delivery, and canonical artifact metadata.

## Product Goal

The long-term goal is a production-ready teacher/student workflow where:

1. Teachers create or import a course version.
2. The app validates the course structure and prompt bundle.
3. Teachers publish a course bundle to the marketplace.
4. Students browse available courses and request enrollment.
5. Teachers approve enrollment.
6. Students download the approved bundle and study locally with LLM tutoring.
7. Client and server sync only changed zip artifacts and verify parity through persisted artifact manifests.

## Current Shape

- Flutter client package: `tutor1on1`, currently version `1.0.31`.
- Public release targets: Android APK and Windows ZIP.
- Backend: Go + Fiber API with MySQL persistence and filesystem-backed artifact/bundle storage under `STORAGE_ROOT`.
- Local data: Drift/SQLite, secure storage for secrets/tokens, local artifact cache for downloaded and generated zip artifacts.
- LLM tutoring: prompt templates, prompt-bundle metadata, structured response handling, session logs, TTS/STT support, and tutor modes for learning/review.
- Public download artifacts use stable names: `Tutor1on1.apk`, `Tutor1on1.zip`, and `SHA256SUMS.txt`.

## User Roles

- Student: browse marketplace courses, request enrollment, download approved bundles, study knowledge points, review progress, and sync local learning artifacts.
- Teacher: build course versions, manage skill trees, upload marketplace bundles, approve enrollments, and use study-mode controls.
- Subject/admin roles: review teacher/course registration flows and manage access where enabled by the remote API.

## Sync Contract

Artifact sync is the active canonical sync model. The equality check is the persisted zip-artifact manifest/state only:

- `course_bundle` artifacts represent published course bundles.
- `student_kp` artifacts represent student knowledge-point learning state.
- `state2` is the compact parity hash.
- `state1` is the manifest used to diff individual artifact IDs.
- Normal sync compares `state2`, fetches `state1` only when needed, transfers changed zip artifacts, and verifies final parity.

Row-level session/progress/message sync is retired as the canonical cross-device/server sync contract. Local learning state can exist locally, but cross-device/server parity is decided by artifacts.

## Repository Layout

- `lib/` - Flutter client code, including UI, app state, local database, LLM, sync, TTS/STT, and remote API services.
- `assets/` - prompts, schemas, sample textbook material, and teacher assets bundled with the client.
- `test/` and `integration_test/` - Flutter unit and integration tests.
- `remote/` - Go remote API, migrations, handlers, storage, artifact-sync helpers, and repair/cutover tools.
- `scripts/` - validation, release, publishing, migration, and operational helper scripts.
- `tool/` - project tooling used by scripts and maintenance workflows.
- `public_release/` and `web/` - public client website/download metadata and static site assets.
- `LEGAL/` and `third_party/` - public snapshot legal material and bundled third-party references.

## Development Entry Points

Common local commands:

```powershell
flutter pub get
flutter analyze
flutter test
```

Remote API checks run from `remote/`:

```powershell
go test ./...
```

The main project validation entry point is:

```powershell
.\scripts\validate_project.ps1
```

The public release entry point is:

```powershell
.\scripts\release_public.ps1
```

`release_public.ps1` validates, handles the git/tag flow when enabled, publishes the Android APK, publishes the Windows ZIP, and refreshes GitHub Release assets. Website publishing is opt-in with `-PublishWebsite`.

## Documentation Map

- `AGENTS.md` - concise index for project memory and operating rules.
- `WORKFLOW.md` - standard work and validation flow.
- `SCRIPTS.md` - concrete command reference.
- `PUBLIC_CLIENT_README.md` - public-client distribution scope.
- `VERSIONING.md` - public release versioning checklist.
- `sync.md` - current artifact-sync design notes.
- `BUGS.md`, `LESSONS.md`, `TODOS.md`, `LOGBOOK.md`, and `WORKLOG.md` - project memory, lessons, backlog, and operation history.
