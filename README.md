# Tutor1on1 Web Client

This repository is the client-only open-source snapshot of Tutor1on1, a Flutter Web application for Chrome. It lets users inspect the shipped client, network behavior, browser storage, and release inputs without exposing the private backend repository.

## Scope

Included:

- Flutter application code under `lib/`
- Browser bootstrap and pinned Drift assets under `web/`
- Localized marketing pages under `website/`
- Tests under `test/` and non-live `integration_test/` paths
- Bundled course and prompt assets under `assets/`

Excluded:

- Backend source under `remote/`
- Host-bound live diagnostics and account configuration
- Private deploy scripts, runbooks, secrets, logs, databases, and build outputs

## Runtime Model

- Chrome loads the app from `https://www.tutor1on1.org/app/`.
- Drift stores local data in browser-supported SQLite/WASM storage.
- Auth uses the official API at `https://api.tutor1on1.org` with bearer tokens.
- Course, session, progress, and mistake-book data synchronize with the server.
- Optional LLM, TTS, and STT integrations use the provider configuration selected by the user.
- For OpenAI Codex (ChatGPT OAuth), OpenAI authorization runs in Chrome, while fixed authenticated routes at `https://api.tutor1on1.org` transiently relay the OpenAI access token/account ID, model catalog, and tutor prompt/response traffic because the ChatGPT Codex backend does not accept direct browser CORS calls; the relay does not persist or log those credentials or content.

The client does not contain hardcoded service credentials, an offline admin password, or an authentication fallback.

## Build

```powershell
flutter pub get
powershell -ExecutionPolicy Bypass -File scripts/validate_web_shell.ps1
flutter analyze --no-pub
flutter test --no-pub
flutter build web --release --base-href /app/ --pwa-strategy=none --no-pub
```

Override the backend only for an intentional non-production build:

```powershell
flutter build web --release --base-href /app/ --pwa-strategy=none --dart-define=AUTH_BASE_URL=https://example.com
```

## Releases

- Current public release tag: `v1.0.65`
- App version in `pubspec.yaml`: `1.0.65`

The canonical private release wrapper validates the source, builds and boots one service-worker-free candidate, verifies production CORS, publishes source refs only after those gates pass, installs that exact attested candidate under an immutable versioned directory, and atomically promotes `/app/`; only the small launcher revalidates, while gzip-compressed runtime files use one-year immutable release URLs, and failed live verification restores the prior release.

Open the public app at `https://www.tutor1on1.org/app/`; every release is served from an immutable web candidate.

## Trust And Verification

A release should identify the exact source tag, commit, immutable deployment id, build command, and pinned `drift_worker.js` plus `sqlite3.wasm` hashes. See `VERSIONING.md` and `CHANGELOG.md`.

## License

Apache-2.0. See `LICENSE`.
