#!/bin/bash
# Compile and run the unit tests (Tests/main.swift) against the app
# sources, excluding the @main entry point.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH="$(uname -m)"
case "$ARCH" in
  arm64|aarch64) TARGET="arm64-apple-macos26" ;;
  x86_64)        TARGET="x86_64-apple-macos26" ;;
  *) echo "Unsupported arch: $ARCH"; exit 1 ;;
esac

BIN="build/betterbob-tests"
mkdir -p build

SWIFT_FILES=()
while IFS= read -r -d '' f; do
  SWIFT_FILES+=( "$f" )
done < <(find Sources Packages -name '*.swift' -type f \
           -not -path 'Sources/App/*' -not -path '*/.build/*' \
           -not -name 'Package.swift' -print0)

# -j: swiftc won't parallelize frontend jobs on its own here — one flag is
# the difference between ~17s (serial) and ~6s on this many files.
swiftc -j "$(sysctl -n hw.ncpu)" -target "$TARGET" -o "$BIN" "${SWIFT_FILES[@]}" Tests/main.swift

"$BIN"
