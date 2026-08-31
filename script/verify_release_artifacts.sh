#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 /path/to/TokenStep.dmg /path/to/TokenStep.zip EXPECTED_VERSION" >&2
  exit 2
fi

DMG_PATH="$1"
ZIP_PATH="$2"
EXPECTED_VERSION="$3"
EXPECTED_TEAM_ID="${TOKENSTEP_EXPECTED_TEAM_ID:-${APPLE_TEAM_ID:-}}"

for artifact in "$DMG_PATH" "$ZIP_PATH"; do
  if [[ ! -f "$artifact" ]]; then
    echo "Release artifact not found: $artifact" >&2
    exit 2
  fi
done

for tool in \
  /usr/bin/codesign \
  /usr/bin/ditto \
  /usr/bin/hdiutil \
  /usr/bin/shasum \
  /usr/sbin/spctl \
  /usr/bin/syspolicy_check \
  /usr/bin/xcrun \
  /usr/libexec/PlistBuddy; do
  if [[ ! -x "$tool" ]]; then
    echo "Required release verification tool is unavailable: $tool" >&2
    exit 2
  fi
done

VERIFY_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/tokenstep-release-verify.XXXXXX")"
DMG_MOUNT="$VERIFY_ROOT/dmg"
ZIP_EXTRACT="$VERIFY_ROOT/zip"
DMG_ATTACHED=false

cleanup() {
  if [[ "$DMG_ATTACHED" == true ]]; then
    /usr/bin/hdiutil detach "$DMG_MOUNT" -force -quiet >/dev/null 2>&1 || true
  fi
  if [[ -n "${VERIFY_ROOT:-}" && "$VERIFY_ROOT" == *tokenstep-release-verify.* ]]; then
    /bin/rm -rf "$VERIFY_ROOT"
  fi
}
trap cleanup EXIT

/bin/mkdir -p "$DMG_MOUNT" "$ZIP_EXTRACT"

validate_app() {
  local app_path="$1"
  local label="$2"
  local info_plist="$app_path/Contents/Info.plist"
  local actual_version
  local actual_team_id=""

  if [[ ! -d "$app_path" || ! -f "$info_plist" ]]; then
    echo "$label does not contain TokenStep.app with an Info.plist." >&2
    exit 1
  fi

  actual_version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$info_plist")"
  if [[ "$actual_version" != "$EXPECTED_VERSION" ]]; then
    echo "$label version mismatch: expected $EXPECTED_VERSION, got $actual_version" >&2
    exit 1
  fi

  /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"
  /usr/bin/xcrun stapler validate "$app_path"
  /usr/bin/syspolicy_check distribution "$app_path"
  /usr/sbin/spctl --assess --type execute --verbose=2 "$app_path"

  if [[ -n "$EXPECTED_TEAM_ID" ]]; then
    actual_team_id="$(/usr/bin/codesign -dv --verbose=4 "$app_path" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p' | /usr/bin/head -n 1)"
    if [[ "$actual_team_id" != "$EXPECTED_TEAM_ID" ]]; then
      echo "$label TeamIdentifier mismatch: expected $EXPECTED_TEAM_ID, got ${actual_team_id:-missing}" >&2
      exit 1
    fi
  fi

  echo "Verified $label: version=$actual_version team=${actual_team_id:-not-enforced}"
}

echo "Verifying DMG signature and notarization ticket..."
/usr/bin/codesign --verify --verbose=2 "$DMG_PATH"
/usr/bin/xcrun stapler validate "$DMG_PATH"

echo "Verifying the app mounted from the DMG..."
/usr/bin/hdiutil attach -readonly -nobrowse -quiet -mountpoint "$DMG_MOUNT" "$DMG_PATH"
DMG_ATTACHED=true
validate_app "$DMG_MOUNT/TokenStep.app" "DMG app"
/usr/bin/hdiutil detach "$DMG_MOUNT" -force -quiet
DMG_ATTACHED=false

echo "Verifying the app extracted from the ZIP..."
/usr/bin/ditto -x -k "$ZIP_PATH" "$ZIP_EXTRACT"
validate_app "$ZIP_EXTRACT/TokenStep.app" "ZIP app"

echo "Release artifact SHA-256 values:"
/usr/bin/shasum -a 256 "$DMG_PATH" "$ZIP_PATH"
echo "Verified signed, notarized, stapled TokenStep $EXPECTED_VERSION release artifacts."
