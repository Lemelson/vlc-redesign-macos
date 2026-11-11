#!/bin/sh
# Wrap the installed, verified VLC Redesign.app into a release DMG; never rebuilds or re-signs it.
# Run right after tools/install-app.sh (for a release: --app with the universal app of
# make-universal.py) from the same checkout: the DMG names that checkout's commit as the source of
# the build (GPL). Release DMGs come from the public `publish` checkout.
# The Finder window (size, icon places, background, no toolbar) comes from the checked-in
# Resources/dmg/DS_Store template (tools/gen-dmg-layout.py), so no Finder automation runs here.
# Usage: tools/package-dmg.sh output-dir [app]
# Output: VLC-Redesign-<version>-universal.dmg (or -arm64/-x86_64 for a single-architecture app) + .sha256
# The update feed (appcast.xml, signed with the Sparkle key) is written afterwards from the finished DMG
# by the updater's own tool; this script leaves the app's Info.plist and Sparkle.framework as they are.
set -eu
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "usage: $0 output-dir [app]" >&2
    exit 2
fi
mxr_source=$(cd "$(dirname "$0")/../../../.." && pwd)
mxr_tools=$(cd "$(dirname "$0")" && pwd)
mxr_assets="$mxr_tools/../Resources/dmg"
mxr_app=${2:-/Applications/VLC Redesign.app}
mxr_identity=io.github.lemelson.vlc-redesign
mxr_volume="VLC Redesign"
mxr_repository=https://github.com/Lemelson/vlc-redesign-macos
mkdir -p "$1"
mxr_out=$(cd "$1" && pwd -P)
mxr_stage=
mxr_mount=

cleanup() {
    mxr_status=$?
    trap - 0 HUP INT TERM
    if [ -n "$mxr_mount" ]; then hdiutil detach -quiet "$mxr_mount" || hdiutil detach -quiet -force "$mxr_mount" || true; fi
    if [ -n "$mxr_stage" ]; then rm -rf "$mxr_stage"; fi
    exit "$mxr_status"
}
verify_app() {
    test ! -L "$1" || { echo "refusing a symlinked application: $1" >&2; return 1; }
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist")" = "$mxr_identity" || {
        echo "refusing unexpected application identity: $1" >&2; return 1;
    }
    test -f "$1/Contents/Frameworks/plugins/libmacosx_redesign_plugin.dylib" || {
        echo "application is missing the redesign interface: $1" >&2; return 1;
    }
    python3 -I "$mxr_tools/check-minimum-macos.py" "$1"
    python3 "$mxr_tools/finalize-app.py" --verify-only "$1"
}
# The DMG's own parts: window layout, background, volume icon, Applications link, notes.
verify_volume() {
    test -L "$1/Applications" && test "$(readlink "$1/Applications")" = /Applications || {
        echo "DMG is missing the Applications link" >&2; return 1;
    }
    cmp -s "$1/.DS_Store" "$mxr_assets/DS_Store" || { echo "DMG window layout differs from the template" >&2; return 1; }
    test -s "$1/.background/background.tiff" || { echo "DMG is missing its background picture" >&2; return 1; }
    test -s "$1/.VolumeIcon.icns" || { echo "DMG is missing its volume icon" >&2; return 1; }
    test -s "$1/Read Me First.txt" || { echo "DMG is missing Read Me First.txt" >&2; return 1; }
}

test -d "$mxr_app" || { echo "no application at $mxr_app; run tools/install-app.sh first" >&2; exit 1; }
# A dirty tree means the commit below is not the source of the build.
if [ -n "$(git -C "$mxr_source" status --porcelain --untracked-files=no)" ] && [ "${MXR_DMG_ALLOW_DIRTY:-0}" != 1 ]; then
    echo "uncommitted changes in $mxr_source; commit them, rebuild with install-app.sh, or set MXR_DMG_ALLOW_DIRTY=1 for a local test DMG" >&2
    exit 1
