# Windows Release Publish Skill

## Purpose
Build the Windows app, package it as a versioned ZIP such as `Tutor1on1-1.0.8.zip`, upload it to the remote server, remove old versioned ZIP artifacts, and verify the public download link.

## Use when
- A new desktop release needs to be published for download.
- The canonical download file should remain stable as `Tutor1on1.zip`.

## Script
- `scripts/publish_windows_release.ps1`

## Default behavior
1. Run prompt-asset gate: `flutter test test/prompt_assets_integrity_test.dart`.
2. Run `flutter build windows --release` so the local `build/windows/x64/runner/Release` tree is refreshed before packaging/upload.
3. Package `build/windows/x64/runner/Release` into `build/Tutor1on1-<version>.zip`.
4. Validate ZIP artifact entries and prompt asset decoding using `scripts/validate_windows_release_zip.ps1`.
5. Upload ZIP to remote `/tmp/Tutor1on1-<version>.zip`.
6. Install candidate ZIP to `/var/lib/family_teacher_remote/public/Tutor1on1_candidate.zip`.
7. Verify candidate SHA-256 and candidate URL (`/downloads/Tutor1on1_candidate.zip`) before promotion.
8. Promote candidate to `/var/lib/family_teacher_remote/public/Tutor1on1-<version>.zip`.
9. Delete the stale Windows candidate ZIP, stale unversioned `Tutor1on1.zip`, older versioned `Tutor1on1-*.zip`, and legacy `family_teacher*.zip` files after promotion.
10. Verify published SHA-256 and URL (`https://api.tutor1on1.org/downloads/Tutor1on1-<version>.zip`).

## Run
```powershell
powershell -ExecutionPolicy Bypass -File skills/windows_release_publish/scripts/publish_windows_release.ps1
```

## Useful options
```powershell
# Reuse existing local build output only if `build/windows/x64/runner/Release`
# was already rebuilt for the exact commit you are publishing
powershell -ExecutionPolicy Bypass -File skills/windows_release_publish/scripts/publish_windows_release.ps1 -SkipBuild

# Build + zip only (no upload)
powershell -ExecutionPolicy Bypass -File skills/windows_release_publish/scripts/publish_windows_release.ps1 -SkipUpload

# Skip prompt-asset gate (only for emergency diagnostics)
powershell -ExecutionPolicy Bypass -File skills/windows_release_publish/scripts/publish_windows_release.ps1 -SkipPromptAssetTests

# Skip ZIP artifact validation (only for emergency diagnostics)
powershell -ExecutionPolicy Bypass -File skills/windows_release_publish/scripts/publish_windows_release.ps1 -SkipZipValidation
```

## Required environment/tooling
- Local:
  - Flutter SDK in `PATH`
  - `ssh`, `scp`, `curl.exe`, `tar` available
- Remote:
  - SSH access: `ecs-user@43.99.59.107`
  - Key: `C:\Users\kl\.ssh\id_rsa`
  - `sudo` permission for install/delete under `/var/lib/family_teacher_remote/public`

## Notes
- The script is intentionally fail-fast after a short retry window. It throws on any mismatch or candidate/canonical URL check that still is not `200 OK` after the retries.
- It uses absolute command paths on remote host because remote `PATH` may be empty.
- Candidate-first promotion avoids publishing a broken canonical ZIP when upload content is malformed.
- A Windows server publish is incomplete if the local `build/windows/x64/runner/Release` output is stale. The local Release tree must match the uploaded ZIP for the same commit.
