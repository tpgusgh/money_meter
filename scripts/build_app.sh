#!/bin/bash
# Builds a double-clickable 월급미터기.app and zips it for release.
set -euo pipefail
cd "$(dirname "$0")/.."

EXEC_NAME="TimeIsMoney"    # matches the Package.swift executable target; do not rename
APP_DISPLAY_NAME="월급미터기"
APP_DIR="dist/$APP_DISPLAY_NAME.app"
VERSION="${1:-1.0.0}"

swift build -c release

rm -rf "dist"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/$EXEC_NAME" "$APP_DIR/Contents/MacOS/$EXEC_NAME"
cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.tpgusgh.timeismoney</string>
    <key>CFBundleExecutable</key>
    <string>$EXEC_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "dist/$APP_DISPLAY_NAME-$VERSION.zip"

echo "Built dist/$APP_DISPLAY_NAME-$VERSION.zip"
