#!/usr/bin/env bash
set -euo pipefail

# Verifies that usage is split into days in the configured zone and that every
# collector cache is rebuilt when the zone changes. Each phase runs in its own
# process because the collector fixes its zone for the life of the process.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/TokenStepSwift"
BUILD_DIR="/tmp/tokenstep-time-zone-fixture-$UID-$$"
OVERLAY_DIR="$BUILD_DIR/vfs-overlay"
OVERLAY_FILE="$OVERLAY_DIR/overlay.yaml"
EMPTY_MODULEMAP="$OVERLAY_DIR/empty.modulemap"
EXECUTABLE="$BUILD_DIR/time-zone-fixture-check"
DATA_DIR="$BUILD_DIR/data"

cleanup() {
  rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

mkdir -p "$BUILD_DIR" "$OVERLAY_DIR" "$DATA_DIR"
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
  "$SWIFT_DIR/Tests/Fixtures/TimeZoneFixtureCheck.swift" \
  -o "$EXECUTABLE"

in_zone() {
  local zone="$1"
  shift
  TOKENSTEP_TIMEZONE="$zone" "$EXECUTABLE" "$@"
}

fail() {
  echo "Time zone fixture failed: $*" >&2
  exit 1
}

SH="Asia/Shanghai"
LA="America/Los_Angeles"
IN="Asia/Kolkata"
DB="$DATA_DIR/codex-incremental.sqlite3"

in_zone "$SH" write "$DATA_DIR"

# Day and hour follow the zone, and the Codex incremental cache is rebuilt on
# every switch (a stale cache would keep the previous zone's day key).
in_zone "$SH" check "$DATA_DIR" 2026-07-13 10
in_zone "$LA" check "$DATA_DIR" 2026-07-12 19
in_zone "$IN" check "$DATA_DIR" 2026-07-13 8
in_zone "$SH" check "$DATA_DIR" 2026-07-13 10

# A cache from before the zone marker existed was built in Shanghai: it stays
# valid there and gains a marker, but is rebuilt anywhere else.
/usr/bin/sqlite3 "$DB" "DELETE FROM cache_meta WHERE key = 'time_zone'"
before="$(in_zone "$SH" cache-generation "$DATA_DIR")"
in_zone "$SH" check "$DATA_DIR" 2026-07-13 10
after="$(in_zone "$SH" cache-generation "$DATA_DIR")"
[[ "$before" == "$after" ]] || fail "legacy Shanghai cache was rebuilt (generation $before -> $after)"
marker="$(/usr/bin/sqlite3 "$DB" "SELECT value FROM cache_meta WHERE key = 'time_zone'")"
[[ "$marker" == "$SH" ]] || fail "legacy cache did not gain a zone marker (got '$marker')"
echo "PASS legacy cache kept in Shanghai and marked"

/usr/bin/sqlite3 "$DB" "DELETE FROM cache_meta WHERE key = 'time_zone'"
in_zone "$LA" check "$DATA_DIR" 2026-07-12 19
echo "PASS legacy cache rebuilt outside Shanghai"

# The JSON collector cache follows the same rule.
REVISION="$(grep -Eo 'static let codexAccountingRevision = [0-9]+' \
  "$SWIFT_DIR/Sources/TokenStepSwift/Services/Collector/"*.swift | grep -Eo '[0-9]+$')"
json_cache() {
  local file="$1" zone_field="$2"
  printf '{"version":%s,%s"files":{"/tmp/tz.jsonl":{"tool":"Claude Code","size":1,"modificationTime":0,"records":[]}}}' \
    "$REVISION" "$zone_field" > "$DATA_DIR/$file"
}
json_cache legacy.json ''
json_cache la.json "\"timeZone\":\"$LA\","
[[ "$(in_zone "$SH" json-cache "$DATA_DIR" legacy.json)" == reusable ]] || fail "legacy JSON cache discarded in Shanghai"
[[ "$(in_zone "$LA" json-cache "$DATA_DIR" legacy.json)" == discarded ]] || fail "legacy JSON cache reused in Los Angeles"
[[ "$(in_zone "$LA" json-cache "$DATA_DIR" la.json)" == reusable ]] || fail "Los Angeles JSON cache discarded in Los Angeles"
[[ "$(in_zone "$SH" json-cache "$DATA_DIR" la.json)" == discarded ]] || fail "Los Angeles JSON cache reused in Shanghai"
echo "PASS JSON collector cache is scoped to its zone"

echo "Time zone collector fixture checks passed"
