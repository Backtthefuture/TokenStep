#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="TokenStep"
PRODUCT_NAME="TokenStepSwift"
SWIFT_DIR="$ROOT_DIR/TokenStepSwift"
APP_BUNDLE="$SWIFT_DIR/dist/$APP_NAME.app"
RELEASE_DIR="$ROOT_DIR/release"
VERSION="${TOKENSTEP_VERSION:-0.1.26}"
IDENTITY="${CODE_SIGN_IDENTITY:-}"
NOTARIZE=false

usage() {
  cat <<'USAGE'
Usage:
  TOKENSTEP_VERSION=0.1.26 CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./script/package_release.sh [--notarize]

Notarization credentials, choose one:
  TOKENSTEP_NOTARY_PROFILE="notarytool-profile"
  or
  APPLE_ID="you@example.com" APPLE_TEAM_ID="TEAMID" APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"

Outputs:
  release/TokenStep-<version>.zip
  release/TokenStep-<version>.dmg
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --notarize)
      NOTARIZE=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$IDENTITY" ]]; then
  echo "CODE_SIGN_IDENTITY is required for public distribution." >&2
  echo "Run: security find-identity -p codesigning -v" >&2
  exit 2
fi

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

echo "Building $APP_NAME $VERSION..."
TOKENSTEP_VERSION="$VERSION" "$ROOT_DIR/script/build_swiftui_and_run.sh" --no-launch

echo "Signing app with Developer ID..."
find "$APP_BUNDLE" \( -name ".DS_Store" -o -name "*.nssyncsc" \) -delete
if [[ -f "$APP_BUNDLE/Contents/Helpers/TokenStepHelper" ]]; then
  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP_BUNDLE/Contents/Helpers/TokenStepHelper"
fi
codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.zip"
DMG_STAGING="$RELEASE_DIR/dmg-staging"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"

echo "Creating zip..."
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

submit_for_notarization() {
  local artifact="$1"

  if [[ -n "${TOKENSTEP_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$artifact" --keychain-profile "$TOKENSTEP_NOTARY_PROFILE" --wait
    return
  fi

  if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    xcrun notarytool submit "$artifact" \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_PASSWORD" \
      --wait
    return
  fi

  echo "Notarization requested, but no credentials were provided." >&2
  echo "Set TOKENSTEP_NOTARY_PROFILE or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD." >&2
  exit 2
}

if [[ "$NOTARIZE" == true ]]; then
  echo "Submitting zip for notarization..."
  submit_for_notarization "$ZIP_PATH"
  echo "Stapling app ticket..."
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
fi

echo "Creating dmg..."
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$NOTARIZE" == true ]]; then
  echo "Submitting dmg for notarization..."
  submit_for_notarization "$DMG_PATH"
  echo "Stapling dmg ticket..."
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

echo "Validating signature..."
spctl -a -vv "$APP_BUNDLE" || true
spctl -a -vv -t install "$DMG_PATH" || true

echo
echo "Release artifacts:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
