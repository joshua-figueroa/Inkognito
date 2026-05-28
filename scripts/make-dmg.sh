#!/usr/bin/env bash
set -euo pipefail

APP="${1:?Usage: make-dmg.sh <path/to/App.app> <output.dmg>}"
DMG="${2:?Usage: make-dmg.sh <path/to/App.app> <output.dmg>}"
APP_NAME="$(basename "$APP" .app)"
VOLUME_NAME="$APP_NAME"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON="$REPO_ROOT/Inkognito/Assets.xcassets/AppIcon.imageset/Inkognito-iOS-Default-1024x1024@1x.png"

rm -f "$DMG"

create-dmg \
  --volname "$VOLUME_NAME" \
  --volicon "$ICON" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 128 \
  --icon "$APP_NAME.app" 180 170 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 480 170 \
  "$DMG" \
  "$(dirname "$APP")"

echo "✓ DMG created: $DMG"
