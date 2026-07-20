#!/bin/bash
# Cut a release: bump the version, build, zip the .app, and publish it to
# GitHub Releases (where the in-app updater looks). Usage:
#   ./Scripts/release.sh 1.1
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: ./Scripts/release.sh <version>   e.g. ./Scripts/release.sh 1.1"; exit 1
fi

PLIST="Resources/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST"
echo "==> Version set to $VERSION"

# Force a clean build (removes any stale ad-hoc signature / icon cache).
rm -rf build/BetterBob.app
./Scripts/build.sh

ZIP="build/BetterBob-$VERSION.zip"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent build/BetterBob.app "$ZIP"
echo "==> Zipped $ZIP"

# Commit the version bump, tag, and push — always (needs your git credentials).
git commit -m "Release $VERSION" -- "$PLIST" || true
git tag "v$VERSION"
git push origin HEAD "v$VERSION"
echo "==> Pushed commit + tag v$VERSION"

# Publish the release itself. gh uploads the asset; without it, do that step by hand.
if command -v gh >/dev/null 2>&1; then
  gh release create "v$VERSION" "$ZIP" --title "BetterBob $VERSION" --generate-notes
  echo "==> Published v$VERSION with $ZIP"
else
  cat <<EOF

gh (GitHub CLI) not installed — the code + tag are pushed; finish the release by hand:
  github.com/kevinhufnagl/betterbob/releases → Draft new release
    → choose tag v$VERSION, then upload $ZIP as the asset.
The asset must be a .zip of BetterBob.app (this script already made it), and its
name/tag must be newer than installed builds for the in-app updater to see it.
EOF
fi
