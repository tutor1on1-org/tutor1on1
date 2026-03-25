# Changelog

## v1.0.1

- Windows ZIP now ships `tutor1on1.exe` instead of `family_teacher.exe`
- Windows release packaging now clears stale `build/windows` output before rebuilding so legacy executables do not leak into published ZIPs
- Public release flow now publishes GitHub Release assets in addition to the server APK/ZIP and website sync
- Validation now fails fast on non-zero analyze/test exits instead of reporting a false green release precheck

## v1.0

- First public client-only open-source snapshot
- Apache-2.0 license
- Local offline admin bootstrap removed from the client
- Public README and snapshot export flow added
- Static website prepared to point at versioned GitHub Release assets
