#!/bin/bash
# Builds a double-clickable TimeIsMoney.app and zips it for release.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="TimeIsMoney"
APP_DIR="dist/$APP_NAME.app"
VERSION="${1:-1.0.0}"

swift build -c release

rm -rf "dist"
mkdir -p "$APP_DIR/Contents/MacOS"
cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>월급 카운터 펫</string>
    <key>CFBundleIdentifier</key>
    <string>com.tpgusgh.timeismoney</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP_DIR"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "dist/$APP_NAME-$VERSION.zip"

echo "Built dist/$APP_NAME-$VERSION.zip"
