#!/usr/bin/env bash
set -euo pipefail

# One entry point for every local check. Fixture checks only need swiftc, so
# they run with Command Line Tools alone. The XCTest suite needs a full Xcode,
# because Command Line Tools do not ship XCTest.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Test expectations encode day boundaries in this zone.
export TOKENSTEP_TIMEZONE="Asia/Shanghai"

FIXTURE_CHECKS=(
  test_release_contract
  test_ccswitch_proxy_collector
  test_codex_cumulative_collector
  test_usage_recalibration_migration
  test_time_zone_collector
  test_claude_incremental_collector
  test_settings_codable
  test_compact_popover
)

failed=()
for check in "${FIXTURE_CHECKS[@]}"; do
  echo "==> $check"
  if ! "$ROOT_DIR/script/$check.sh"; then
    failed+=("$check")
  fi
done

if xcrun --find xctest >/dev/null 2>&1; then
  echo "==> swift test"
  if ! swift test --package-path "$ROOT_DIR/TokenStepSwift"; then
    failed+=("swift test")
  fi
else
  echo "==> swift test skipped: XCTest needs a full Xcode (Command Line Tools do not include it)."
  echo "    Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app"
fi

if ((${#failed[@]} > 0)); then
  echo "Failed: ${failed[*]}" >&2
  exit 1
fi
echo "All available checks passed."
