#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="TokenStep"
PRODUCT_NAME="TokenStepSwift"
SWIFT_DIR="$ROOT_DIR/TokenStepSwift"
BUILT_APP_BUNDLE="$SWIFT_DIR/dist/$APP_NAME.app"
APP_BUNDLE="$BUILT_APP_BUNDLE"
RELEASE_DIR="$ROOT_DIR/release"
VERSION="${TOKENSTEP_VERSION:-0.1.37}"
IDENTITY="${CODE_SIGN_IDENTITY:-}"
NOTARIZE=false

usage() {
  cat <<'USAGE'
Usage:
  TOKENSTEP_VERSION=0.1.37 CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./script/package_release.sh [--notarize]

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

PACKAGE_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tokenstep-release.XXXXXX")"
trap 'rm -rf "$PACKAGE_WORK_DIR"' EXIT
APP_BUNDLE="$PACKAGE_WORK_DIR/$APP_NAME.app"
ditto "$BUILT_APP_BUNDLE" "$APP_BUNDLE"

clean_bundle_metadata() {
  find "$APP_BUNDLE" \( -name ".DS_Store" -o -name "*.nssyncsc" \) -delete
}

echo "Signing app with Developer ID..."
clean_bundle_metadata
if [[ -f "$APP_BUNDLE/Contents/Helpers/TokenStepHelper" ]]; then
  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP_BUNDLE/Contents/Helpers/TokenStepHelper"
fi
clean_bundle_metadata
codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.zip"
DMG_STAGING="$PACKAGE_WORK_DIR/dmg-staging"
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
  echo "Recreating zip with stapled app..."
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
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
echo "Signing dmg with Developer ID..."
codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

if [[ "$NOTARIZE" == true ]]; then
  echo "Submitting dmg for notarization..."
  submit_for_notarization "$DMG_PATH"
  echo "Stapling dmg ticket..."
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

echo "Validating signature..."
spctl -a -vv "$APP_BUNDLE"
spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"
if [[ "$NOTARIZE" == true ]]; then
  ZIP_VALIDATE_DIR="$RELEASE_DIR/zip-validate"
  rm -rf "$ZIP_VALIDATE_DIR"
  mkdir -p "$ZIP_VALIDATE_DIR"
  ditto -x -k "$ZIP_PATH" "$ZIP_VALIDATE_DIR"
  xcrun stapler validate "$ZIP_VALIDATE_DIR/$APP_NAME.app"
  rm -rf "$ZIP_VALIDATE_DIR"
fi

echo
echo "Release artifacts:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
