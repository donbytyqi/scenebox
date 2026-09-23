#!/bin/bash
# Mac Catalyst app as a DMG with no Developer ID, no team and no notarization.
# The app gets an ad-hoc signature only (Apple Silicon refuses to run code with none).
# Usage: scripts/release-mac.sh [version]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME=WatchBox
APP_NAME=SceneBox
VERSION="${1:-}"
OUT="$REPO/build/mac"
DERIVED="$OUT/DerivedData"
rm -rf "$OUT"; mkdir -p "$OUT"

echo "==> Building (Mac Catalyst, Release, unsigned)"
xcodebuild -project "$REPO/WatchBox.xcodeproj" -scheme "$SCHEME" \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  ${VERSION:+MARKETING_VERSION="$VERSION"} \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM="" \
  build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

BUILT=$(find "$DERIVED/Build/Products/Release-maccatalyst" -maxdepth 1 -name "*.app" | head -1)
[ -n "$BUILT" ] || { echo "!! build failed"; exit 1; }

STAGE="$OUT/dmg"; mkdir -p "$STAGE"
APP="$STAGE/$(basename "$BUILT")"
cp -R "$BUILT" "$APP"
find "$APP" -name "embedded.provisionprofile" -delete

echo "==> Ad-hoc signing"
ENTITLEMENTS="$OUT/adhoc.entitlements"
cp "$REPO/WatchBox/WatchBox.entitlements" "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Delete :keychain-access-groups" "$ENTITLEMENTS"
find -d "$APP/Contents" \( -name "*.framework" -o -name "*.dylib" -o -name "*.appex" \) -print0 \
  | xargs -0 -n1 codesign --force --sign - --timestamp=none
codesign --force --sign - --timestamp=none --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Building DMG"
DMG="$OUT/$APP_NAME${VERSION:+-$VERSION}.dmg"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null 2>&1

echo ""
echo "==== READY: $DMG ($(du -h "$DMG" | cut -f1)) ===="
