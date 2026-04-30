#!/usr/bin/env bash
set -euo pipefail

# Local developer testing helper only.
#
# Removes the com.apple.quarantine extended attribute from a target .app bundle so the
# Gatekeeper "Apple cannot verify ... is free of malware" prompt does not appear when
# launching a build that was downloaded or otherwise touched by quarantine on this Mac.
#
# WARNING:
#   This is only for local developer testing.
#   Public releases should be signed with a Developer ID Application certificate and
#   notarized through Apple. Do not advise end users to run this script.

if [ "$#" -lt 1 ]; then
  echo "usage: $(basename "$0") <path-to-app-or-file>" >&2
  exit 64
fi

TARGET="$1"

if [ ! -e "$TARGET" ]; then
  echo "error: target not found: $TARGET" >&2
  exit 1
fi

echo "==> Quarantine attributes before:"
xattr -lr "$TARGET" 2>/dev/null | grep com.apple.quarantine || echo "    (none)"

xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

echo "==> Quarantine attributes after:"
xattr -lr "$TARGET" 2>/dev/null | grep com.apple.quarantine || echo "    (none)"

echo "ok: quarantine cleared on $TARGET"
echo "note: this is for local developer testing only — public releases need Developer ID signing + notarization"
