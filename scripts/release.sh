#!/bin/bash
#
#  release.sh
#  Scripts
#
#  Created by rit3zh CX on 10/12/26.
#

# Builds a Developer ID signed, notarized, stapled Slice.app and DMG into dist/.
# Needs SIGN_IDENTITY, TEAM_ID and NOTARY_PROFILE, from the environment or scripts/release.local.env
# (see release.local.env.example), plus Config/Signing.local.xcconfig for the build itself.
set -euo pipefail

notarize() {
  local out
  out=$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --team-id "$TEAM" --wait 2>&1) || true
  if echo "$out" | grep -q "No Keychain password item"; then
    echo "Notary credentials missing. Run once in Terminal:" >&2
    echo "  xcrun notarytool store-credentials $PROFILE --apple-id <your Apple ID> --team-id $TEAM" >&2
    echo "The signed (not notarized) app is at $APP" >&2
    exit 1
  fi
  echo "$out" | tail -3
  if ! echo "$out" | grep -q "status: Accepted"; then
    local id
    id=$(echo "$out" | awk '/^  id:/ {print $2; exit}')
    xcrun notarytool log "$id" --keychain-profile "$PROFILE" || true
    echo "Notarization failed" >&2
    exit 1
  fi
}
cd "$(dirname "$0")/.."

if [ -f scripts/release.local.env ]; then source scripts/release.local.env; fi
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY (see scripts/release.local.env.example)}"
: "${TEAM_ID:?Set TEAM_ID (see scripts/release.local.env.example)}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE (see scripts/release.local.env.example)}"
if [ ! -f Config/Signing.local.xcconfig ]; then
  echo "Create Config/Signing.local.xcconfig (see the .example next to it) so the build is Developer ID signed." >&2
  exit 1
fi
IDENTITY="$SIGN_IDENTITY"
TEAM="$TEAM_ID"
PROFILE="$NOTARY_PROFILE"
APP_NAME="Slice"
DIST="dist"

xcodegen generate >/dev/null
rm -rf "$DIST" build/release
mkdir -p "$DIST"

xcodebuild -project Slice.xcodeproj -scheme Slice -configuration Release \
  -derivedDataPath build/release clean build | grep -E "error:|BUILD" || true
APP="build/release/Build/Products/Release/$APP_NAME.app"
test -d "$APP"
codesign --verify --deep --strict "$APP"

echo "Notarizing app…"
ditto -c -k --keepParent "$APP" "$DIST/app.zip"
notarize "$DIST/app.zip"
xcrun stapler staple "$APP"
rm "$DIST/app.zip"
cp -R "$APP" "$DIST/"

echo "Building DMG…"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DIST/Slice.dmg" >/dev/null
rm -rf "$STAGE"
codesign --sign "$IDENTITY" --timestamp "$DIST/Slice.dmg"
notarize "$DIST/Slice.dmg"
xcrun stapler staple "$DIST/Slice.dmg"

spctl -a -vvv -t install "$DIST/Slice.dmg"
echo "Done: $DIST/Slice.dmg"
