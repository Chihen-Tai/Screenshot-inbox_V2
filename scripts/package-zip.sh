#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="0.1.0-alpha"
APP_PATH="$ROOT_DIR/dist/Screenshot Inbox.app"
ZIP_PATH="$ROOT_DIR/dist/ScreenshotInbox-$VERSION.zip"
export COPYFILE_DISABLE=1

"$ROOT_DIR/scripts/build-release.sh"
rm -f "$ZIP_PATH"
ditto -c -k --norsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "$ZIP_PATH"
