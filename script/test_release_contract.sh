#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/script/build_swiftui_and_run.sh"
PACKAGE_SCRIPT="$ROOT_DIR/script/package_release.sh"
ARTIFACT_VERIFIER="$ROOT_DIR/script/verify_release_artifacts.sh"
INSTALLER_VERIFIER="$ROOT_DIR/script/verify_update_installer.sh"
RELEASE_WORKFLOW="$ROOT_DIR/.github/workflows/release.yml"

CURRENT_VERSION="$(/usr/bin/sed -n 's/^VERSION="${TOKENSTEP_VERSION:-\([^}]*\)}"$/\1/p' "$BUILD_SCRIPT")"
if [[ ! "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Could not resolve the current release version from $BUILD_SCRIPT" >&2
  exit 1
fi

assert_contains() {
  local file="$1"
  local text="$2"
  if ! /usr/bin/grep -Fq -- "$text" "$file"; then
    echo "Release contract is missing '$text' in $file" >&2
    exit 1
  fi
}

for script in "$PACKAGE_SCRIPT" "$ARTIFACT_VERIFIER" "$INSTALLER_VERIFIER"; do
  /bin/bash -n "$script"
done

if [[ ! -f "$ROOT_DIR/docs/RELEASE_NOTES_$CURRENT_VERSION.md" ]]; then
  echo "Missing release notes for $CURRENT_VERSION" >&2
  exit 1
fi
assert_contains "$ROOT_DIR/README.md" "TokenStep-$CURRENT_VERSION.dmg"
assert_contains "$PACKAGE_SCRIPT" "notarytool submit"
assert_contains "$PACKAGE_SCRIPT" "verify_release_artifacts.sh"
assert_contains "$PACKAGE_SCRIPT" "verify_update_installer.sh"
assert_contains "$ARTIFACT_VERIFIER" "stapler validate \"\$DMG_PATH\""
assert_contains "$ARTIFACT_VERIFIER" "syspolicy_check distribution \"\$app_path\""
assert_contains "$INSTALLER_VERIFIER" "stapler validate \"\$VERIFY_DESTINATION\""
assert_contains "$INSTALLER_VERIFIER" "syspolicy_check distribution \"\$VERIFY_DESTINATION\""
assert_contains "$RELEASE_WORKFLOW" "--draft"
assert_contains "$RELEASE_WORKFLOW" "gh release download"
assert_contains "$RELEASE_WORKFLOW" "--draft=false --latest"

draft_line="$(/usr/bin/grep -n 'name: Create verified draft release' "$RELEASE_WORKFLOW" | /usr/bin/cut -d: -f1)"
download_line="$(/usr/bin/grep -n 'name: Download and verify draft assets' "$RELEASE_WORKFLOW" | /usr/bin/cut -d: -f1)"
publish_line="$(/usr/bin/grep -n 'name: Publish verified release' "$RELEASE_WORKFLOW" | /usr/bin/cut -d: -f1)"
if [[ -z "$draft_line" || -z "$download_line" || -z "$publish_line" || \
      "$draft_line" -ge "$download_line" || "$download_line" -ge "$publish_line" ]]; then
  echo "Release workflow must create a draft, verify downloaded assets, then publish." >&2
  exit 1
fi

set +e
missing_version_output="$(
  /usr/bin/env \
    -u TOKENSTEP_VERSION \
    -u CODE_SIGN_IDENTITY \
    -u TOKENSTEP_NOTARY_PROFILE \
    -u APPLE_ID \
    -u APPLE_TEAM_ID \
    -u APPLE_APP_PASSWORD \
    "$PACKAGE_SCRIPT" --notarize 2>&1
)"
missing_version_rc=$?
set -e
if [[ "$missing_version_rc" -ne 2 || "$missing_version_output" != *"TOKENSTEP_VERSION is required"* ]]; then
  echo "Packaging did not fail closed when the release version was missing." >&2
  exit 1
fi

set +e
missing_notary_output="$(
  /usr/bin/env \
    -u TOKENSTEP_NOTARY_PROFILE \
    -u APPLE_ID \
    -u APPLE_TEAM_ID \
    -u APPLE_APP_PASSWORD \
    TOKENSTEP_VERSION="$CURRENT_VERSION" \
    CODE_SIGN_IDENTITY="Developer ID Application: Release Contract Test (AAAAAAAAAA)" \
    "$PACKAGE_SCRIPT" --notarize 2>&1
)"
missing_notary_rc=$?
set -e
if [[ "$missing_notary_rc" -ne 2 || "$missing_notary_output" != *"notarization credentials are mandatory"* ]]; then
  echo "Packaging did not fail closed when Apple notarization credentials were missing." >&2
  exit 1
fi

echo "Release safety contract passed for TokenStep $CURRENT_VERSION."
