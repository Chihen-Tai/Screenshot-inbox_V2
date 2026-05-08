#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_DIRS=(
  "$ROOT_DIR/ScreenshotInbox/Core"
  "$ROOT_DIR/ScreenshotInbox/Models"
)

BANNED_IMPORTS='^[[:space:]]*import[[:space:]]+(SwiftUI|AppKit|Cocoa|Vision|QuickLook)\b'
BANNED_TOKENS='\b(NSImage|NSView|NSWorkspace|NSPasteboard)\b|SwiftUI\.Image'
status=0

for dir in "${CHECK_DIRS[@]}"; do
  [[ -d "$dir" ]] || continue
  if matches="$(rg -n "$BANNED_IMPORTS" "$dir" --glob '*.swift' || true)"; [[ -n "$matches" ]]; then
    echo "Core architecture violation: UI/platform framework import found in $dir"
    echo "$matches"
    status=1
  fi
  if matches="$(rg -n "$BANNED_TOKENS" "$dir" --glob '*.swift' || true)"; [[ -n "$matches" ]]; then
    echo "Core architecture violation: UI/platform type reference found in $dir"
    echo "$matches"
    status=1
  fi
done

if [[ "$status" -eq 0 ]]; then
  echo "Architecture check passed: Core and Models are free of UI framework imports."
fi

exit "$status"
