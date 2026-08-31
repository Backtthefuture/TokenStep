#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="TokenStep"
SWIFT_DIR="$ROOT_DIR/TokenStepSwift"
BUILT_APP_BUNDLE="$SWIFT_DIR/dist/$APP_NAME.app"
RELEASE_DIR="$ROOT_DIR/release"
VERSION="${TOKENSTEP_VERSION:-}"
IDENTITY="${CODE_SIGN_IDENTITY:-}"
NOTES_FILE="$ROOT_DIR/docs/RELEASE_NOTES_${VERSION}.md"
EXPECTED_TEAM_ID="${APPLE_TEAM_ID:-}"
NOTARY_ARGS=()

usage() {
  cat <<'USAGE'
Usage:
  TOKENSTEP_VERSION=0.2.13 \
  CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  TOKENSTEP_NOTARY_PROFILE="notarytool-profile" \
  ./script/package_release.sh [--notarize]

Public release artifacts are always submitted to Apple, stapled, and verified.
The --notarize flag is retained for compatibility but is no longer optional behavior.

Notarization credentials, choose one:
  TOKENSTEP_NOTARY_PROFILE="notarytool-profile"
  or
  APPLE_ID="you@example.com" APPLE_TEAM_ID="TEAMID" APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"

Outputs:
  release/TokenStep-<version>.zip
  release/TokenStep-<version>.dmg
  release/TokenStep-<version>-SHA256SUMS.txt
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --notarize)
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

if [[ -z "$VERSION" ]]; then
  echo "TOKENSTEP_VERSION is required; release versions must be explicit." >&2
  exit 2
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid TOKENSTEP_VERSION: $VERSION" >&2
  exit 2
fi
if [[ -z "$IDENTITY" ]]; then
  echo "CODE_SIGN_IDENTITY is required for public distribution." >&2
  echo "Run: security find-identity -p codesigning -v" >&2
  exit 2
fi
if [[ ! -f "$NOTES_FILE" ]]; then
  echo "Release notes are required: $NOTES_FILE" >&2
  exit 2
fi
if [[ ! -x /usr/bin/syspolicy_check ]]; then
  echo "syspolicy_check is required for public distribution verification." >&2
  exit 2
fi

if [[ -n "${TOKENSTEP_NOTARY_PROFILE:-}" ]]; then
  NOTARY_ARGS=(--keychain-profile "$TOKENSTEP_NOTARY_PROFILE")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  NOTARY_ARGS=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
else
  echo "Apple notarization credentials are mandatory for every release artifact." >&2
  echo "Set TOKENSTEP_NOTARY_PROFILE or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD." >&2
  exit 2
fi

if ! /usr/bin/security find-identity -p codesigning -v | /usr/bin/grep -Fq "\"$IDENTITY\""; then
  echo "The requested Developer ID identity is not available: $IDENTITY" >&2
  exit 2
fi

if [[ -z "$EXPECTED_TEAM_ID" && "$IDENTITY" =~ \(([A-Z0-9]{10})\)$ ]]; then
  EXPECTED_TEAM_ID="${BASH_REMATCH[1]}"
fi

echo "Validating Apple notarization credentials..."
/usr/bin/xcrun notarytool history "${NOTARY_ARGS[@]}" >/dev/null

/bin/rm -rf "$RELEASE_DIR"
/bin/mkdir -p "$RELEASE_DIR"

echo "Building $APP_NAME $VERSION..."
TOKENSTEP_VERSION="$VERSION" "$ROOT_DIR/script/build_swiftui_and_run.sh" --no-launch

PACKAGE_WORK_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/tokenstep-release.XXXXXX")"
trap '/bin/rm -rf "$PACKAGE_WORK_DIR"' EXIT
APP_BUNDLE="$PACKAGE_WORK_DIR/$APP_NAME.app"
/usr/bin/ditto "$BUILT_APP_BUNDLE" "$APP_BUNDLE"

clean_bundle_metadata() {
  /usr/bin/find "$APP_BUNDLE" \( -name ".DS_Store" -o -name "*.nssyncsc" \) -delete
}

echo "Signing app with Developer ID..."
clean_bundle_metadata
if [[ -f "$APP_BUNDLE/Contents/Helpers/TokenStepHelper" ]]; then
  /usr/bin/codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP_BUNDLE/Contents/Helpers/TokenStepHelper"
fi
clean_bundle_metadata
/usr/bin/codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.zip"
DMG_STAGING="$PACKAGE_WORK_DIR/dmg-staging"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"

echo "Creating zip for Apple notarization..."
/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

submit_for_notarization() {
  local artifact="$1"
  /usr/bin/xcrun notarytool submit "$artifact" "${NOTARY_ARGS[@]}" --wait
}

echo "Submitting zip for notarization..."
submit_for_notarization "$ZIP_PATH"
echo "Stapling app ticket..."
/usr/bin/xcrun stapler staple "$APP_BUNDLE"
/usr/bin/xcrun stapler validate "$APP_BUNDLE"
echo "Recreating zip with the stapled app..."
/bin/rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "Creating dmg..."
/bin/mkdir -p "$DMG_STAGING"
/usr/bin/ditto "$APP_BUNDLE" "$DMG_STAGING/$APP_NAME.app"
/bin/ln -s /Applications "$DMG_STAGING/Applications"

DMG_CREATED=false
for attempt in 1 2 3; do
  /bin/rm -f "$DMG_PATH"
  if /usr/bin/hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"; then
    DMG_CREATED=true
    break
  fi
  echo "DMG creation attempt $attempt failed; retrying..." >&2
  /bin/sleep $((attempt * 3))
done

if [[ "$DMG_CREATED" != true ]]; then
  echo "DMG creation failed after 3 attempts." >&2
  exit 1
fi

echo "Signing dmg with Developer ID..."
/usr/bin/codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
/usr/bin/codesign --verify --verbose=2 "$DMG_PATH"

echo "Submitting dmg for notarization..."
submit_for_notarization "$DMG_PATH"
echo "Stapling dmg ticket..."
/usr/bin/xcrun stapler staple "$DMG_PATH"
/usr/bin/xcrun stapler validate "$DMG_PATH"

echo "Running distribution and artifact verification..."
TOKENSTEP_EXPECTED_TEAM_ID="$EXPECTED_TEAM_ID" \
  "$ROOT_DIR/script/verify_release_artifacts.sh" "$DMG_PATH" "$ZIP_PATH" "$VERSION"

echo "Running the isolated automatic-update installer verification..."
"$ROOT_DIR/script/verify_update_installer.sh" \
  "$DMG_PATH" \
  "$VERSION" \
  "$APP_BUNDLE/Contents/Helpers/TokenStepHelper"

CHECKSUM_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-SHA256SUMS.txt"
(
  cd "$RELEASE_DIR"
  /usr/bin/shasum -a 256 \
    "$(/usr/bin/basename "$DMG_PATH")" \
    "$(/usr/bin/basename "$ZIP_PATH")" \
    > "$(/usr/bin/basename "$CHECKSUM_PATH")"
)

echo
echo "Verified public release artifacts:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
echo "  $CHECKSUM_PATH"
