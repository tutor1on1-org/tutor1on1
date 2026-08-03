# Public Versioning

Tutor1on1 ships one Chrome web application:

- `pubspec.yaml` is the only version source.
- Git tags use `vMAJOR.MINOR.PATCH`.
- Each release has a deterministic immutable id `vMAJOR.MINOR.PATCH-<commit>`; random ids are reserved for temporary publish transactions.
- The public entry point is `https://www.tutor1on1.org/app/`.
- The entry page revalidates, while runtime files use gzip-compressed one-year immutable `/app/releases/<release-id>/` URLs so ordinary refreshes download them only after promotion of a new release.

## Current Public Release

- Git tag: `v1.0.61`
- App version: `1.0.61`

## Release Checklist

1. Run `scripts/release_public.ps1` with no arguments for the canonical release.
2. Let the wrapper derive the tag from `pubspec.yaml`, validate once, and build one service-worker-free Flutter Web candidate.
3. Require its artifact hash, 6 MiB Chrome core gzip budget, headless-Chrome boot, and production API CORS compatibility before publishing private or public refs.
4. Promote only that exact candidate and verify the live launcher, immutable compressed runtime assets, service-worker absence, and the exact `release.json` id.
5. On failure, restore the prior symlink; later rollbacks use `scripts/publish_web_release.ps1 -RollbackTo <release-id>`.
