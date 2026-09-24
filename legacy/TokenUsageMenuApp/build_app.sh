#!/usr/bin/env bash
set -euo pipefail

APP_NAME="TokenStep"
BUNDLE_ID="com.huangshu.TokenStep.prototype"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/TokenUsageMenuApp"
DIST_DIR="$APP_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
# Icon assets are shared with the Swift app and stay in the repository root.
ICON_FILE="$ROOT_DIR/../TokenUsageMenuApp/assets/TokenStepIcon.icns"
PYTHON="/opt/homebrew/opt/python@3.14/bin/python3.14"

if [ ! -x "$PYTHON" ]; then
  PYTHON="$(command -v python3)"
fi

if [ ! -f "$ICON_FILE" ] && [ -f "$APP_DIR/render_icon.py" ]; then
  "$PYTHON" "$APP_DIR/render_icon.py" >/dev/null
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"
cp "$APP_DIR/TokenUsageMenu.py" "$RESOURCES/TokenUsageMenu.py"
if [ -f "$ICON_FILE" ]; then
  cp "$ICON_FILE" "$RESOURCES/TokenStepIcon.icns"
fi

cat > "$MACOS/TokenStep" <<EOF2
#!/usr/bin/env bash
cd "\$(dirname "\$0")/../Resources"
exec "$PYTHON" TokenUsageMenu.py
EOF2
chmod +x "$MACOS/TokenStep"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>TokenStep</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>TokenStepIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_BUNDLE"
