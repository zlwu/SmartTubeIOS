#!/bin/bash
# package-macos.sh - build a locally installable macOS SmartTube (DMG + PKG).
#
#   scripts/package-macos.sh
#
# The app is built Release for macOS (native, not Catalyst) and signed ad-hoc:
# there is no Developer ID in this repo's signing setup, so the result is for
# local/personal install only - it is not notarized and Gatekeeper will block it
# if it is downloaded from the internet. Entitlements are reduced to App Sandbox
# + network access because app groups and iCloud KVS need a real Team ID.
#
# Output: releases/SmartTube-<version>-macOS-<arch>.dmg and .pkg (both gitignored).
# Overrides: SMARTTUBE_ARCH (default arm64), SMARTTUBE_RELEASE_DIR,
#            SMARTTUBE_DERIVED_DATA.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${SMARTTUBE_ARCH:-arm64}"
OUT="${SMARTTUBE_RELEASE_DIR:-$ROOT/releases}"
DERIVED="${SMARTTUBE_DERIVED_DATA:-$ROOT/build/macos-package/DerivedData}"
WORK="$ROOT/build/macos-package"
APP_NAME="SmartTube"
GSP="$ROOT/SmartTubeApp/SmartTubeApp/GoogleService-Info.plist"

[ -f "$GSP" ] || {
    echo "error: $GSP is missing." >&2
    echo "       Add your own Firebase config (see README > Getting Started > Signing)." >&2
    exit 1
}

mkdir -p "$WORK" "$OUT"
echo "==> building $APP_NAME Release (macOS $ARCH)"
xcodebuild build \
    -workspace "$ROOT/SmartTube.xcworkspace" \
    -scheme SmartTube \
    -configuration Release \
    -destination "platform=macOS,arch=$ARCH" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO -quiet \
    || { echo "build failed (see xcodebuild output above)" >&2; exit 1; }

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || { echo "error: $APP not found after build" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
echo "==> $APP_NAME $VERSION ($BUILD)"

# Ad-hoc sign with the Sandbox/network subset that does not need a Team ID.
ENTITLEMENTS="$WORK/entitlements.plist"
cat >"$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
PLIST
echo "==> signing (ad-hoc)"
codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP" \
    && codesign --verify --deep --strict "$APP" \
    || { echo "codesign failed" >&2; exit 1; }

STAGE="$WORK/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

DMG="$OUT/$APP_NAME-$VERSION-macOS-$ARCH.dmg"
rm -f "$DMG"
echo "==> creating $DMG"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG" \
    || { echo "hdiutil failed" >&2; exit 1; }

PKGROOT="$WORK/pkgroot"
rm -rf "$PKGROOT"
mkdir -p "$PKGROOT/Applications"
ditto "$APP" "$PKGROOT/Applications/$APP_NAME.app"
PKG="$OUT/$APP_NAME-$VERSION-macOS-$ARCH.pkg"
rm -f "$PKG"
PKGSIGN=()
[ -n "${SMARTTUBE_INSTALLER_IDENTITY:-}" ] && PKGSIGN=(--sign "$SMARTTUBE_INSTALLER_IDENTITY")
echo "==> creating $PKG"
pkgbuild --root "$PKGROOT" --identifier com.void.smarttube.app \
    --version "$VERSION.$BUILD" --install-location / --ownership recommended \
    ${PKGSIGN[@]+"${PKGSIGN[@]}"} "$PKG" >/dev/null \
    || { echo "pkgbuild failed" >&2; exit 1; }

echo
echo "artifacts:"
ls -lh "$DMG" "$PKG"
echo "note: ad-hoc signed, not notarized - local use only."
