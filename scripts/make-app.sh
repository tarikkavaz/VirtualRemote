#!/bin/sh
# Builds build/VirtualRemote.app from the SwiftPM executable (ad-hoc signed),
# including the mediaremote-adapter (needs git and cmake).
set -eu
cd "$(dirname "$0")/.."

ADAPTER_REPO=https://github.com/ungive/mediaremote-adapter.git
ADAPTER_COMMIT=797729d9b16316dc313844476c153d7a107ca0df
ADAPTER_SRC=build/adapter-src

# --- adapter (pinned) ---
mkdir -p build
if [ ! -d "$ADAPTER_SRC/.git" ]; then
    git clone -q "$ADAPTER_REPO" "$ADAPTER_SRC"
fi
if ! git -C "$ADAPTER_SRC" cat-file -e "$ADAPTER_COMMIT^{commit}" 2>/dev/null; then
    git -C "$ADAPTER_SRC" fetch -q origin
fi
git -C "$ADAPTER_SRC" checkout -q "$ADAPTER_COMMIT"
cmake -S "$ADAPTER_SRC" -B "$ADAPTER_SRC/build" >/dev/null
cmake --build "$ADAPTER_SRC/build" >/dev/null

# --- app ---
swift build -c release --product VirtualRemote
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/VirtualRemote.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/adapter"
cp "$BIN_DIR/VirtualRemote" "$APP/Contents/MacOS/VirtualRemote"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# shown in Settings > General > About
/usr/libexec/PlistBuddy -c "Add :VRAdapterCommit string $ADAPTER_COMMIT" "$APP/Contents/Info.plist"

# SwiftPM resource bundles (e.g. KeyboardShortcuts strings)
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# adapter: perl script, framework (loaded by perl, not linked), test client, license
ADAPTER_DEST="$APP/Contents/Resources/adapter"
cp "$ADAPTER_SRC/bin/mediaremote-adapter.pl" "$ADAPTER_DEST/"
cp -R "$ADAPTER_SRC/build/MediaRemoteAdapter.framework" "$ADAPTER_DEST/"
cp "$ADAPTER_SRC/build/MediaRemoteAdapterTestClient" "$ADAPTER_DEST/"
cp "$ADAPTER_SRC/LICENSE" "$ADAPTER_DEST/LICENSE"

# sign inside out (no --deep). Set SIGN_IDENTITY to a certificate name for a
# stable identity (keeps Local Network and Keychain permissions across rebuilds);
# the default "-" is ad-hoc and changes on every build.
IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" "$ADAPTER_DEST/MediaRemoteAdapter.framework"
codesign --force --sign "$IDENTITY" "$ADAPTER_DEST/MediaRemoteAdapterTestClient"
codesign --force --sign "$IDENTITY" "$APP"
echo "built $APP"
