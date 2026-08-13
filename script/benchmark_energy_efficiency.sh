#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/TokenStepSwift"
BUILD_DIR="${TMPDIR:-/tmp}/tokenstep-energy-benchmark-$UID"
OVERLAY_DIR="$BUILD_DIR/vfs-overlay"
OVERLAY_FILE="$OVERLAY_DIR/overlay.yaml"
EMPTY_MODULEMAP="$OVERLAY_DIR/empty.modulemap"
EXECUTABLE="$BUILD_DIR/energy-efficiency-benchmark"
DATABASE="${TOKENSTEP_BENCHMARK_DATABASE:-$BUILD_DIR/codex-incremental.sqlite3}"

# ---------------------------------------------------------------------------
# fixed-corpus：G-E0 / E0-T04 固定语料基准（PRD §4.6）
# 覆盖 Codex cold/warm/append/rewrite/truncated/corrupt-cache/compare 与
# Claude cold/warm/append；每组独立进程 + 独立语料，/usr/bin/time 采集 max RSS。
# ---------------------------------------------------------------------------
if [ "${1:-warm}" = "fixed-corpus" ]; then
  FIXED_EXECUTABLE="$BUILD_DIR/fixed-corpus-benchmark"
  FIXED_CORPUS_ROOT="$BUILD_DIR/fixed-corpus"
  WARM_RUNS="${TOKENSTEP_BENCHMARK_WARM_RUNS:-5}"

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
    "$SWIFT_DIR/Sources/TokenStepSwift/Services/UsageCollector.swift" \
    "$SWIFT_DIR/Tests/Fixtures/FixedCorpusBenchmark.swift" \
    -o "$FIXED_EXECUTABLE"

  # 每个场景独立语料 + 独立进程；输出 key=value 供下方汇总。
  run_fixed_scenario() {
    local scenario="$1"
    rm -rf "$FIXED_CORPUS_ROOT"
    "$FIXED_EXECUTABLE" generate "$FIXED_CORPUS_ROOT" > "$BUILD_DIR/fixed-$scenario-gen.txt"
    /usr/bin/time -l "$FIXED_EXECUTABLE" "$2" "$FIXED_CORPUS_ROOT" "${@:3}" \
      2> "$BUILD_DIR/fixed-$scenario-time.txt" \
      > "$BUILD_DIR/fixed-$scenario-out.txt" \
      || { echo "scenario=$scenario FAILED"; cat "$BUILD_DIR/fixed-$scenario-out.txt"; return 1; }
    local rss
    rss=$(awk '/maximum resident set size/ { print $1 }' "$BUILD_DIR/fixed-$scenario-time.txt")
    echo "scenario=$scenario max_rss_bytes=$rss"
    grep -E '^(codex_files|claude_files|corpus_sha256)=' "$BUILD_DIR/fixed-$scenario-gen.txt" || true
    cat "$BUILD_DIR/fixed-$scenario-out.txt"
  }

  echo "===== fixed-corpus benchmark report ====="
  date "+timestamp=%Y-%m-%dT%H:%M:%S%z"
  echo "warm_runs=$WARM_RUNS"
  run_fixed_scenario "codex-cold"       codex "$BUILD_DIR/fixed-codex.sqlite3" cold
  run_fixed_scenario "codex-warm"       codex "$BUILD_DIR/fixed-codex.sqlite3" warm "$WARM_RUNS"
  run_fixed_scenario "codex-append"     codex "$BUILD_DIR/fixed-codex.sqlite3" append
  run_fixed_scenario "codex-rewrite"    codex "$BUILD_DIR/fixed-codex.sqlite3" rewrite
  run_fixed_scenario "codex-truncated"  codex "$BUILD_DIR/fixed-codex.sqlite3" truncated
  run_fixed_scenario "codex-corrupt"    codex "$BUILD_DIR/fixed-codex.sqlite3" corrupt-cache
  run_fixed_scenario "codex-compare"    codex "$BUILD_DIR/fixed-codex.sqlite3" compare
  run_fixed_scenario "claude-cold"      claude cold
  run_fixed_scenario "claude-warm"      claude warm "$WARM_RUNS"
  run_fixed_scenario "claude-append"    claude append
  echo "===== end report ====="
  exit 0
fi

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
  "$SWIFT_DIR/Sources/TokenStepSwift/Services/UsageCollector.swift" \
  "$SWIFT_DIR/Tests/Fixtures/EnergyEfficiencyBenchmark.swift" \
  -o "$EXECUTABLE"

mode="${1:-warm}"
/usr/bin/time -l "$EXECUTABLE" "$DATABASE" "$mode"
