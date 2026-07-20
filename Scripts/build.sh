#!/bin/bash
# Build BetterBob.app — menu bar HiBob clock-in/out client with automatic
# breaks. Requires Xcode 17+ (macOS 26 SDK).
set -euo pipefail

APP_NAME="BetterBob"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# Run from project root regardless of where the script is invoked from.
cd "$(dirname "$0")/.."

ARCH="$(uname -m)"
case "$ARCH" in
  arm64|aarch64) TARGET="arm64-apple-macos26" ;;
  x86_64)        TARGET="x86_64-apple-macos26" ;;
  *) echo "Unsupported arch: $ARCH"; exit 1 ;;
esac

echo "==> Cleaning previous build"
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS" "$RESOURCES"

ICON_ICNS="Resources/AppIcon.icns"
ICON_SET="Resources/AppIcon.iconset"

if [[ ! -f "$ICON_ICNS" ]]; then
  echo "==> Generating $ICON_ICNS from Scripts/generate_icon.swift"
  rm -rf "$ICON_SET"
  swift Scripts/generate_icon.swift "$ICON_SET" >/dev/null
  iconutil -c icns "$ICON_SET" -o "$ICON_ICNS"
fi
cp "$ICON_ICNS" "$RESOURCES/AppIcon.icns"

echo "==> Compiling Swift sources (target $TARGET)"
SWIFT_FILES=()
while IFS= read -r -d '' f; do
  SWIFT_FILES+=( "$f" )
done < <(find Sources -name '*.swift' -type f -print0)

# Build in two passes so the swiftc frontend actually emits the const
# values file for App Intents (it's skipped on the one-shot path).
INTERMEDIATES="$BUILD_DIR/intermediates"
mkdir -p "$INTERMEDIATES"
SWIFT_CONST_VALS="$INTERMEDIATES/$APP_NAME.swiftconstvalues"
SWIFT_MODULE="$INTERMEDIATES/$APP_NAME.swiftmodule"
SWIFT_OBJ="$INTERMEDIATES/$APP_NAME.o"

if ! swiftc -O -wmo -c \
    -target "$TARGET" \
    -parse-as-library \
    -emit-module -emit-module-path "$SWIFT_MODULE" \
    -emit-const-values-path "$SWIFT_CONST_VALS" \
    -Xfrontend -const-gather-protocols-file \
    -Xfrontend Scripts/appintents-protocols.json \
    -o "$SWIFT_OBJ" \
    "${SWIFT_FILES[@]}"; then
  echo ""
  echo "!! Compilation failed."
  echo "!! The Liquid Glass UI needs the macOS 26 SDK (Xcode 17+)."
  echo "!! Verify:  xcrun --show-sdk-version   (expect 26.x)"
  exit 1
fi

swiftc -O \
    -target "$TARGET" \
    -parse-as-library \
    -o "$MACOS/$APP_NAME" \
    "$SWIFT_OBJ"

# App Intents metadata bundle — reproduces the Xcode build phase so
# Spotlight, Siri, and the Shortcuts app can see the actions.
echo "==> Generating AppIntents metadata"
SOURCE_LIST="$INTERMEDIATES/sources.txt"
CONST_LIST="$INTERMEDIATES/constvals.txt"
printf '%s\n' "${SWIFT_FILES[@]}" > "$SOURCE_LIST"
echo "$SWIFT_CONST_VALS" > "$CONST_LIST"

XCODE_BUILD="$(xcodebuild -version 2>/dev/null | awk '/Build version/ {print $3}')"
TOOLCHAIN_DIR="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain"
SDK_ROOT="$(xcrun --sdk macosx --show-sdk-path)"

xcrun appintentsmetadataprocessor \
    --output "$RESOURCES" \
    --toolchain-dir "$TOOLCHAIN_DIR" \
    --module-name "$APP_NAME" \
    --sdk-root "$SDK_ROOT" \
    --xcode-version "${XCODE_BUILD:-17A0000}" \
    --platform-family macosx \
    --deployment-target 26.0 \
    --target-triple "$TARGET" \
    --source-file-list "$SOURCE_LIST" \
    --swift-const-vals-list "$CONST_LIST" \
    --no-app-shortcuts-localization \
    --force \
  || echo "   (appintentsmetadataprocessor returned non-zero — Spotlight/Siri may miss actions)"

echo "==> Copying Info.plist"
cp Resources/Info.plist "$CONTENTS/Info.plist"

echo "==> Ad-hoc code signing"
# Pin the signing identifier to the bundle ID so it stays stable across
# rebuilds — TCC and Keychain grants key off the signing identifier.
codesign --force --deep --sign - --identifier k3n.betterbob "$APP_BUNDLE"

echo "==> Nudging macOS icon cache"
touch "$APP_BUNDLE"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "Built: $APP_BUNDLE"
echo ""
echo "Run it:        open $APP_BUNDLE"
echo "Install it:    cp -r $APP_BUNDLE /Applications/"
