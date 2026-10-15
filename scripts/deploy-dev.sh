#!/bin/sh
# Builds a signed dev copy of VirtualRemote and installs it on this Mac and on the
# test Mac over ssh, stopping at the first failure. This is not a release: nothing
# is notarized, uploaded or published (scripts/release.sh does that).
#
# usage: SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" sh scripts/deploy-dev.sh [local] [remote]
#   no argument  both Macs
#   local        only this Mac (/Applications)
#   remote       only the test Mac
# optional: REMOTE_HOST=<ssh host> (default macmini)
#
# Each step is checked: the build must verify, the old app must really quit, the
# copy must verify on the target, and the new app must really be running.
set -eu
cd "$(dirname "$0")/.."

: "${SIGN_IDENTITY:?set SIGN_IDENTITY to your Developer ID Application certificate name}"
REMOTE_HOST="${REMOTE_HOST:-macmini}"
APP=build/VirtualRemote.app
DEST=/Applications/VirtualRemote.app
SSH_OPTS="-o BatchMode=yes -o RemoteCommand=none -o RequestTTY=no"

do_local=0
do_remote=0
if [ "$#" -eq 0 ]; then
    do_local=1
    do_remote=1
fi
for target in "$@"; do
    case "$target" in
        local) do_local=1 ;;
        remote) do_remote=1 ;;
        *) echo "unknown target '$target' (use local and/or remote)" >&2; exit 2 ;;
    esac
done

die() {
    echo "deploy-dev: $*" >&2
    exit 1
}

step() {
    echo "== $*"
}

remote() {
    # shellcheck disable=SC2086
    ssh $SSH_OPTS "$REMOTE_HOST" "$@"
}

version() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist"
}

# --- build -------------------------------------------------------------------
step "building and signing"
sh scripts/make-app.sh
[ -d "$APP" ] || die "the build produced no $APP"
codesign --verify --strict "$APP" || die "the new build does not verify, nothing was deployed"
echo "built $APP $(version "$APP")"

# --- this Mac ----------------------------------------------------------------
if [ "$do_local" -eq 1 ]; then
    step "this Mac: stopping the app"
    if pgrep -x VirtualRemote >/dev/null; then
        osascript -e 'tell application "VirtualRemote" to quit' >/dev/null 2>&1 || true
    fi
    tries=0
    while pgrep -x VirtualRemote >/dev/null; do
        tries=$((tries + 1))
        [ "$tries" -le 20 ] || die "the app on this Mac did not quit"
        sleep 0.5
    done

    step "this Mac: installing"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    codesign --verify --strict "$DEST" || die "the copy in /Applications does not verify"

    step "this Mac: starting"
    open "$DEST"
    sleep 3
    pid="$(pgrep -x VirtualRemote)" || die "the app on this Mac did not start"
    echo "this Mac: running $(version "$DEST"), pid $pid"
fi

# --- the test Mac ------------------------------------------------------------
if [ "$do_remote" -eq 1 ]; then
    step "$REMOTE_HOST: stopping the app"
    remote '
        if pgrep -x VirtualRemote >/dev/null; then
            osascript -e "tell application \"VirtualRemote\" to quit" >/dev/null 2>&1 || true
        fi
        tries=0
        while pgrep -x VirtualRemote >/dev/null; do
            tries=$((tries + 1))
            [ "$tries" -le 20 ] || exit 1
            sleep 0.5
        done
    ' || die "could not stop the app on $REMOTE_HOST (is the host reachable?)"

    step "$REMOTE_HOST: copying"
    # shellcheck disable=SC2086
    rsync -a --delete -e "ssh $SSH_OPTS" "$APP/" "$REMOTE_HOST:$DEST/" \
        || die "rsync to $REMOTE_HOST failed"
    remote "xattr -cr $DEST && codesign --verify --strict $DEST" \
        || die "the copy on $REMOTE_HOST does not verify"

    step "$REMOTE_HOST: starting"
    pid="$(remote "open $DEST; sleep 3; pgrep -x VirtualRemote")" \
        || die "the app on $REMOTE_HOST did not start"
    echo "$REMOTE_HOST: running $(remote "/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $DEST/Contents/Info.plist"), pid $pid"
fi

step "done"
