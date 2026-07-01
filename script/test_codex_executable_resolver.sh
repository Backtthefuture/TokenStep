#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/TokenStepSwift"
BUILD_DIR="$SWIFT_DIR/.build/codex-executable-resolver-fixture"
EXECUTABLE="$BUILD_DIR/codex-executable-resolver-fixture-check"

mkdir -p "$BUILD_DIR"

swiftc \
  -target arm64-apple-macos14.0 \
  -parse-as-library \
  "$SWIFT_DIR/Sources/TokenStepSwift/Services/CodexExecutableResolver.swift" \
  "$SWIFT_DIR/Tests/Fixtures/CodexExecutableResolverFixtureCheck.swift" \
  -o "$EXECUTABLE"

"$EXECUTABLE"
