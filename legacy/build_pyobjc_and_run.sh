#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BUILDER="$ROOT_DIR/TokenUsageMenuApp/build_app.sh"
APP_BUNDLE="$ROOT_DIR/TokenUsageMenuApp/dist/TokenStep.app"

pkill -f "TokenUsageMenu.py" 2>/dev/null || true
pkill -x "TokenStep" 2>/dev/null || true

"$APP_BUILDER" >/dev/null
/usr/bin/open -n "$APP_BUNDLE"

if [[ "${1:-}" == "--verify" ]]; then
  sleep 2
  if pgrep -f "TokenUsageMenu.py" >/dev/null; then
    echo "TokenStep PyObjC prototype is running"
  else
    echo "TokenStep PyObjC prototype did not start" >&2
    exit 1
  fi
fi
