# SCRIPTS
Last updated: 2026-03-25

All commands are expected from repository root (`C:\family_teacher\app`) unless stated otherwise.

## Host shell alias
- `codexlast relay_letta_tutor` reopens the latest `relay_letta_tutor` Codex relay session and prints the relay name, session id, session path, message count, and numbered recent messages; when relaying its output to the user, keep the raw line layout and omit message timestamps.

## Local secrets policy
- Keep real credentials only in local `.env` (untracked).
- Use `.env.example` as the sanitized template and never commit real secrets.
- For shared/production environments, prefer managed secret injection over checked-in files.

## Memory update hook and validation
Install tracked git hooks:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/install_githooks.ps1
```

Run memory update hook now:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/hook_memory_update.ps1
```

Hook behavior:
- Track line counts in `scripts/memory_line_snapshot.json` (tracked file).
- Trigger Codex memory update only for memory markdown files whose line count changed by more than `10` since last hook run.
- Reuse a dedicated memory-hook Codex session from tracked file `scripts/memory_hook_agent/memory_hook_state.json`.
- Build sub-agent system prompt in `scripts/memory_hook_agent/AGENTS.md` each run by combining `scripts/memory_hook_agent/AGENTS.template.md` + full root `AGENTS.md`.
- Direct hook runs auto-commit and auto-push memory updates when changes are applied.
- Pre-push does not run this hook.

Validate project only:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/validate_project.ps1 -NoPostHook
```

Optional legacy post-validation publish hook:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/validate_project.ps1 -RunPostHook
```

## Flutter app setup
```powershell
flutter --version
flutter pub get
```

## Flutter static checks and tests
```powershell
flutter analyze
flutter test
flutter test test/migration_test.dart
flutter test test/prompt_scope_precedence_test.dart
flutter test test/schema_validator_test.dart
flutter test test/course_bundle_service_test.dart
flutter test --plain-name "migrates from v1 to v11"
```

## Integration tests
```powershell
flutter test integration_test/app_flow_test.dart
```
Current integration flow covers deterministic auth-gated register/logout/login path using in-memory DB and mocked path providers.

## Local app run and release build
```powershell
flutter build apk --config-only
flutter build apk --release
flutter run -d windows
flutter build windows --release
flutter build macos --release
```
Required workflow gate: run release build before updating `DONEs.md` after code changes.

## Utility scripts
### Consolidated public release
```powershell
powershell -ExecutionPolicy Bypass -File scripts/release_public.ps1
```
Default behavior:
- Syncs `web/site.js` release metadata from `pubspec.yaml` before validation/git/publish so website download links stay aligned with the GitHub Release tag.
- Runs `scripts/validate_project.ps1 -NoPostHook` first.
- Runs `git add -A`, `git commit`, and `git push` if the worktree is dirty.
- Publishes Android as `Tutor1on1.apk`.
- Publishes Windows as `Tutor1on1.zip`.
- Publishes GitHub Release assets for the configured public tag.
- Republishes the static website after artifacts are live.
Useful flags:
- `-SkipValidation`
- `-SkipGit`
- `-SkipAndroid`
- `-SkipAndroidBuild`
- `-SkipWindows`
- `-SkipWindowsBuild`
- `-SkipGitHubRelease`
- `-SkipPromptAssetTests`
- `-SkipZipValidation`
- `-SkipWebsite`

### Android release publish (build + upload)
```powershell
powershell -ExecutionPolicy Bypass -File scripts/publish_android_release.ps1
```
Optional flags:
- `-SkipBuild` (reuse existing `build/app/outputs/flutter-apk/app-release.apk`)

Default safeguards:
- Runs `flutter build apk --config-only` immediately before the release APK build to refresh Android plugin wiring when the Flutter toolchain regresses on `integration_test` dev dependencies.
- Publishes candidate first as `Tutor1on1_candidate.apk`.
- Publishes the canonical APK and a versioned alias such as `Tutor1on1-1.0.3.apk`, while deleting older versioned APK aliases so mobile download/install flows cannot reuse a stale same-name APK.
- Verifies remote SHA-256 against the local APK before promotion.
- Verifies both candidate and canonical public download URLs.
- Cleans old `Tutor1on1*.apk` and legacy `family_teacher*.apk` artifacts after promotion.

### Windows release publish (build + zip + upload)
```powershell
powershell -ExecutionPolicy Bypass -File skills/windows_release_publish/scripts/publish_windows_release.ps1
```
Optional flags:
- `-SkipBuild` (reuse existing `build/windows/x64/runner/Release`)
- `-SkipUpload` (build + zip only)
- `-SkipPromptAssetTests` (skip `test/prompt_assets_integrity_test.dart`)
- `-SkipZipValidation` (skip `skills/windows_release_publish/scripts/validate_windows_release_zip.ps1`)

