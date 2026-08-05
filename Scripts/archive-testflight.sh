#!/bin/bash
# Archive the iOS app and send it to App Store Connect, where TestFlight picks it up.
# Ported from betterhealth's Scripts/archive-testflight.sh (same team, no Watch app).
#
#   ./Scripts/archive-testflight.sh --team TXPSG28B95            archive and upload
#   ./Scripts/archive-testflight.sh --team TXPSG28B95 --no-upload    archive and export only
#   ./Scripts/archive-testflight.sh --no-gen                     skip regenerating the project
#   ./Scripts/archive-testflight.sh --build 42                   override the build number
#   ./Scripts/archive-testflight.sh --no-archive                 upload the archive already built
#
# `--no-archive` exists because the export is the half that fails — a missing app record, an
# authentication problem, a rejected build number — and rebuilding an identical Release archive to
# retry the step after it costs minutes and can change nothing.
#
# **The build number must rise on every upload** — App Store Connect refuses a repeat for a given
# version. It comes from `git rev-list --count HEAD`, which rises by construction and is the same
# number for the same commit, so an upload can be repeated after a failure without inventing one.
#
# Signing is automatic and `-allowProvisioningUpdates` mints the distribution profiles. The two
# bundle ids (k3n.betterbob.ios, .widgets) and the app group (group.k3n.betterbob) are registered
# on the portal the first time this runs.
#
# Authentication for the upload is an App Store Connect API key (App Store Connect → Users and
# Access → Integrations → App Store Connect API):
#
#   export ASC_KEY_ID=XXXXXXXXXX
#   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#   export ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
#
# With none of the three set the upload falls back to the account signed in to Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

GEN=1
UPLOAD=1
ARCHIVING=1
TEAM=""
BUILD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-gen) GEN=0 ;;
    --no-upload) UPLOAD=0 ;;
    --no-archive) ARCHIVING=0; GEN=0 ;;
    --team) TEAM="${2:-}"; shift ;;
    --build) BUILD="${2:-}"; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$TEAM" ]; then
  echo "Pass --team with the ten-character id of the paid team." >&2
  echo "Xcode → Settings → Accounts shows it beside the membership." >&2
  exit 2
fi

if [ -z "$BUILD" ]; then
  BUILD=$(git rev-list --count HEAD)
fi

if [ "$GEN" = 1 ]; then
  ./Scripts/gen-ios.sh >/dev/null
fi

OUT=build/testflight
ARCHIVE="$OUT/BetterBob.xcarchive"
if [ "$ARCHIVING" = 1 ]; then
  rm -rf "$OUT"
elif [ ! -d "$ARCHIVE" ]; then
  echo "No archive at $ARCHIVE — run without --no-archive first." >&2
  exit 1
else
  rm -rf "$OUT/export"
fi
mkdir -p "$OUT"

# `destination: upload` hands the export straight to App Store Connect, so there is no .ipa to
# carry to Transporter and no `altool` step.
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>$([ "$UPLOAD" = 1 ] && echo upload || echo export)</string>
	<key>teamID</key><string>$TEAM</string>
	<key>signingStyle</key><string>automatic</string>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' iOS/project.yml | head -1)
if [ "$ARCHIVING" = 1 ]; then
  echo "Archiving version ${VERSION} build ${BUILD}, team ${TEAM}…"
  set +e
  xcodebuild \
    -project iOS/BetterBob-iOS.xcodeproj \
    -scheme BetterBob \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -configuration Release \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    archive \
    > "$OUT/archive.log" 2>&1
  STATUS=$?
  set -e
  if [ "$STATUS" != 0 ]; then
    grep -E "error:|ARCHIVE FAILED" "$OUT/archive.log" | head -20 >&2
    echo "" >&2
    echo "Full log: $OUT/archive.log" >&2
    exit 1
  fi
  echo "Archived."
else
  # The build number is the archive's own, not this run's — `--no-archive` reuses what is on disk
  # and `CURRENT_PROJECT_VERSION` above never reached it.
  BUILD=$(plutil -extract ApplicationProperties.CFBundleVersion raw \
    "$ARCHIVE/Info.plist" 2>/dev/null || echo "$BUILD")
  echo "Reusing the archive already built — version ${VERSION} build ${BUILD}."
fi

# **Expanded as `${AUTH[@]+"${AUTH[@]}"}` below, never bare.** macOS ships bash 3.2, where an
# *empty* array's `"${AUTH[@]}"` counts as an unbound variable and `set -u` kills the script.
AUTH=()
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -n "${ASC_KEY_PATH:-}" ]; then
  AUTH=(-authenticationKeyID "$ASC_KEY_ID" \
        -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
        -authenticationKeyPath "${ASC_KEY_PATH/#\~/$HOME}")
elif [ "$UPLOAD" = 1 ]; then
  echo "No ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH — falling back to the Xcode account."
fi

echo "$([ "$UPLOAD" = 1 ] && echo Uploading || echo Exporting)…"
set +e
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -allowProvisioningUpdates \
  ${AUTH[@]+"${AUTH[@]}"} \
  > "$OUT/export.log" 2>&1
STATUS=$?
set -e
if [ "$STATUS" != 0 ]; then
  grep -E "error:|EXPORT FAILED" "$OUT/export.log" | head -20 >&2
  echo "" >&2
  echo "Full log: $OUT/export.log" >&2
  exit 1
fi

if [ "$UPLOAD" = 1 ]; then
  echo "Uploaded build $BUILD. It appears in TestFlight once processing finishes."
else
  echo "Exported to $OUT/export."
fi