fi
python3 -I "$mxr_tools/gen-dmg-layout.py" --check >/dev/null
mxr_commit=$(git -C "$mxr_source" rev-parse --short=10 HEAD)
mxr_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$mxr_app/Contents/Info.plist")
mxr_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$mxr_app/Contents/Info.plist")
case $(lipo -archs "$mxr_app/Contents/MacOS/$mxr_executable" | tr ' ' '\n' | sort | paste -sd' ' -) in
    "arm64 x86_64") mxr_arch=universal ;;
    arm64) mxr_arch=arm64 ;;
    x86_64) mxr_arch=x86_64 ;;
    *) echo "unexpected architectures in $mxr_app" >&2; exit 1 ;;
esac
mxr_dmg="$mxr_out/VLC-Redesign-$mxr_version-$mxr_arch.dmg"
trap cleanup 0
trap 'exit 1' HUP INT TERM
verify_app "$mxr_app"

mxr_stage=$(mktemp -d "${TMPDIR:-/tmp}/vlc-redesign-dmg.XXXXXX")
mxr_root="$mxr_stage/root"
mkdir -p "$mxr_root/.background"
ditto "$mxr_app" "$mxr_root/VLC Redesign.app"
ln -s /Applications "$mxr_root/Applications"
sed -e "s|@COMMIT@|$mxr_commit|g" -e "s|@REPOSITORY@|$mxr_repository|g" -e "s|@VERSION@|$mxr_version|g" \
    "$mxr_tools/dmg-first-launch.txt" > "$mxr_root/Read Me First.txt"
# One TIFF with the 1x and 2x pictures; Finder picks the one for the display.
tiffutil -cathidpicheck "$mxr_assets/background.png" "$mxr_assets/background@2x.png" \
    -out "$mxr_root/.background/background.tiff" >/dev/null 2>&1
cp "$mxr_assets/DS_Store" "$mxr_root/.DS_Store"
cp "$mxr_app/Contents/Resources/VLCRedesign.icns" "$mxr_root/.VolumeIcon.icns"

# hdiutil sometimes fails with "Resource busy" right after a copy; retry a few times, each time
# without the partial image a failed attempt can leave behind.
mxr_rw="$mxr_stage/rw.dmg"
mxr_try=1
until rm -f "$mxr_rw" && hdiutil create -quiet -volname "$mxr_volume" -srcfolder "$mxr_root" -fs HFS+ -format UDRW "$mxr_rw"; do
    if [ "$mxr_try" -ge 5 ]; then echo "hdiutil create failed $mxr_try times" >&2; exit 1; fi
    mxr_try=$((mxr_try + 1))
    sleep 3
done
# Volume-level Finder flags need the mounted volume: the custom volume icon (kHasCustomIcon in
# the root folder's FinderInfo). -nobrowse keeps Finder from opening, and rewriting, the window.
mxr_mount="$mxr_stage/mount"
mkdir "$mxr_mount"
hdiutil attach -quiet -readwrite -nobrowse -noautoopen -mountpoint "$mxr_mount" "$mxr_rw"
xattr -wx com.apple.FinderInfo 0000000000000000040000000000000000000000000000000000000000000000 "$mxr_mount"
verify_volume "$mxr_mount"
hdiutil detach -quiet "$mxr_mount"
mxr_mount=
rm -f "$mxr_dmg"
hdiutil convert -quiet "$mxr_rw" -format UDZO -imagekey zlib-level=9 -o "$mxr_dmg"
hdiutil verify -quiet "$mxr_dmg"

# Check the copy a user gets, not the source.
mxr_mount="$mxr_stage/check"
mkdir "$mxr_mount"
hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$mxr_mount" "$mxr_dmg"
verify_app "$mxr_mount/VLC Redesign.app"
verify_volume "$mxr_mount"
test "$(xattr -px com.apple.FinderInfo "$mxr_mount" | tr -d ' \n' | cut -c17-20)" = 0400 || {
    echo "DMG volume icon flag is not set" >&2; exit 1;
}
hdiutil detach -quiet "$mxr_mount"
mxr_mount=

(cd "$mxr_out" && shasum -a 256 "$(basename "$mxr_dmg")" > "$(basename "$mxr_dmg").sha256")
echo "packaged $mxr_dmg"