Default safeguards:
- Prompt asset test gate runs before build.
- Clears stale `build/windows` output before rebuild so renamed executables do not inherit the old CMake target name.
- ZIP validator checks required runtime files and prompt asset UTF-8 readability.
- ZIP packaging uses `System.IO.Compression` for Windows Explorer compatibility.
- Remote publish uses candidate-first promotion before replacing canonical `Tutor1on1.zip`.
- Cleans the stale Windows candidate ZIP and legacy `family_teacher*.zip` artifacts, without glob-deleting other `Tutor1on1*.zip` packages.

### GitHub Release publish
```powershell
powershell -ExecutionPolicy Bypass -File public_release/publish_github_release.ps1
```
Optional flags:
- `-ReleaseTag v1.0.1`
- `-SkipPackage` (reuse existing `public_release/dist/<tag>` contents)
- `-SkipPubGet`
- `-SkipAnalyze`
- `-SkipTest`
- `-SkipAndroidBuild`
- `-SkipWindowsBuild`

Default safeguards:
- Builds or reuses `Tutor1on1.apk`, `Tutor1on1.zip`, and `SHA256SUMS.txt` under `public_release/dist/<tag>/`.
- Defaults the release tag/name from `pubspec.yaml` when not explicitly provided.
- Validates the packaged Windows ZIP with the same ZIP checker used by the server publish flow.
- Resolves a GitHub token from `GITHUB_TOKEN`/`GH_TOKEN` or `git credential fill`.
- Creates the GitHub Release if it does not exist, replaces same-name assets if it does, and uploads the canonical asset names only.

### Website static publish
```powershell
powershell -ExecutionPolicy Bypass -File scripts/publish_website_static.ps1
```
Default safeguards:
- Re-syncs `web/site.js` release metadata from `pubspec.yaml` before upload so standalone website publishes cannot drift from the public release tag.
- Clears the remote website root before syncing `web/` so deleted public pages are actually removed.
- Verifies the remote website tree after upload.
- Verifies localized home/help/install pages return HTTP 200, install pages reference `Tutor1on1.apk` / `Tutor1on1.zip`, and removed macOS install pages no longer return HTTP 200.

### Future macOS notarized release package
Do not publish or relink macOS on the website until the app is runnable.

Create notary credentials once on the Mac:
```bash
xcrun notarytool store-credentials "tutor1on1-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

Recommended release flow:
1. In Xcode, set the Runner Release signing certificate to `Developer ID Application` and keep Hardened Runtime enabled.
2. Archive/export the signed `Tutor1on1.app` from Xcode for outside-App-Store distribution.
3. Package, notarize, staple, and validate:
```bash
MACOS_NOTARY_KEYCHAIN_PROFILE=tutor1on1-notary \
  bash scripts/notarize_macos_release.sh --app "/path/to/Tutor1on1.app"
```

Optional flag:
- `--skip-notarize` (package and signature-verify only; not for public release)

Default safeguards:
- Fails if the expected `Tutor1on1` app binary is missing.
- Verifies the app signature before notarization.
- Prints detected binary architectures with `lipo -archs`.
- Staples the accepted ticket and validates Gatekeeper with `spctl`.

### Auth API smoke test
```powershell
powershell -ExecutionPolicy Bypass -File scripts/test_auth.ps1
powershell -ExecutionPolicy Bypass -File scripts/test_auth.ps1 -BaseUrl "https://api.tutor1on1.org"
```
Optional env inputs:
- `FT_REMOTE_BASE_URL`
- `FT_RECOVERY_TOKEN` (needed when server does not echo recovery token)

### Teacher/Student enrollment+bundle smoke flow
```powershell
powershell -ExecutionPolicy Bypass -File scripts/smoke_teacher_student_flow.ps1
powershell -ExecutionPolicy Bypass -File scripts/smoke_teacher_student_flow.ps1 -BaseUrl "https://api.tutor1on1.org"
```
What it validates:
- teacher register -> create course -> ensure bundle -> upload -> publish
- student register -> request enrollment
- teacher approve request
- student list enrollments -> download latest bundle
- local ZIP import-readiness checks (`contents/context` + lecture files)
Optional flags:
- `-KeepArtifacts` (preserve temp bundle/download folder for debugging)
Optional env inputs for moderation-enabled servers:
- `FT_SMOKE_ADMIN_USERNAME`
- `FT_SMOKE_ADMIN_PASSWORD`
When teacher registration or course upload requires admin approval, the smoke script uses those admin credentials to approve the pending teacher-registration request and pending course-upload request before continuing.

### Decrypt LLM JSONL metadata for a known user
```powershell
$env:LOG_USER_ID='6'
$env:LOG_ROLE='student'
$env:LOG_PASSWORD='1234'
$env:LOG_SESSION_ID='71'
$env:LOG_KP_KEY='4.1.2.2'
dart run tool/decrypt_llm_logs.dart
```
Notes:
- Raw JSONL is at `C:\family_teacher\logs\llm_logs.jsonl`.
- Determine `LOG_USER_ID` and `LOG_ROLE` from raw JSONL `owner_user_id` / `owner_role` before decrypting.
- `tool/decrypt_llm_logs.dart` decrypts JSONL metadata fields such as prompt name, status, retry reason, and parse error for one `(session_id, kp_key)` pair.
- JSONL does not contain rendered prompt / full response bodies; inspect the local `llm_calls` DB table when available for those.

### Remote upload/storage preflight
```powershell
powershell -ExecutionPolicy Bypass -File scripts/preflight_remote_upload_and_storage.ps1
powershell -ExecutionPolicy Bypass -File scripts/preflight_remote_upload_and_storage.ps1 `
  -RemoteHost "43.99.59.107" `
  -RemoteUser "ecs-user" `
  -KeyPath "C:\Users\kl\.ssh\id_rsa"
```
Optional env inputs:
- `FT_REMOTE_HOST`
- `FT_REMOTE_USER`
- `FT_REMOTE_KEY_PATH`

