#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DISPLAY_NAME="照片转存"
PRODUCT_NAME="PhotoTransferApp"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_DISPLAY_NAME.app"
EXECUTABLE_PATH="$ROOT_DIR/.build/release/$PRODUCT_NAME"

cd "$ROOT_DIR"
swift build -c release --product "$PRODUCT_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/$APP_DISPLAY_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_DISPLAY_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>$APP_DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>local.nick.photo-transfer</string>
    <key>CFBundleName</key>
    <string>$APP_DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_DISPLAY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "$APP_DIR"
