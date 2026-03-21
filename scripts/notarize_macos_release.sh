#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
app_path="$repo_root/build/macos/Build/Products/Release/Tutor1on1.app"
output_zip="$repo_root/build/macos/Tutor1on1-macos-universal.zip"
keychain_profile="${MACOS_NOTARY_KEYCHAIN_PROFILE:-}"
skip_notarize=0

usage() {
  cat <<'EOF'
Usage:
  bash scripts/notarize_macos_release.sh [--app /path/to/Tutor1on1.app] [--output-zip /path/to/Tutor1on1-macos-universal.zip] [--keychain-profile profile] [--skip-notarize]

Behavior:
  - Verifies the app bundle signature and reported architectures.
  - Creates a ZIP with ditto for website delivery compatibility.
  - Notarizes and staples the app unless --skip-notarize is provided.
  - Rebuilds the ZIP after stapling so the final archive contains the stapled app.

Environment:
  MACOS_NOTARY_KEYCHAIN_PROFILE  Keychain profile created with xcrun notarytool store-credentials
EOF
}

while (($# > 0)); do
  case "$1" in
    --app)
      app_path="$2"
      shift 2
      ;;
    --output-zip)
      output_zip="$2"
      shift 2
      ;;
    --keychain-profile)
      keychain_profile="$2"
      shift 2
      ;;
    --skip-notarize)
      skip_notarize=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$app_path" ]]; then
  echo "App bundle not found: $app_path" >&2
  exit 1
fi

binary_path="$app_path/Contents/MacOS/Tutor1on1"
if [[ ! -f "$binary_path" ]]; then
  echo "App binary not found: $binary_path" >&2
  exit 1
fi

mkdir -p "$(dirname "$output_zip")"

echo "Architectures: $(/usr/bin/lipo -archs "$binary_path")"
echo "Verifying code signature..."
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"

echo "Creating ZIP: $output_zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$output_zip"

if [[ "$skip_notarize" -eq 1 ]]; then
  echo "Skipped notarization by request."
  exit 0
fi

if [[ -z "$keychain_profile" ]]; then
  echo "MACOS_NOTARY_KEYCHAIN_PROFILE is required unless --skip-notarize is used." >&2
  echo "Create it once with xcrun notarytool store-credentials and retry." >&2
  exit 1
fi

echo "Submitting ZIP for notarization..."
/usr/bin/xcrun notarytool submit "$output_zip" --keychain-profile "$keychain_profile" --wait

echo "Stapling notarization ticket..."
/usr/bin/xcrun stapler staple "$app_path"

echo "Validating Gatekeeper acceptance..."
/usr/sbin/spctl -a -vv "$app_path"

echo "Repacking stapled app..."
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$output_zip"

echo "Done: $output_zip"