### Canonical remote SSH executor
```powershell
powershell -ExecutionPolicy Bypass -File scripts/remote_exec.ps1 -- "hostname"
powershell -ExecutionPolicy Bypass -File scripts/remote_exec.ps1 -Tty
```
Defaults:
- `RemoteHost`: `43.99.59.107`
- `RemoteUser`: `ecs-user`
- `KeyPath`: `C:\Users\kl\.ssh\id_rsa`
- SSH options: key-only auth with `IdentitiesOnly=yes`

### Legacy summary migration
```powershell
powershell -ExecutionPolicy Bypass -File scripts/migrate_legacy_summary_results.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File scripts/migrate_legacy_summary_results.ps1
```
What it does:
- migrates legacy local SQLite summary rows that still encode `PASS_EASY|PASS_MEDIUM|PASS_HARD`
- updates local `chat_sessions` / `progress_entries` into `lit=true` plus passed-counts
- updates server `progress_sync` mirror rows for the same legacy summary text pattern

### Skill tree parser check
```powershell
dart run tool/parse_check.dart
```

### JWT secret rotation prep (PowerShell)
```powershell
$bytes = New-Object byte[] 48
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$newJwtSecret = [Convert]::ToBase64String($bytes)
$newJwtSecret
```
Operational notes:
- Set `JWT_SECRET` to the newly generated value.
- Keep the previous key in `JWT_PREVIOUS_SECRETS` (comma-separated) during rollout.
- In production, set `APP_ENV=production` and keep `RECOVERY_TOKEN_ECHO=false`.
- If tokens were exposed, revoke all active refresh tokens in DB so users re-authenticate:
```sql
UPDATE refresh_tokens
SET revoked_at = NOW()
WHERE revoked_at IS NULL;
```

### Backup restore drill
Runbook: `BACKUP_DRILL.md`
- Execute restore drill monthly and after schema changes.
- Validate restored DB with both smoke scripts:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/test_auth.ps1 -BaseUrl "https://<restore-host>"
powershell -ExecutionPolicy Bypass -File scripts/smoke_teacher_student_flow.ps1 -BaseUrl "https://<restore-host>"
```

## Remote API (Go) commands
```powershell
cd remote
go test ./...
go run ./cmd/server
go build -o family-teacher-api ./cmd/server
```

### One-time artifact cutover migration
```powershell
cd remote
go run ./cmd/artifact_cutover -student albert=1234 -student dennis=1234
go run ./cmd/artifact_cutover -student albert=1234 -student dennis=1234 -drop-legacy -confirm-hard-cutover
```
Operational notes:
- `-student` may be repeated, but the provided username set must exactly match the distinct legacy student usernames present in `session_text_sync` / `progress_sync` or the cutover fails hard.
- Use `-drop-legacy -confirm-hard-cutover` only after backup verification and artifact-manifest validation succeed.

## SQLC generation
```powershell
cd remote
sqlc generate
```

## Remote deploy quick sequence (Linux host)
```bash
/usr/local/go/bin/go build -o /opt/family_teacher_remote/bin/family-teacher-api /opt/family_teacher_remote/remote/cmd/server
/usr/bin/systemctl restart family-teacher-api.service
curl https://api.tutor1on1.org/health
```

## Test-case creation shortcuts
- Add Dart unit tests under `test/` and run target file first, then full `flutter test`.
- Add API regression tests under `remote/` and run `go test ./...`.
- For bug fixes, script the repro path first, then validate fixed path and one adjacent path.
