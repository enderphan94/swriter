#!/bin/bash
# Builds Swriter.app from source: compiles the SwiftUI app, generates the icon,
# assembles the bundle, and ad-hoc signs it. No external dependencies.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Swriter"
BUNDLE_ID="com.enderphan.swriter"
VERSION="1.1.0"
MIN_OS="13.0"
TARGET="arm64-apple-macosx${MIN_OS}"

BUILD_DIR="build"
DIST_DIR="dist"
APP="${DIST_DIR}/${APP_NAME}.app"

rm -rf "$APP"
mkdir -p "$BUILD_DIR" "$DIST_DIR" \
         "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ Compiling Swift sources…"
swiftc -parse-as-library -swift-version 5 -O \
  -target "$TARGET" \
  -framework SwiftUI -framework AppKit \
  -o "$APP/Contents/MacOS/$APP_NAME" \
  Sources/*.swift

echo "▸ Generating app icon…"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
swift scripts/make_icon.swift "$BUILD_DIR/icon_1024.png" >/dev/null
items=( "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
        "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
        "512:512x512" "1024:512x512@2x" )
for it in "${items[@]}"; do
  px="${it%%:*}"; name="${it##*:}"
  sips -z "$px" "$px" "$BUILD_DIR/icon_1024.png" --out "$ICONSET/icon_${name}.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Writing Info.plist…"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>${MIN_OS}</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>A calm Markdown writer for notes and books.</string>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc code signing…"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP" 2>&1 | tail -1 || true

echo "✓ Built $APP"
du -sh "$APP" | awk '{print "  size: "$1}'
