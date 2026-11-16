#!/bin/bash
# Builds VoyagerView.app (release) and ad-hoc signs it.
#
#   scripts/bundle.sh            → ./VoyagerView.app
#   scripts/bundle.sh --install  → also copies it to ~/Applications (recommended for Launch at login)
#
# The app is assembled inside .build first: this repo may live in an iCloud-synced folder, and iCloud
# stamps Finder metadata on bundles, which makes codesign refuse to sign them.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="VoyagerView"
BUNDLE_ID="com.voyagerview.app"
VERSION="$(git describe --tags --always 2>/dev/null || echo 0.1)"

swift build -c release --product "$APP_NAME"
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

STAGE=".build/bundle"
APP="$STAGE/$APP_NAME.app"
rm -rf "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSInputMonitoringUsageDescription</key>
    <string>VoyagerView reads layer changes from your Voyager keyboard's raw HID interface.</string>
</dict>
</plist>
PLIST

xattr -cr "$APP"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify "$APP"

rm -rf "./$APP_NAME.app"
ditto --noextattr --norsrc "$APP" "./$APP_NAME.app"
echo "Built ./$APP_NAME.app"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/$APP_NAME.app"
    ditto --noextattr --norsrc "$APP" "$HOME/Applications/$APP_NAME.app"
    echo "Installed to ~/Applications/$APP_NAME.app"
fi
