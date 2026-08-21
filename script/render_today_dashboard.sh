#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/TokenStepSwift"
BUILD_DIR="$SWIFT_DIR/.build/today-dashboard-render"
OVERLAY_DIR="$BUILD_DIR/vfs-overlay"
OVERLAY_FILE="$OVERLAY_DIR/overlay.yaml"
EMPTY_MODULEMAP="$OVERLAY_DIR/empty.modulemap"
EXECUTABLE="$BUILD_DIR/today-dashboard-render"
OUTPUT_DIR="${1:-$ROOT_DIR/docs/validation/today-dashboard}"

mkdir -p "$BUILD_DIR" "$OVERLAY_DIR" "$OUTPUT_DIR"
cat > "$EMPTY_MODULEMAP" <<'EOF'
// Intentionally empty.
EOF
cat > "$OVERLAY_FILE" <<EOF
{"version":0,"roots":[{"type":"directory","name":"/Library/Developer/CommandLineTools/usr/include/swift","contents":[{"type":"file","name":"module.modulemap","external-contents":"$EMPTY_MODULEMAP"}]}]}
EOF

SOURCES=()
while IFS= read -r source; do SOURCES+=("$source"); done < <(find "$SWIFT_DIR/Sources/TokenStepSwift" -type f -name '*.swift' ! -path '*/App/TokenStepApp.swift' | sort)

swiftc -D TOKENSTEP_TESTING -target arm64-apple-macos14.0 -vfsoverlay "$OVERLAY_FILE" -Xcc -ivfsoverlay -Xcc "$OVERLAY_FILE" -parse-as-library "${SOURCES[@]}" "$SWIFT_DIR/Tests/Fixtures/TodayDashboardRender.swift" -o "$EXECUTABLE"

for scenario in zh-normal zh-empty zh-waiting-details en-normal zh-narrow zh-long-large; do
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/tokenstep-today-${scenario}.XXXXXX")"
  TOKENSTEP_TEST_APP_SUPPORT_ROOT="$test_root/app-support" TOKENSTEP_TODAY_SCENARIO="$scenario" TOKENSTEP_TODAY_RENDER_PATH="$OUTPUT_DIR/$scenario.png" "$EXECUTABLE"
  test -s "$OUTPUT_DIR/$scenario.png"
  rm -rf "$test_root"
done
