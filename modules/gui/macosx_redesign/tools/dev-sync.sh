#!/bin/sh
# Update only our plugin/bundles in an installed redesign app (close it first).
# Usage: tools/dev-sync.sh build-dir "/Applications/VLC Redesign.app"
set -eu
if [ "$#" -ne 2 ]; then
    echo "usage: $0 build-dir app" >&2
    exit 2
fi
mxr_build=$(cd "$1" && pwd)
mxr_app=$(cd "$2" && pwd)
mxr_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$mxr_app/Contents/Info.plist")
case "$mxr_id" in
    ''|org.videolan.vlc) echo "refusing to update a stock VLC app" >&2; exit 1 ;;
esac
mxr_plugins="$mxr_app/Contents/Frameworks/plugins"
test ! -e "$mxr_plugins/libmacosx_plugin.dylib"
cp "$mxr_build/modules/.libs/libmacosx_redesign_plugin.dylib" "$mxr_plugins/"
for mxr_bundle in MacOSXRedesign_MXRCore.bundle MacOSXRedesign_MXRDesign.bundle; do
    mkdir -p "$mxr_app/Contents/Resources/$mxr_bundle"
    rsync -a --delete "$mxr_build/modules/gui/macosx_redesign/swift/resources/$mxr_bundle/" \
        "$mxr_app/Contents/Resources/$mxr_bundle/"
done
# Re-sign only the replaced plugin, regenerate the cache, then reseal (non-deep).
python3 "$(dirname "$0")/finalize-app.py" "$mxr_app" "$mxr_build/bin/vlc-cache-gen" \
    --sign "$mxr_plugins/libmacosx_redesign_plugin.dylib"
