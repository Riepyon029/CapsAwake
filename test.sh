#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$PROJECT_DIR/.build"
xcrun swiftc -swift-version 5 -parse-as-library \
  "$PROJECT_DIR/Sources/Shared/Protocol.swift" "$PROJECT_DIR/Sources/Shared/SessionCore.swift" \
  "$PROJECT_DIR/Tests/SessionTests.swift" -o "$PROJECT_DIR/.build/session-tests"
"$PROJECT_DIR/.build/session-tests"
