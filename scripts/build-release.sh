#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Screenshot Inbox"
EXECUTABLE_NAME="ScreenshotInbox"
RESOURCE_BUNDLE_NAME="ScreenshotInbox_ScreenshotInbox.bundle"
VERSION="${VERSION:-0.4.0-alpha-dev}"
BUILD_NUMBER="${BUILD_NUMBER:-4}"
BUNDLE_ID="${BUNDLE_ID:-com.chihentai.screenshotinbox}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/screenshot-inbox-clang-module-cache}"
export SWIFT_MODULE_CACHE_PATH="${SWIFT_MODULE_CACHE_PATH:-/tmp/screenshot-inbox-swift-module-cache}"
export COPYFILE_DISABLE=1

cd "$ROOT_DIR"

# Clean previous staged bundle so a stale signature can't survive into the new build.
rm -rf "$APP_DIR"

swift build -c release

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

# Strip junk that codesign hates before signing.
find "$APP_DIR" \( -name '.DS_Store' -o -name '._*' \) -delete

# --- Bundle sanity checks (run BEFORE signing) ---
echo "==> Bundle sanity checks"
[ -d "$APP_DIR" ] || { echo "error: app bundle missing: $APP_DIR" >&2; exit 1; }
[ -f "$CONTENTS_DIR/Info.plist" ] || { echo "error: Info.plist missing" >&2; exit 1; }
[ -x "$MACOS_DIR/$EXECUTABLE_NAME" ] || { echo "error: main executable missing or not executable" >&2; exit 1; }

PLIST_BUDDY=/usr/libexec/PlistBuddy
PLIST_BID=$("$PLIST_BUDDY" -c "Print CFBundleIdentifier" "$CONTENTS_DIR/Info.plist")
PLIST_VER=$("$PLIST_BUDDY" -c "Print CFBundleShortVersionString" "$CONTENTS_DIR/Info.plist")
PLIST_BUILD=$("$PLIST_BUDDY" -c "Print CFBundleVersion" "$CONTENTS_DIR/Info.plist")
[ "$PLIST_BID" = "$BUNDLE_ID" ] || { echo "error: CFBundleIdentifier mismatch ($PLIST_BID != $BUNDLE_ID)" >&2; exit 1; }
[ "$PLIST_VER" = "$VERSION" ] || { echo "error: CFBundleShortVersionString mismatch ($PLIST_VER != $VERSION)" >&2; exit 1; }
[ "$PLIST_BUILD" = "$BUILD_NUMBER" ] || { echo "error: CFBundleVersion mismatch ($PLIST_BUILD != $BUILD_NUMBER)" >&2; exit 1; }
if [ ! -f "$RESOURCES_DIR/AppIcon.icns" ] && [ ! -f "$RESOURCES_DIR/AppIcon.png" ]; then
  echo "error: app icon missing in Resources/" >&2; exit 1
fi
echo "    bundle id:    $PLIST_BID"
echo "    version:      $PLIST_VER"
echo "    build:        $PLIST_BUILD"
echo "    executable:   $MACOS_DIR/$EXECUTABLE_NAME"

# Detect anything that smells like personal data inside the staged bundle.
if grep -RIl --include='*.plist' --include='*.json' --include='*.txt' --include='*.html' \
     -e '/Users/' "$APP_DIR" 2>/dev/null; then
  echo "warning: personal-looking paths found inside the bundle" >&2
fi

# --- Signing (last step before any verification, no further bundle mutations after) ---
if [ "${SKIP_CODESIGN:-0}" = "1" ]; then
  echo "==> Skipping codesign (SKIP_CODESIGN=1)"
else
  if [ -n "${DEVELOPER_ID_APPLICATION:-}" ]; then
    echo "==> Signing with Developer ID: $DEVELOPER_ID_APPLICATION"
    codesign --force --deep --options runtime --timestamp \
      --sign "$DEVELOPER_ID_APPLICATION" "$APP_DIR"
  else
    SIGN_IDENTITY="${SIGN_IDENTITY:--}"
    echo "==> Ad-hoc signing (identity: $SIGN_IDENTITY)"
    codesign --force --deep --timestamp=none --sign "$SIGN_IDENTITY" "$APP_DIR"
  fi

  echo "==> codesign -dv"
  codesign -dv --verbose=4 "$APP_DIR" 2>&1 | sed 's/^/    /'

  echo "==> codesign --verify"
  if ! codesign --verify --deep --strict --verbose=2 "$APP_DIR"; then
    echo "error: codesign verification failed" >&2
    exit 1
  fi

  echo "==> spctl assessment (informational; ad-hoc builds are expected to be rejected)"
  spctl --assess --type execute --verbose=4 "$APP_DIR" 2>&1 | sed 's/^/    /' || true
fi

echo "$APP_DIR"
