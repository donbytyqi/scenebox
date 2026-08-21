#!/bin/bash
# Unsigned iOS .ipa for sideloading (Sideloadly / AltStore re-sign it).
# Usage: scripts/export-ipa.sh [version]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME=WatchBox
APP_NAME=SceneBox
VERSION="${1:-}"
OUT="$REPO/build/ios"
DERIVED="$OUT/DerivedData"
rm -rf "$OUT"; mkdir -p "$OUT"

echo "==> Building (iOS device, Release, unsigned)"
xcodebuild -project "$REPO/WatchBox.xcodeproj" -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  ${VERSION:+MARKETING_VERSION="$VERSION"} \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

APP=$(find "$DERIVED/Build/Products/Release-iphoneos" -maxdepth 1 -name "*.app" | head -1)
[ -n "$APP" ] || { echo "!! build failed"; exit 1; }

echo "==> Packaging IPA"
STAGE="$OUT/Payload"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
find "$STAGE" -name "_CodeSignature" -type d -prune -exec rm -rf {} +
find "$STAGE" -name "embedded.mobileprovision" -delete

IPA="$OUT/$APP_NAME${VERSION:+-$VERSION}.ipa"
(cd "$OUT" && zip -qry "$IPA" Payload)
rm -rf "$STAGE"

echo ""
echo "==== READY: $IPA ($(du -h "$IPA" | cut -f1)) ===="
echo "Install with Sideloadly."
