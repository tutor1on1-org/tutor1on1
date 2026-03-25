# Public Versioning

This public client snapshot uses a simple release scheme:

- Git tags and GitHub Releases use `vMAJOR.MINOR` or `vMAJOR.MINOR.PATCH`
- The app build version in `pubspec.yaml` uses semantic versioning such as `1.0.0+1`
- The website download links must point at the same GitHub Release tag as the published assets
- GitHub Release asset names stay stable:
  - `Tutor1on1.apk`
  - `Tutor1on1.zip`
  - `SHA256SUMS.txt`

## First Public Release

- Git tag: `v1.0`
- App version: `1.0.0+1`

## Release Checklist

1. Update `pubspec.yaml` app version if the release content changed.
2. Update the release tag in `web/site.js`, and update the GitHub repo slug there too if the public repository path is not `tutor1on1-org/tutor1on1`.
3. Build release assets with `public_release/package_github_release.ps1`.
4. Create the GitHub Release for the same tag and upload `Tutor1on1.apk`, `Tutor1on1.zip`, and `SHA256SUMS.txt`.
5. Publish the static `web/` directory after the GitHub Release assets are live.
