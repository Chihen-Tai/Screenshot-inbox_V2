#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/dist/Screenshot Inbox.app}"
PLIST_BUDDY=/usr/libexec/PlistBuddy

if [ ! -d "$APP_PATH" ]; then
  echo "error: app bundle not found: $APP_PATH" >&2
  exit 1
fi

CONTENTS_DIR="$APP_PATH/Contents"
PLIST_PATH="$CONTENTS_DIR/Info.plist"

if [ ! -f "$PLIST_PATH" ]; then
  echo "error: Info.plist missing: $PLIST_PATH" >&2
  exit 1
fi

EXECUTABLE_NAME="$("$PLIST_BUDDY" -c "Print CFBundleExecutable" "$PLIST_PATH")"
EXECUTABLE_PATH="$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME"

if [ ! -x "$EXECUTABLE_PATH" ]; then
  echo "error: executable missing or not executable: $EXECUTABLE_PATH" >&2
  exit 1
fi

BUNDLE_ID="$("$PLIST_BUDDY" -c "Print CFBundleIdentifier" "$PLIST_PATH")"
VERSION="$("$PLIST_BUDDY" -c "Print CFBundleShortVersionString" "$PLIST_PATH")"
BUILD="$("$PLIST_BUDDY" -c "Print CFBundleVersion" "$PLIST_PATH")"

echo "==> Bundle"
echo "    app:        $APP_PATH"
echo "    bundle id:  $BUNDLE_ID"
echo "    version:    $VERSION"
echo "    build:      $BUILD"
echo "    executable: $EXECUTABLE_PATH"

if [ "${SKIP_CODESIGN:-0}" = "1" ]; then
  echo "==> codesign verification skipped (SKIP_CODESIGN=1)"
  exit 0
fi

echo "==> codesign -dv"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | sed 's/^/    /'

echo "==> codesign --verify"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "    codesign verify: ok"

echo "==> spctl assessment"
if spctl --assess --type execute --verbose=4 "$APP_PATH" 2>&1 | sed 's/^/    /'; then
  echo "    spctl assessment: accepted"
else
  echo "    spctl assessment: rejected or unavailable"
  echo "    note: ad-hoc signed or non-notarized downloaded apps may still be rejected by Gatekeeper."
fi
