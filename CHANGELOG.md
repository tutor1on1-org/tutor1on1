# Changelog

## Unreleased - 2026-08-03

- Restored OpenAI Codex (ChatGPT OAuth) to the Chrome client and routed Codex model/tutor traffic through a fixed authenticated API relay that does not persist or log OAuth credentials or prompt/response content.
- Raised the bounded course-bundle entry limit from 10,000 to 100,000 on both client and server so valid production courses remain compatible while ZIP resource limits stay enforced.
- Migrated the public client to Chrome/WebGUI only and removed the Windows and Android source, dependencies, and release targets.
- Added durable browser database/file/audio persistence, continuous cross-tab-safe sync, account-bound auth guards, and bounded ZIP handling.
- Replaced native artifact publishing with an atomic Flutter Web `/app/` release pipeline with preflight validation, full-tree checksums, rollback, a revalidated launcher, and deterministic gzip-compressed immutable release assets.
- Added fail-closed API CORS and browser security configuration; production server/nginx deployment is required before web promotion, with no database schema migration.

## v1.0.59

- Pass confirmation no longer waits for the streaming connection to close after the API has emitted `response.completed`

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
