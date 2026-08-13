#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/TokenStepSwift"
BUILD_DIR="/tmp/tokenstep-freshness-render-$UID-$$"
OVERLAY_DIR="$BUILD_DIR/vfs-overlay"
OVERLAY_FILE="$OVERLAY_DIR/overlay.yaml"
EMPTY_MODULEMAP="$OVERLAY_DIR/empty.modulemap"
EXECUTABLE="$BUILD_DIR/freshness-states-render"
OUTPUT="${TOKENSTEP_FRESHNESS_RENDER_PATH:-$ROOT_DIR/docs/goal-runs/G-V1/2026-08-13/screenshots/freshness-states.png}"

cleanup() {
  rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

mkdir -p "$BUILD_DIR" "$OVERLAY_DIR" "$(dirname "$OUTPUT")"
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
  "$SWIFT_DIR/Sources/TokenStepSwift/Support/Formatters.swift" \
  "$SWIFT_DIR/Sources/TokenStepSwift/Support/EnergyRefreshPolicy.swift" \
  "$SWIFT_DIR/Sources/TokenStepSwift/Support/FreshnessPolicy.swift" \
  "$SWIFT_DIR/Sources/TokenStepSwift/Models/UsageModels.swift" \
  "$SWIFT_DIR/Sources/TokenStepSwift/Views/FreshnessBadge.swift" \
  "$SWIFT_DIR/Tests/Fixtures/FreshnessStatesRender.swift" \
  -o "$EXECUTABLE"

TOKENSTEP_FRESHNESS_RENDER_PATH="$OUTPUT" "$EXECUTABLE"
echo "Rendered: $OUTPUT"
