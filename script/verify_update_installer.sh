#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/release_retry.sh"

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 /path/to/TokenStep.dmg EXPECTED_VERSION /path/to/TokenStepHelper" >&2
  exit 2
fi

DMG_PATH="$1"
EXPECTED_VERSION="$2"
HELPER_SOURCE="$3"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH" >&2
  exit 2
fi
if [[ ! -x "$HELPER_SOURCE" ]]; then
  echo "Helper is not executable: $HELPER_SOURCE" >&2
  exit 2
fi

/usr/bin/codesign --verify --verbose=2 "$DMG_PATH"
retry_transient "stapler validate (dmg)" /usr/bin/xcrun stapler validate "$DMG_PATH"

VERIFY_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/tokenstep-update-verify.XXXXXX")"
VERIFY_DESTINATION="$VERIFY_ROOT/Applications/TokenStep.app"
VERIFY_HELPER="$VERIFY_ROOT/TokenStepHelper"
VERIFY_LOG="$VERIFY_ROOT/update-install.log"

cleanup() {
  if [[ -n "${VERIFY_ROOT:-}" && "$VERIFY_ROOT" == *tokenstep-update-verify.* ]]; then
    /bin/rm -rf "$VERIFY_ROOT"
  fi
}
trap cleanup EXIT

/bin/mkdir -p "$VERIFY_ROOT/Applications"
/bin/cp "$HELPER_SOURCE" "$VERIFY_HELPER"
/bin/chmod 755 "$VERIFY_HELPER"

retry_transient "update installer verification" \
  "$VERIFY_HELPER" install \
  --dmg "$DMG_PATH" \
  --version "$EXPECTED_VERSION" \
  --current-pid 0 \
  --require-verified 1 \
  --log "$VERIFY_LOG" \
  --helper-path "$VERIFY_HELPER" \
  --destination "$VERIFY_DESTINATION" \
  --skip-relaunch 1 \
  --skip-stop 1

INSTALLED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$VERIFY_DESTINATION/Contents/Info.plist")"
if [[ "$INSTALLED_VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "Installed version mismatch: expected $EXPECTED_VERSION, got $INSTALLED_VERSION" >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict "$VERIFY_DESTINATION"
retry_transient "stapler validate (installed app)" /usr/bin/xcrun stapler validate "$VERIFY_DESTINATION"
retry_transient "syspolicy_check distribution (installed app)" /usr/bin/syspolicy_check distribution "$VERIFY_DESTINATION"
retry_transient "spctl assess (installed app)" /usr/sbin/spctl --assess --type execute "$VERIFY_DESTINATION"
/bin/cat "$VERIFY_LOG"
echo "Verified signed, notarized TokenStep $INSTALLED_VERSION update installation in an isolated destination."
