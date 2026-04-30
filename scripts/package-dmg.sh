#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="0.3.0-alpha"
APP_PATH="$ROOT_DIR/dist/Screenshot Inbox.app"
STAGING_DIR="$ROOT_DIR/dist/dmg-root"
DMG_PATH="$ROOT_DIR/dist/ScreenshotInbox-$VERSION.dmg"
export COPYFILE_DISABLE=1

"$ROOT_DIR/scripts/build-release.sh"
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "Screenshot Inbox $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "$DMG_PATH"
