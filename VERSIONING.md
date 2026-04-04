# Public Versioning

This public client snapshot uses a simple release scheme:

- Git tags and GitHub Releases are derived from `pubspec.yaml` and use `vMAJOR.MINOR` or `vMAJOR.MINOR.PATCH`
- The app version in `pubspec.yaml` uses semantic versioning such as `1.0.5`
- The website download links must point at the same GitHub Release tag as the published assets
- GitHub Release asset names stay stable:
  - `Tutor1on1.apk`
  - `Tutor1on1.zip`
  - `SHA256SUMS.txt`

## Current Public Release

- Git tag: `v1.0.5`
- App version: `1.0.5`

## Release Checklist

1. Every shipped app update must increment the single `pubspec.yaml` version line before build/publish.
2. Treat `pubspec.yaml` as the only version source. Derive Android `versionCode`, website metadata, and GitHub release tags from it instead of maintaining a separate build number.
3. Build release assets with `public_release/package_github_release.ps1`, or publish them directly with `public_release/publish_github_release.ps1`. If no tag is passed, those scripts derive `vMAJOR.MINOR.PATCH` from `pubspec.yaml`.
4. Ensure the GitHub Release for the same tag contains `Tutor1on1.apk`, `Tutor1on1.zip`, and `SHA256SUMS.txt`.
5. Publish the static `web/` directory after the GitHub Release assets are live.
