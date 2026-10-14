#!/bin/sh
# Builds a universal, signed, notarized VirtualRemote.app and zips it for sharing.
#
# One-time setup (stores the notarization credentials in your Keychain):
#   xcrun notarytool store-credentials VirtualRemote-notary \
#       --apple-id <your Apple ID> --team-id <your team ID>
#   (it asks for an app-specific password from appleid.apple.com)
#
# usage: SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" sh scripts/release.sh
# optional: NOTARY_PROFILE=<profile name> (default VirtualRemote-notary)
set -eu
cd "$(dirname "$0")/.."

: "${SIGN_IDENTITY:?set SIGN_IDENTITY to your Developer ID Application certificate name}"
PROFILE="${NOTARY_PROFILE:-VirtualRemote-notary}"
APP=build/VirtualRemote.app
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
ZIP="build/VirtualRemote-$VERSION.zip"
UPLOAD=build/notarize-upload.zip

UNIVERSAL=1 HARDENED=1 sh scripts/make-app.sh

echo "== checking the build"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "architectures: $(lipo -archs "$APP/Contents/MacOS/VirtualRemote")"

echo "== notarizing (this can take a few minutes)"
rm -f "$UPLOAD"
ditto -c -k --keepParent "$APP" "$UPLOAD"
OUTPUT="$(xcrun notarytool submit "$UPLOAD" --keychain-profile "$PROFILE" --wait 2>&1)" || true
echo "$OUTPUT"
rm -f "$UPLOAD"
if ! echo "$OUTPUT" | grep -q "status: Accepted"; then
    SUBMISSION="$(echo "$OUTPUT" | awk '/^  id:/ {print $2; exit}')"
    echo "Notarization was not accepted. Details:"
    echo "  xcrun notarytool log $SUBMISSION --keychain-profile $PROFILE"
    exit 1
fi

echo "== stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --verbose=2 --type execute "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "== done"
echo "$ZIP"
shasum -a 256 "$ZIP"
