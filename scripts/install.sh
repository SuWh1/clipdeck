#!/usr/bin/env bash
# Builds Clipdeck, replaces the copy in /Applications (or $DEST) and starts it.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="${DEST:-/Applications}"
./scripts/build-app.sh
pkill -x Clipdeck 2>/dev/null || true
sleep 0.5
rm -rf "$DEST/Clipdeck.app"
ditto dist/Clipdeck.app "$DEST/Clipdeck.app"
open "$DEST/Clipdeck.app"
echo "Installed $DEST/Clipdeck.app"
