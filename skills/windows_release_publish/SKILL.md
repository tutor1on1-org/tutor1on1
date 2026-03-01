# Windows Release Publish Skill

## Purpose
Build the Windows app, package it as `family_teacher.zip`, upload it to the remote server, remove old versioned ZIP artifacts, and verify the public download link.

## Use when
- A new desktop release needs to be published for download.
- The canonical download file should remain stable as `family_teacher.zip`.

## Script
- `scripts/publish_windows_release.ps1`

## Default behavior
1. Run `flutter build windows --release`.
2. Package `build/windows/x64/runner/Release` into `build/family_teacher.zip`.
3. Upload ZIP to remote `/tmp/family_teacher.zip`.
4. Install to `/var/lib/family_teacher_remote/public/family_teacher.zip`.
5. Delete old versioned ZIP files that match `family_teacher*.zip` except `family_teacher.zip`.
6. Verify:
   - remote SHA-256 equals local SHA-256
   - `https://43.99.59.107/downloads/family_teacher.zip` returns `HTTP 200`.

## Run
```powershell
powershell -ExecutionPolicy Bypass -File skills/windows_release_publish/scripts/publish_windows_release.ps1
```

## Useful options
```powershell
# Reuse existing local build output (skip flutter build)
powershell -ExecutionPolicy Bypass -File skills/windows_release_publish/scripts/publish_windows_release.ps1 -SkipBuild

# Build + zip only (no upload)
powershell -ExecutionPolicy Bypass -File skills/windows_release_publish/scripts/publish_windows_release.ps1 -SkipUpload
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
- The script is intentionally fail-fast. It throws on any mismatch or non-200 link check.
- It uses absolute command paths on remote host because remote `PATH` may be empty.
