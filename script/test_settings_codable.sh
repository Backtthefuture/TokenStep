#!/usr/bin/env bash
set -euo pipefail

# Guards the hand-written TokenStepSettings Codable implementation against
# settings that are declared but not encoded or decoded.

# Fixture expectations are written in this zone.
export TOKENSTEP_TIMEZONE="Asia/Shanghai"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/TokenStepSwift"
BUILD_DIR="/tmp/tokenstep-settings-codable-fixture-$UID-$$"
OVERLAY_DIR="$BUILD_DIR/vfs-overlay"
OVERLAY_FILE="$OVERLAY_DIR/overlay.yaml"
EMPTY_MODULEMAP="$OVERLAY_DIR/empty.modulemap"
EXECUTABLE="$BUILD_DIR/settings-codable-fixture-check"

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
  "$SWIFT_DIR/Sources/TokenStepSwift/Support/TokenStepClock.swift" \
  "$SWIFT_DIR/Sources/TokenStepSwift/Support/Localization.swift" \
  "$SWIFT_DIR/Sources/TokenStepSwift/Support/Theme.swift" \
  "$SWIFT_DIR/Sources/TokenStepSwift/Support/SQLiteReadonly.swift" \
  "$SWIFT_DIR/Sources/TokenStepSwift/Models/QuotaModels.swift" \
  "$SWIFT_DIR/Sources/TokenStepSwift/Models/UsageModels.swift" \
  "$SWIFT_DIR/Sources/TokenStepSwift/Services/Collector/"*.swift \
  "$SWIFT_DIR/Tests/Fixtures/SettingsCodableFixtureCheck.swift" \
  -o "$EXECUTABLE"

"$EXECUTABLE"
