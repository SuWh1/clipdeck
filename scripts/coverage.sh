#!/usr/bin/env bash
# Runs the tests with coverage and prints the report for ClipdeckCore.
set -euo pipefail
cd "$(dirname "$0")/.."

swift test --enable-code-coverage >/dev/null
PROFDATA="$(find .build -name default.profdata | head -1)"
BINARY="$(find .build -path '*ClipdeckCoreTests.xctest/Contents/MacOS/ClipdeckCoreTests' -type f | head -1)"
xcrun llvm-cov report "$BINARY" -instr-profile "$PROFDATA" Sources/ClipdeckCore
