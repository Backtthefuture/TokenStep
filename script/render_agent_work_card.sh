#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/TokenStepSwift"
BUILD_DIR="$SWIFT_DIR/.build/agent-work-card-render"
OVERLAY_DIR="$BUILD_DIR/vfs-overlay"
OVERLAY_FILE="$OVERLAY_DIR/overlay.yaml"
EMPTY_MODULEMAP="$OVERLAY_DIR/empty.modulemap"
EXECUTABLE="$BUILD_DIR/agent-work-card-render"
OUTPUT_PATH="${1:-/tmp/tokenstep-agent-work-card.png}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tokenstep-agent-work-card.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

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

SOURCES=()
while IFS= read -r source; do
  SOURCES+=("$source")
done < <(find "$SWIFT_DIR/Sources/TokenStepSwift" -type f -name '*.swift' ! -path '*/App/TokenStepApp.swift' | sort)

swiftc \
  -D TOKENSTEP_TESTING \
  -target arm64-apple-macos14.0 \
  -vfsoverlay "$OVERLAY_FILE" \
  -Xcc -ivfsoverlay \
  -Xcc "$OVERLAY_FILE" \
  -parse-as-library \
  "${SOURCES[@]}" \
  "$SWIFT_DIR/Tests/Fixtures/AgentWorkCardRender.swift" \
  -o "$EXECUTABLE"

TOKENSTEP_TEST_APP_SUPPORT_ROOT="$TEST_ROOT/app-support" \
TOKENSTEP_AGENT_WORK_CARD_RENDER_PATH="$OUTPUT_PATH" \
"$EXECUTABLE"

test -s "$OUTPUT_PATH"
