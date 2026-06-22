#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/TokenStepSwift"
APP_NAME="TokenStep"
PRODUCT_NAME="TokenStepSwift"
HELPER_NAME="TokenStepHelper"
DIST_DIR="$SWIFT_DIR/dist"
BUILD_DIR="$SWIFT_DIR/.build"
BUILD_LOG="$BUILD_DIR/swift-build.log"
HELPER_BUILD_LOG="$BUILD_DIR/swift-helper-build.log"
OVERLAY_DIR="$BUILD_DIR/vfs-overlay"
OVERLAY_FILE="$OVERLAY_DIR/overlay.yaml"
EMPTY_MODULEMAP="$OVERLAY_DIR/empty.modulemap"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
HELPERS="$CONTENTS/Helpers"
RESOURCES="$CONTENTS/Resources"
EXECUTABLE="$BUILD_DIR/$PRODUCT_NAME"
HELPER_EXECUTABLE="$BUILD_DIR/$HELPER_NAME"
ICON_FILE="$ROOT_DIR/TokenUsageMenuApp/assets/TokenStepIcon.icns"
VERSION="${TOKENSTEP_VERSION:-0.1.40}"
LAUNCH=true
VERIFY=false

for arg in "$@"; do
  case "$arg" in
    --no-launch)
      LAUNCH=false
      ;;
    --verify)
      VERIFY=true
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

pkill -f "TokenUsageMenu.py" 2>/dev/null || true
pkill -x "$PRODUCT_NAME" 2>/dev/null || true
pkill -x "$HELPER_NAME" 2>/dev/null || true
pkill -x "$APP_NAME" 2>/dev/null || true

mkdir -p "$BUILD_DIR" "$DIST_DIR" "$OVERLAY_DIR"
python3 "$ROOT_DIR/script/check_localization.py"
python3 "$ROOT_DIR/script/check_language_refresh.py"
cat > "$EMPTY_MODULEMAP" <<'EOF'
// Intentionally empty.
// CLT 16.x can leave both module.modulemap and bridging.modulemap defining SwiftBridging.
// This overlay hides the stale module.modulemap during this build without modifying /Library/Developer.
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
done < <(find "$SWIFT_DIR/Sources/TokenStepSwift" -type f -name '*.swift' | sort)

if ! swiftc \
  -target arm64-apple-macos14.0 \
  -vfsoverlay "$OVERLAY_FILE" \
  -Xcc -ivfsoverlay \
  -Xcc "$OVERLAY_FILE" \
  -parse-as-library \
  "${SOURCES[@]}" \
  -o "$EXECUTABLE" >"$BUILD_LOG" 2>&1; then
  echo "TokenStep SwiftUI build failed. Full log: $BUILD_LOG" >&2
  tail -n 24 "$BUILD_LOG" >&2
  exit 1
fi

HELPER_SOURCES=(
  "$SWIFT_DIR/Sources/TokenStepSwift/Support/AppPaths.swift"
  "$SWIFT_DIR/Sources/TokenStepSwift/Support/Localization.swift"
  "$SWIFT_DIR/Sources/TokenStepSwift/Support/MemoryPressure.swift"
  "$SWIFT_DIR/Sources/TokenStepSwift/Support/Theme.swift"
  "$SWIFT_DIR/Sources/TokenStepSwift/Models/UsageModels.swift"
  "$SWIFT_DIR/Sources/TokenStepSwift/Services/UsageCollector.swift"
  "$SWIFT_DIR/Sources/TokenStepSwift/Services/DataService.swift"
  "$SWIFT_DIR/Sources/TokenStepHelper/main.swift"
)

if ! swiftc \
  -target arm64-apple-macos14.0 \
  -vfsoverlay "$OVERLAY_FILE" \
  -Xcc -ivfsoverlay \
  -Xcc "$OVERLAY_FILE" \
  -parse-as-library \
  "${HELPER_SOURCES[@]}" \
  -o "$HELPER_EXECUTABLE" >"$HELPER_BUILD_LOG" 2>&1; then
  echo "TokenStep helper build failed. Full log: $HELPER_BUILD_LOG" >&2
  tail -n 24 "$HELPER_BUILD_LOG" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$HELPERS" "$RESOURCES"
cp "$EXECUTABLE" "$MACOS/$PRODUCT_NAME"
cp "$HELPER_EXECUTABLE" "$HELPERS/$HELPER_NAME"
if [ -f "$ICON_FILE" ]; then
  cp "$ICON_FILE" "$RESOURCES/TokenStepIcon.icns"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.huangshu.TokenStep</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>TokenStepIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>LSMultipleInstancesProhibited</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ "$LAUNCH" == true ]]; then
  /usr/bin/open -n "$APP_BUNDLE"
fi

if [[ "$VERIFY" == true ]]; then
  if [[ "$LAUNCH" != true ]]; then
    echo "--verify requires launch; remove --no-launch" >&2
    exit 2
  fi
  sleep 2
  if pgrep -x "$PRODUCT_NAME" >/dev/null; then
    echo "TokenStep SwiftUI is running"
  else
    echo "TokenStep SwiftUI did not start" >&2
    exit 1
  fi
fi
