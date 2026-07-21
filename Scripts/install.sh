#!/bin/bash
# Install (or update) BetterBob from the latest GitHub release:
#
#   curl -fsSL https://raw.githubusercontent.com/kevinhufnagl/betterbob/main/Scripts/install.sh | bash
#
# Downloads the release zip into a temp dir, replaces /Applications/BetterBob.app,
# clears the quarantine flag (the app is self-signed), and launches it.
set -euo pipefail

REPO="kevinhufnagl/betterbob"
APP="/Applications/BetterBob.app"

echo "==> Finding the latest BetterBob release…"
URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | cut -d'"' -f4)
if [ -z "$URL" ]; then
  echo "Couldn't find a release zip — see https://github.com/$REPO/releases" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading ${URL##*/}…"
curl -fL --progress-bar "$URL" -o "$TMP/BetterBob.zip"
ditto -xk "$TMP/BetterBob.zip" "$TMP/unzipped"

SRC=$(find "$TMP/unzipped" -maxdepth 2 -type d -name "BetterBob.app" | head -1)
if [ -z "$SRC" ]; then
  echo "BetterBob.app missing from the downloaded zip." >&2
  exit 1
fi

if [ -d "$APP" ]; then
  echo "==> Replacing the existing BetterBob…"
  osascript -e 'tell application "BetterBob" to quit' >/dev/null 2>&1 || true
  rm -rf "$APP"
fi
ditto "$SRC" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "==> Installed $APP"
open "$APP"
echo "Done — Bob lives in your menu bar now. Updates arrive through the in-app updater."
