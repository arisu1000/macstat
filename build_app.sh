#!/bin/bash

# Exit on any error
set -e

APP_NAME="MacStat"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

if [ ! -f ".build/release/${APP_NAME}" ]; then
    echo "Error: Release binary not found!"
    echo "Please run 'swift build -c release' first before running this script."
    exit 1
fi

echo "Creating App Bundle Structure..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

if [ -f "base_icon.png" ]; then
    echo "Generating App Icon (icns)..."
    mkdir -p MacStat.iconset
    sips -z 16 16     base_icon.png --out MacStat.iconset/icon_16x16.png > /dev/null
    sips -z 32 32     base_icon.png --out MacStat.iconset/icon_16x16@2x.png > /dev/null
    sips -z 32 32     base_icon.png --out MacStat.iconset/icon_32x32.png > /dev/null
    sips -z 64 64     base_icon.png --out MacStat.iconset/icon_32x32@2x.png > /dev/null
    sips -z 128 128   base_icon.png --out MacStat.iconset/icon_128x128.png > /dev/null
    sips -z 256 256   base_icon.png --out MacStat.iconset/icon_128x128@2x.png > /dev/null
    sips -z 256 256   base_icon.png --out MacStat.iconset/icon_256x256.png > /dev/null
    sips -z 512 512   base_icon.png --out MacStat.iconset/icon_256x256@2x.png > /dev/null
    sips -z 512 512   base_icon.png --out MacStat.iconset/icon_512x512.png > /dev/null
    sips -z 1024 1024 base_icon.png --out MacStat.iconset/icon_512x512@2x.png > /dev/null
    iconutil -c icns MacStat.iconset -o AppIcon.icns
    rm -rf MacStat.iconset
    cp AppIcon.icns "${RESOURCES_DIR}/"
    echo "App Icon Generated and Copied."
fi

echo "Copying binary..."
cp ".build/release/${APP_NAME}" "${MACOS_DIR}/"

echo "Creating Info.plist..."
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.${APP_NAME}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/> <!-- Hides the dock icon -->
</dict>
</plist>
EOF

echo "Done! The application bundle ${APP_DIR} has been created."
echo "You can move it to your /Applications folder to use it like a regular macOS app."
