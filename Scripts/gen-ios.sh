#!/bin/bash
# Regenerate the iOS Xcode project from iOS/project.yml.
# One-time setup: brew install xcodegen
set -euo pipefail
cd "$(dirname "$0")/../iOS"
xcodegen generate
echo "Generated iOS/BetterBob-iOS.xcodeproj — open it with: open iOS/BetterBob-iOS.xcodeproj"
