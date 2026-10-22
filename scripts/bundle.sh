#!/usr/bin/env bash
# Builds build/Carousel.app from the SwiftPM executable.
#
# macOS ties the Accessibility permission to the app's code signature. With an ad-hoc
# signature (the default when you have no certificate) every rebuild looks like a new app,
# so you have to re-tick Carousel in System Settings → Privacy & Security → Accessibility.
# Set CODESIGN_IDENTITY to a real certificate to avoid that.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Carousel"

APP=build/Carousel.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Carousel"
cp Resources/Info.plist "$APP/Contents/Info.plist"

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with ${IDENTITY:-ad-hoc signature})"
