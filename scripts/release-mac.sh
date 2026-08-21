#!/bin/bash
# Archive, sign (Developer ID), notarize and package the Mac Catalyst app as a DMG.
# Requires a "SceneBoxNotary" notarytool keychain profile.
# Usage: scripts/release-mac.sh [version]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME=WatchBox
APP_NAME=SceneBox
PROFILE=SceneBoxNotary
VERSION="${1:-}"
OUT="$REPO/build/mac"
ARCHIVE="$OUT/$APP_NAME.xcarchive"
EXPORT="$OUT/export"
rm -rf "$OUT"; mkdir -p "$OUT"

echo "==> Archiving (Mac Catalyst, Release)"
xcodebuild -project "$REPO/WatchBox.xcodeproj" -scheme "$SCHEME" \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  -configuration Release -archivePath "$ARCHIVE" archive \
  -allowProvisioningUpdates \
  ${VERSION:+MARKETING_VERSION="$VERSION"} \
  | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)" | grep -v "no platform load" || true
[ -d "$ARCHIVE" ] || { echo "!! archive failed"; exit 1; }

echo "==> Exporting with Developer ID"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$REPO/scripts/ExportOptions-mac.plist" \
  -exportPath "$EXPORT" -allowProvisioningUpdates \
  | grep -E "error|EXPORT" || true
APP=$(find "$EXPORT" -maxdepth 1 -name "*.app" | head -1)
[ -n "$APP" ] || { echo "!! export failed"; exit 1; }

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP" || echo "   (not yet notarized)"

echo "==> Notarizing the app"
ZIP="$OUT/$APP_NAME.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

echo "==> Building DMG"
DMG="$OUT/$APP_NAME${VERSION:+-$VERSION}.dmg"
if command -v create-dmg >/dev/null; then
  create-dmg --volname "$APP_NAME" --window-size 540 380 --icon-size 128 \
    --icon "$(basename "$APP")" 140 180 --app-drop-link 400 180 \
    "$DMG" "$APP" >/dev/null
else
  STAGE="$OUT/dmg"; mkdir -p "$STAGE"; cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null 2>&1
fi

echo "==> Signing the DMG"
IDENTITY=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
[ -n "$IDENTITY" ] || { echo "!! no Developer ID Application identity in the keychain"; exit 1; }
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

echo "==> Notarizing the DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo ""
echo "==== READY: $DMG ===="
