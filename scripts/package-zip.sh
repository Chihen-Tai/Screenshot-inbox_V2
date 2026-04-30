#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.4.0-alpha-dev}"
APP_NAME="Screenshot Inbox"
APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"
ZIP_PATH="$ROOT_DIR/dist/ScreenshotInbox-$VERSION.zip"
export COPYFILE_DISABLE=1

VERSION="$VERSION" "$ROOT_DIR/scripts/build-release.sh"

[ -d "$APP_PATH" ] || { echo "error: app bundle not found at $APP_PATH" >&2; exit 1; }

rm -f "$ZIP_PATH"
ditto -c -k --norsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Verifying packaged ZIP"
TMP_DIR="$(mktemp -d -t screenshotinbox-zip-verify)"
trap 'rm -rf "$TMP_DIR"' EXIT
ditto -x -k "$ZIP_PATH" "$TMP_DIR"
EXTRACTED_APP="$(/usr/bin/find "$TMP_DIR" -maxdepth 3 -name '*.app' -print -quit)"
[ -n "$EXTRACTED_APP" ] || { echo "error: no .app found inside extracted ZIP" >&2; exit 1; }

if [ "${SKIP_CODESIGN:-0}" = "1" ]; then
  echo "    skipped (SKIP_CODESIGN=1)"
else
  if ! codesign --verify --deep --strict --verbose=2 "$EXTRACTED_APP"; then
    echo "error: codesign verification of extracted ZIP failed" >&2
    exit 1
  fi
  echo "    extracted bundle: $EXTRACTED_APP"
  echo "    codesign verify:  ok"
fi

echo "$ZIP_PATH"
