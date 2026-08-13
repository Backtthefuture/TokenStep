#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER_SOURCE="$ROOT_DIR/TokenStepSwift/Sources/TokenStepHelper/main.swift"
BUILD_SCRIPT="$ROOT_DIR/script/build_swiftui_and_run.sh"
TMP_ROOT="$(mktemp -d /tmp/tokenstep-helper-transaction.XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_absent() {
  [[ ! -e "$1" ]] || fail "unexpected path: $1"
}

assert_log() {
  # grep -F：固定字符串匹配，无 riprep 依赖（CI runner 无 rg）。
  grep -aF -- "$2" "$1" >/dev/null || fail "log does not contain: $2"
}

assert_no_backup() {
  if [[ -n "$(find "$1" -maxdepth 1 -name 'TokenStep.app.previous.*' -print -quit)" ]]; then
    fail "stale backup remains under $1"
  fi
}

make_app() {
  local app_path="$1"
  local version="$2"
  local marker="$3"
  mkdir -p "$app_path/Contents/MacOS"
  cat > "$app_path/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.huangshu.TokenStep.fixture</string>
  <key>CFBundleName</key>
  <string>TokenStep</string>
  <key>CFBundleShortVersionString</key>
  <string>$version</string>
  <key>CFBundleVersion</key>
  <string>$version</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>
PLIST
  : > "$app_path/Contents/$marker"
}

cat > "$TMP_ROOT/DataServiceStub.swift" <<'SWIFT'
import Foundation

enum CollectionRunOutcome: String {
    case updated
    case unchanged
    case updatedWhileSourcesChanged = "updated_source_changed"
}

struct DataService {
    struct Settings { let historyDays = 30 }
    static func loadSettings() -> Settings { Settings() }
    static func runCollector(historyDays: Int, force: Bool = false) throws -> CollectionRunOutcome { .updated }
}
SWIFT

cat > "$TMP_ROOT/empty.modulemap" <<'EOF'
// Intentionally empty. The VFS overlay avoids the CLT 16.x SwiftBridging
// module.modulemap collision without modifying the Command Line Tools install.
EOF
cat > "$TMP_ROOT/overlay.yaml" <<EOF
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
          "external-contents": "$TMP_ROOT/empty.modulemap"
        }
      ]
    }
  ]
}
EOF

SWIFTC_ARGS=(
  -parse-as-library \
  -vfsoverlay "$TMP_ROOT/overlay.yaml" \
  -Xcc -ivfsoverlay \
  -Xcc "$TMP_ROOT/overlay.yaml" \
  "$TMP_ROOT/DataServiceStub.swift" \
  "$HELPER_SOURCE"
)
swiftc "${SWIFTC_ARGS[@]}" \
  -D TOKENSTEP_HELPER_TESTING \
  -o "$TMP_ROOT/TokenStepHelper"
swiftc "${SWIFTC_ARGS[@]}" \
  -o "$TMP_ROOT/TokenStepHelper-production"
if "$TMP_ROOT/TokenStepHelper-production" install --test-mode true >"$TMP_ROOT/production-flags.log" 2>&1; then
  fail "production helper unexpectedly accepted test-only arguments"
fi
assert_log "$TMP_ROOT/production-flags.log" "Unknown install argument: --test-mode"

mkdir -p "$TMP_ROOT/payload"
make_app "$TMP_ROOT/payload/TokenStep.app" "2.0.0" "new-version-marker"
/usr/bin/hdiutil create \
  -quiet \
  -fs HFS+ \
  -srcfolder "$TMP_ROOT/payload" \
  "$TMP_ROOT/update.dmg"

DESTINATION="$TMP_ROOT/install/TokenStep.app"
mkdir -p "$(dirname "$DESTINATION")"

