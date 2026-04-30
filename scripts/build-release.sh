#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Screenshot Inbox"
EXECUTABLE_NAME="ScreenshotInbox"
RESOURCE_BUNDLE_NAME="ScreenshotInbox_ScreenshotInbox.bundle"
VERSION="0.3.0-alpha"
BUILD_NUMBER="3"
BUNDLE_ID="${BUNDLE_ID:-com.chihentai.screenshotinbox}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/screenshot-inbox-clang-module-cache}"
export SWIFT_MODULE_CACHE_PATH="${SWIFT_MODULE_CACHE_PATH:-/tmp/screenshot-inbox-swift-module-cache}"
export COPYFILE_DISABLE=1

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/release/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod 755 "$MACOS_DIR/$EXECUTABLE_NAME"

if [ -d "$ROOT_DIR/.build/release/$RESOURCE_BUNDLE_NAME" ]; then
  cp -R "$ROOT_DIR/.build/release/$RESOURCE_BUNDLE_NAME" "$RESOURCES_DIR/$RESOURCE_BUNDLE_NAME"
else
  echo "warning: resource bundle not found at .build/release/$RESOURCE_BUNDLE_NAME" >&2
fi

if command -v iconutil >/dev/null 2>&1; then
  ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  cp "$ROOT_DIR"/ScreenshotInbox/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png "$ICONSET_DIR/"
  iconutil -c icns \
    "$ICONSET_DIR" \
    -o "$RESOURCES_DIR/AppIcon.icns"
  rm -rf "$ICONSET_DIR"
else
  cp "$ROOT_DIR/ScreenshotInbox/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" \
    "$RESOURCES_DIR/AppIcon.png"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Chihen Tai</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

find "$APP_DIR" \( -name '.DS_Store' -o -name '._*' \) -delete

if [ "${SKIP_CODESIGN:-0}" != "1" ]; then
  codesign --force --deep --timestamp=none --sign "$SIGN_IDENTITY" "$APP_DIR"
fi

echo "$APP_DIR"
