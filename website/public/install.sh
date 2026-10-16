#!/bin/bash
set -euo pipefail

DMG_URL="https://github.com/rit3zh/slice/releases/latest/download/Slice.dmg"
APP="/Applications/Slice.app"

if [[ "$(uname -m)" != "arm64" ]]; then
	echo "Slice needs a Mac with Apple silicon." >&2
	exit 1
fi

TMP="$(mktemp -d)"
MOUNT="$TMP/mount"
trap 'hdiutil detach -quiet "$MOUNT" 2>/dev/null || true; rm -rf "$TMP"' EXIT

echo "Downloading Slice…"
curl -fL --progress-bar "$DMG_URL" -o "$TMP/Slice.dmg"

echo "Installing to Applications…"
mkdir -p "$MOUNT"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$TMP/Slice.dmg"
osascript -e 'quit app "Slice"' 2>/dev/null || true
rm -rf "$APP"
ditto "$MOUNT/Slice.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "Done. Opening Slice."
open "$APP"
