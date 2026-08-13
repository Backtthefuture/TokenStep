#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/TokenStepSwift"
BUILD_DIR="/tmp/tokenstep-devicesync-fixture-$UID-$$"
OVERLAY_DIR="$BUILD_DIR/vfs-overlay"
OVERLAY_FILE="$OVERLAY_DIR/overlay.yaml"
EMPTY_MODULEMAP="$OVERLAY_DIR/empty.modulemap"
EXECUTABLE="$BUILD_DIR/device-sync-fixture-check"

cleanup() {
  rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

mkdir -p "$BUILD_DIR" "$OVERLAY_DIR"
cat > "$EMPTY_MODULEMAP" <<'EOF'
// Intentionally empty.
EOF
cat > "$OVERLAY_FILE" <<EOF
{
  "version": 0,
  "roots": [
    {
      "type": "directory",
      "name": "/Library/Developer/CommandLineTools/usr/include/swift",
      "contents": [
        {
          "type": "file",
          "name": "module.modulemap",
          "external-contents": "$EMPTY_MODULEMAP"
        }
      ]
    }
  ]
}
EOF

swiftc \
  -target arm64-apple-macos14.0 \
  -vfsoverlay "$OVERLAY_FILE" \
  -Xcc -ivfsoverlay \
  -Xcc "$OVERLAY_FILE" \
  -parse-as-library \
  "$SWIFT_DIR/Sources/TokenStepSwift/Support/AppPaths.swift" \
  "$SWIFT_DIR/Sources/TokenStepSwift/Support/Localization.swift" \
  "$SWIFT_DIR/Sources/TokenStepSwift/Support/Theme.swift" \
  "$SWIFT_DIR/Sources/TokenStepSwift/Support/EnergyRefreshPolicy.swift" \
  "$SWIFT_DIR/Sources/TokenStepSwift/Support/FreshnessPolicy.swift" \
  "$SWIFT_DIR/Sources/TokenStepSwift/Models/UsageModels.swift" \
  "$SWIFT_DIR/Sources/TokenStepSwift/Services/DeviceSyncService.swift" \
  "$SWIFT_DIR/Tests/Fixtures/DeviceSyncFixtureCheck.swift" \
  -D TOKENSTEP_TESTING \
  -o "$EXECUTABLE"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tokenstep-devicesync-isolated-$UID-XXXXXX")"
mkdir -p "$TEST_ROOT/app-support"
trap 'rm -rf "$TEST_ROOT"' EXIT
TOKENSTEP_TEST_APP_SUPPORT_ROOT="$TEST_ROOT/app-support" "$EXECUTABLE"
