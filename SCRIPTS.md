# SCRIPTS
Last updated: 2026-02-27

All commands are expected from repository root (`C:\family_teacher\app`) unless stated otherwise.

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
flutter run -d windows
flutter build windows --release
```
Required workflow gate: run release build before updating `DONEs.md` after code changes.

## Utility scripts
### Auth API smoke test
```powershell
powershell -ExecutionPolicy Bypass -File scripts/test_auth.ps1
powershell -ExecutionPolicy Bypass -File scripts/test_auth.ps1 -BaseUrl "https://43.99.59.107"
```
Optional env inputs:
- `FT_REMOTE_BASE_URL`
- `FT_RECOVERY_TOKEN` (needed when server does not echo recovery token)

### Teacher/Student enrollment+bundle smoke flow
```powershell
powershell -ExecutionPolicy Bypass -File scripts/smoke_teacher_student_flow.ps1
powershell -ExecutionPolicy Bypass -File scripts/smoke_teacher_student_flow.ps1 -BaseUrl "https://43.99.59.107"
```
What it validates:
- teacher register -> create course -> ensure bundle -> upload -> publish
- student register -> request enrollment
- teacher approve request
- student list enrollments -> download latest bundle
- local ZIP import-readiness checks (`contents/context` + lecture files)
Optional flags:
- `-KeepArtifacts` (preserve temp bundle/download folder for debugging)

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

## SQLC generation
```powershell
cd remote
sqlc generate
```

## Remote deploy quick sequence (Linux host)
```bash
/usr/local/go/bin/go build -o /opt/family_teacher_remote/bin/family-teacher-api /opt/family_teacher_remote/remote/cmd/server
/usr/bin/systemctl restart family-teacher-api.service
curl -k https://43.99.59.107/health
```

## Test-case creation shortcuts
- Add Dart unit tests under `test/` and run target file first, then full `flutter test`.
- Add API regression tests under `remote/` and run `go test ./...`.
- For bug fixes, script the repro path first, then validate fixed path and one adjacent path.
