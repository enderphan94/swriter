#!/bin/bash
# Packages dist/Swriter.app into a distributable .dmg with an Applications
# drop-link. Run ./build.sh first.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Swriter"
VERSION="1.0.0"
APP="dist/${APP_NAME}.app"
DMG="dist/${APP_NAME}-${VERSION}.dmg"

if [ ! -d "$APP" ]; then
  echo "✗ $APP not found — run ./build.sh first." >&2
  exit 1
fi

STAGE="build/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/READ ME FIRST.txt" <<'TXT'
Installing Swriter
==================
1. Drag "Swriter" onto the Applications folder.
2. First launch: right-click Swriter → Open → Open (the app is unsigned,
   so Gatekeeper needs this one-time confirmation).
3. On first run, choose where to keep your Vault (a plain folder of .md files).

Your writing is stored as Markdown you fully own — back it up, sync with
iCloud, or open it in Obsidian, VS Code, or iA Writer.
TXT

rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" \
  -ov -format UDZO "$DMG" >/dev/null

echo "✓ Created $DMG"
du -sh "$DMG" | awk '{print "  size: "$1}'
