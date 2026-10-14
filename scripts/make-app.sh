#!/bin/sh
# Builds build/VirtualRemote.app from the SwiftPM executable (ad-hoc signed).
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product VirtualRemote
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/VirtualRemote.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/VirtualRemote" "$APP/Contents/MacOS/VirtualRemote"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# SwiftPM resource bundles (e.g. KeyboardShortcuts strings)
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

codesign --force --sign - "$APP"
echo "built $APP"