run_helper() {
  local log_path="$1"
  local failure_point="$2"
  local args=(
    install
    --dmg "$TMP_ROOT/update.dmg"
    --version "2.0.0"
    --current-pid "0"
    --require-verified "false"
    --log "$log_path"
    --helper-path "$TMP_ROOT/nonexistent-helper-copy"
    --destination "$DESTINATION"
    --skip-relaunch "false"
    --skip-stop "true"
    --test-mode "true"
  )
  if [[ -n "$failure_point" ]]; then
    args+=(--test-failure-point "$failure_point")
  fi
  "$TMP_ROOT/TokenStepHelper" "${args[@]}"
}

# Failure immediately after installed-version validation must remove the copied
# destination, restore the backup, and try to restart the restored app.
make_app "$DESTINATION" "1.0.0" "old-version-marker"
if run_helper "$TMP_ROOT/after-version-check.log" "after-version-check"; then
  fail "after-version-check failure injection unexpectedly succeeded"
fi
assert_file "$DESTINATION/Contents/old-version-marker"
assert_absent "$DESTINATION/Contents/new-version-marker"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$DESTINATION/Contents/Info.plist")" == "1.0.0" ]] \
  || fail "rollback did not restore version 1.0.0"
assert_no_backup "$(dirname "$DESTINATION")"
assert_log "$TMP_ROOT/after-version-check.log" "Removing incomplete destination before rollback"
assert_log "$TMP_ROOT/after-version-check.log" "Restoring previous app"
assert_log "$TMP_ROOT/after-version-check.log" "Attempting to relaunch previous app"
assert_log "$TMP_ROOT/after-version-check.log" "TEST MODE: simulated relaunch of $DESTINATION"

# Failure after the relaunch phase proves that the backup remains available
# until the final commit point.
if run_helper "$TMP_ROOT/before-commit.log" "before-commit"; then
  fail "before-commit failure injection unexpectedly succeeded"
fi
assert_file "$DESTINATION/Contents/old-version-marker"
assert_absent "$DESTINATION/Contents/new-version-marker"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$DESTINATION/Contents/Info.plist")" == "1.0.0" ]] \
  || fail "before-commit rollback did not restore version 1.0.0"
assert_no_backup "$(dirname "$DESTINATION")"
assert_log "$TMP_ROOT/before-commit.log" "Opening updated app"
assert_log "$TMP_ROOT/before-commit.log" "Injected test failure at before-commit"
assert_log "$TMP_ROOT/before-commit.log" "Restoring previous app"

# A successful transaction commits the replacement and removes the backup.
run_helper "$TMP_ROOT/success.log" ""
assert_file "$DESTINATION/Contents/new-version-marker"
assert_absent "$DESTINATION/Contents/old-version-marker"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$DESTINATION/Contents/Info.plist")" == "2.0.0" ]] \
  || fail "successful update did not install version 2.0.0"
assert_no_backup "$(dirname "$DESTINATION")"
assert_log "$TMP_ROOT/success.log" "Installed version: 2.0.0"
assert_log "$TMP_ROOT/success.log" "Update committed; removing backup"

# Static safety check: every process stop and app open in the developer build
# script must remain inside an explicit LAUNCH=true branch.
bash -n "$BUILD_SCRIPT"
python3 - "$BUILD_SCRIPT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
stack = []
checked = []
for lineno, raw in enumerate(path.read_text().splitlines(), 1):
    line = raw.strip()
    if line.startswith("if "):
        stack.append(line)
    elif line == "fi":
        if not stack:
            raise SystemExit(f"FAIL: unmatched fi at {path}:{lineno}")
        stack.pop()
    if "pkill " in line or line.startswith("/usr/bin/open "):
        if not any('"$LAUNCH" == true' in condition for condition in stack):
            raise SystemExit(f"FAIL: launch side effect outside LAUNCH=true at {path}:{lineno}")
        checked.append((lineno, line))

if len([line for _, line in checked if "pkill " in line]) != 4:
    raise SystemExit("FAIL: expected to inspect exactly four pkill commands")
if len([line for _, line in checked if line.startswith("/usr/bin/open ")]) != 1:
    raise SystemExit("FAIL: expected to inspect exactly one app open command")
PY

echo "PASS: helper rollback transaction and --no-launch side-effect guards"
