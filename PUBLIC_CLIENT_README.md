# Tutor1on1 Client

This repository is the client-only open-source snapshot of Tutor1on1. It exists so users can inspect the shipped Flutter application, review its network behavior, and verify that the published client does not include bundled secrets or an offline admin backdoor.

## Scope

Included in this snapshot:

- Flutter application code under `lib/`
- Platform launchers for Android, iOS, macOS, Linux, and Windows
- Client tests under `test/` and `integration_test/`
- Bundled assets under `assets/`
- Static English download website under `web/`
- Public GitHub Release packaging helpers under `public_release/`
- Tracked client-side support packages under `packages/` and `third_party/`

Intentionally excluded from this snapshot:

- Backend/server source under `remote/`
- Private release, deploy, and internal maintenance scripts
- Local `.env` files, logs, databases, build outputs, and other untracked files
- Private runbooks and host-specific operational docs

## What This Client Does

- Teacher workflows: course import/reload, marketplace upload, enrollment review, and artifact publishing
- Student workflows: login, catalog browsing, enrollment request, bundle download, guided tutor sessions
- Artifact-manifest sync for course and bundle updates
- Optional LLM/TTS/STT integrations with user-supplied API keys

## Transparency Notes

This source tree does not ship:

- Hardcoded Telegram, SMTP, or cloud API credentials
- A built-in offline admin password
- A local admin fallback login path when remote authentication fails

The client stores data in two places:

- Local app data, including the SQLite database and logs
- OS-backed secure storage for auth tokens, per-provider API keys, and local encryption key material

## Network Behavior Visible In Source

Official app backend:

- Default backend base URL: `https://api.tutor1on1.org`
- This can be overridden at build time with `--dart-define=AUTH_BASE_URL=...`

Optional user-configured model providers:

- `https://api.openai.com/v1`
- `https://openrouter.ai/api/v1`
- `https://api.anthropic.com/v1`
- `https://generativelanguage.googleapis.com/v1beta/openai`
- `https://api.x.ai/v1`
- `https://api.siliconflow.cn/v1`
- `https://api.deepseek.com/v1`

Speech features:

- TTS uses OpenAI-compatible APIs when enabled
- STT supports OpenAI-compatible APIs and SiliconFlow-compatible APIs

Permissions visible in tracked client code:

- Android: `android.permission.INTERNET`, `android.permission.RECORD_AUDIO`
- iOS/macOS: microphone usage strings for speech-to-text

## Build

Run from repository root:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build windows --release
flutter build macos --release
```

Override the default backend only if you intentionally want to point the client at a different server:

```powershell
flutter build windows --release --dart-define=AUTH_BASE_URL=https://example.com
```

Do not enable insecure TLS outside local debugging:

```powershell
flutter run --dart-define=AUTH_ALLOW_INSECURE_TLS=true
```

## GitHub Releases

The public release flow is versioned around Git tags and GitHub Release assets.

- Current public release tag: `v1.0.6`
- App version in `pubspec.yaml`: `1.0.6`
- Standard asset names:
  - `Tutor1on1.apk`
  - `Tutor1on1.zip`
  - `SHA256SUMS.txt`

Build release assets from this snapshot with:

```powershell
powershell -ExecutionPolicy Bypass -File public_release/package_github_release.ps1 -ReleaseTag v1.0.6
```

Or publish the GitHub Release assets directly:

```powershell
powershell -ExecutionPolicy Bypass -File public_release/publish_github_release.ps1 -ReleaseTag v1.0.6
```

That script builds Android and Windows release artifacts and writes them to:

```text
public_release/dist/v1.0.6/
```

The static website under `web/` is prepared to point download buttons at the versioned GitHub Release assets for the configured tag.

The default website config currently targets:

- GitHub repo slug: `tutor1on1-org/tutor1on1`
- GitHub Release tag: `v1.0.6`

## Trust And Verification

Open source alone does not prove that a published binary matches this source tree. A trustworthy release should publish:

- The exact source tag or commit
- A `SHA-256` hash for each artifact
- A build command or CI workflow that reproduces the artifact from that tag

See also:

- `VERSIONING.md`
- `CHANGELOG.md`

## Status Of The Server

This snapshot does not include the production server implementation. The official client can talk to the official Tutor1on1 service, but self-hosting the full backend is out of scope for this public snapshot.

## License

Apache-2.0. See `LICENSE`.
