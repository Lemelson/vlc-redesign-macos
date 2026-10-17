#!/bin/sh
# Build, verify a disposable replacement, then install one VLC Redesign.app.
# Refuses a running redesign application; never quits it or touches personal VLC.
# Usage: tools/install-app.sh [build-dir]
set -eu
mxr_source=$(cd "$(dirname "$0")/../../../.." && pwd)
mxr_build=${1:-$(cd "$mxr_source/../build/codex-arm64" && pwd)}
mxr_build=$(cd "$mxr_build" && pwd -P)
mxr_dest="/Applications/VLC Redesign.app"
mxr_parent=$(dirname "$mxr_dest")
mxr_identity=org.example.vlc-redesign.codex
mxr_stage=
mxr_backup=
mxr_installed=0
mxr_owned_build=0
mxr_lock="$mxr_parent/.vlc-redesign-install.lock"

bundle_identity() {
    test ! -L "$1" || { echo "refusing a symlinked application: $1" >&2; return 1; }
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist")" = "$mxr_identity" || {
        echo "refusing unexpected application identity: $1" >&2; return 1;
    }
}
require_idle() {
    mxr_running=$(osascript -e 'application id "org.example.vlc-redesign.codex" is running') || {
        echo "unable to establish whether VLC Redesign is running" >&2; return 1;
    }
    test "$mxr_running" = false || { echo "close VLC Redesign before installing" >&2; return 1; }
}
rename_exact() {
    # Unlike mv, rename never nests the source inside an unexpectedly existing directory.
    python3 -c 'import os, sys; os.rename(sys.argv[1], sys.argv[2])' "$1" "$2"
}
cleanup() {
    mxr_status=$?
    trap - 0 HUP INT TERM
    if [ "$mxr_status" -ne 0 ]; then
        if [ "$mxr_installed" -eq 1 ] && ! rm -rf "$mxr_dest"; then
            echo "replacement cleanup failed; previous application retained at $mxr_backup" >&2
            release_lock
            exit 1
        fi
        if [ -n "$mxr_backup" ] && [ -e "$mxr_backup" ]; then
            if ! rename_exact "$mxr_backup" "$mxr_dest"; then
                echo "restore failed; previous application retained at $mxr_backup" >&2
                release_lock
                exit 1
            fi
        fi
    fi
    if [ "$mxr_owned_build" -eq 1 ]; then rm -rf "$mxr_build/VLC.app"; fi
    if [ -n "$mxr_stage" ]; then rm -rf "$mxr_stage"; fi
    release_lock
    exit "$mxr_status"
}
release_lock() {
    rm -f "$mxr_lock/pid"
    rmdir "$mxr_lock" 2>/dev/null || true
}
take_lock() {
    if mkdir "$mxr_lock" 2>/dev/null; then echo $$ > "$mxr_lock/pid"; return 0; fi
    mxr_owner=$(cat "$mxr_lock/pid" 2>/dev/null || true)
    if [ -n "$mxr_owner" ] && kill -0 "$mxr_owner" 2>/dev/null; then
        echo "another redesign installation (pid $mxr_owner) owns $mxr_lock" >&2; return 1
    fi
    # The owner was killed (SIGKILL skips the cleanup trap): reclaim its lock once.
    echo "removing stale installer lock left by pid ${mxr_owner:-unknown}" >&2
    rm -f "$mxr_lock/pid"
    rmdir "$mxr_lock" && mkdir "$mxr_lock" && echo $$ > "$mxr_lock/pid" || {
        echo "unable to take $mxr_lock" >&2; return 1;
    }
}

# Same toolchain environment as configure (build-native.sh): autoconf records it in
# config.log as one "PATH: <dir>/" line per directory, in order.
test -f "$mxr_build/config.log" || { echo "$mxr_build is not a configured build (no config.log)" >&2; exit 1; }
mxr_tools=$(sed -n 's|^PATH: \(.*\)/$|\1|p' "$mxr_build/config.log" | paste -sd: -)
test -n "$mxr_tools" || { echo "no PATH: lines in $mxr_build/config.log; cannot recover the configure toolchain" >&2; exit 1; }
export PATH="$mxr_tools:/usr/bin:/bin:/usr/sbin:/sbin"
# A changed Makefile.am/configure.m4 makes the first make rerun automake/autoconf.
for mxr_tool in autoconf automake; do
    command -v "$mxr_tool" >/dev/null || {
        echo "$mxr_tool is not on the configure PATH ($mxr_tools); rebuild extras/tools or reconfigure" >&2; exit 1;
    }
done
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export MACOSX_DEPLOYMENT_TARGET=10.13
export CLANG_MODULE_CACHE_PATH="$mxr_build/module-cache"
require_idle
if [ -e "$mxr_dest" ] || [ -L "$mxr_dest" ]; then bundle_identity "$mxr_dest"; fi
take_lock || exit 1
trap cleanup 0
trap 'exit 1' HUP INT TERM
# Never remove a stock/foreign or symlinked build bundle to force regeneration.
if [ -e "$mxr_build/VLC.app" ] || [ -L "$mxr_build/VLC.app" ]; then bundle_identity "$mxr_build/VLC.app"; fi
make -C "$mxr_build" -j8
rm -rf "$mxr_build/VLC.app"
make -C "$mxr_build" VLC.app
bundle_identity "$mxr_build/VLC.app"
test -f "$mxr_build/VLC.app/Contents/Frameworks/plugins/libmacosx_redesign_plugin.dylib" || {
    echo "replacement is missing the redesign interface" >&2; exit 1;
}
mxr_owned_build=1
mxr_stage=$(mktemp -d "$mxr_parent/.vlc-redesign-install.XXXXXX")
mxr_backup="$mxr_stage/previous.app"
mxr_replacement="$mxr_stage/replacement.app"
ditto "$mxr_build/VLC.app" "$mxr_replacement"
bundle_identity "$mxr_replacement"
# `make VLC.app` already signed plugins, generated plugins.dat and sealed the bundle
# (extras/package/macosx/codesign.sh); ditto preserved that. Verify, do not re-sign.
python3 "$(dirname "$0")/finalize-app.py" --verify-only "$mxr_replacement"
# The owner can resume work while a build runs. Check again immediately before swapping.
require_idle
if [ -e "$mxr_dest" ] || [ -L "$mxr_dest" ]; then
    bundle_identity "$mxr_dest"
    rename_exact "$mxr_dest" "$mxr_backup"
fi
rename_exact "$mxr_replacement" "$mxr_dest"
mxr_installed=1
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$mxr_dest"
echo "installed $mxr_dest"
