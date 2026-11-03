#!/bin/sh
# Run after packaging copied plugins and before cache generation/signing.
set -eu
if [ "$#" -ne 4 ]; then
    echo "usage: $0 app build-dir bundle-id app-name" >&2
    exit 2
fi
mxr_app=$1
mxr_build=$2
mxr_id=$3
mxr_name=$4
case "$mxr_id" in
    ''|org.videolan.vlc) echo "refusing stock VLC bundle identity" >&2; exit 1 ;;
esac
mxr_plugins="$mxr_app/Contents/Frameworks/plugins"
if [ -e "$mxr_plugins/libmacosx_plugin.dylib" ]; then
    echo "stock interface must not be packaged with macosx_redesign" >&2
    exit 1
fi
test -f "$mxr_plugins/libmacosx_redesign_plugin.dylib"
for mxr_bundle in MacOSXRedesign_MXRCore.bundle MacOSXRedesign_MXRDesign.bundle; do
    test -d "$mxr_app/Contents/Resources/$mxr_bundle"
done
# Own icon (flat Figma cone on dark chrome) so the app is distinguishable from stock VLC.
cp "$(dirname "$0")/../Resources/AppIcon.icns" "$mxr_app/Contents/Resources/VLCRedesign.icns"
# The app's own version has one source: the module's VERSION file (D058). The engine's version
# (upstream's CFBundleShortVersionString) moves to MXREngineVersion; About reads it from VLC itself.
mxr_version=$(cat "$(dirname "$0")/../VERSION")
python3 - "$mxr_app/Contents/Info.plist" "$mxr_id" "$mxr_name" "$mxr_version" \
    "$(dirname "$0")/../Resources/update-feed.json" <<'PY'
import json
import plistlib
import re
import sys
target, bundle_id, name, version, feed_file = sys.argv[1:]
if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version):
    sys.exit(f'VERSION must be MAJOR.MINOR.PATCH, not {version!r}')
with open(feed_file) as source:
    feed = json.load(source)
with open(target, 'rb') as source:
    info = plistlib.load(source)
engine = info.get('MXREngineVersion', info.get('CFBundleShortVersionString', ''))
# Upstream's "Copyright (c) <years> VLC authors and VideoLAN" stays, after the unofficial notice.
engine_copyright = info.get('MXREngineCopyright', info.get('NSHumanReadableCopyright', ''))
copyright = (f'{name} {version} is an unofficial build, not affiliated with or endorsed by VideoLAN. '
             f'VLC engine {engine}: {engine_copyright}. Design: Juxtopposed (CC BY 4.0).')
info.update(CFBundleShortVersionString=version, CFBundleVersion=version, MXREngineVersion=engine,
            MXREngineCopyright=engine_copyright, NSHumanReadableCopyright=copyright)
info.update(CFBundleIdentifier=bundle_id, CFBundleName=name, CFBundleDisplayName=name,
            LSMinimumSystemVersion='14.0', NSPrincipalClass='NSApplication',
            NSAppleScriptEnabled=False, CFBundleIconFile='VLCRedesign',
            NSLocalNetworkUsageDescription='Find media servers and playback devices when you open Network or Cast.')
for key in ('NSMainNibFile', 'NSAccentColorName', 'SUPublicDSAKeyFile'):
    info.pop(key, None)
# Our Sparkle feed and EdDSA key replace VideoLAN's (D059); never ship theirs.
info.update(SUFeedURL=feed['feedURL'], SUPublicEDKey=feed['publicEDKey'])
# Customize drags (LayoutDrag.swift UTType(exportedAs:)) need their type declared by the app.
layout_type = {'UTTypeIdentifier': 'org.videolan.vlc-redesign.player-layout-item',
               'UTTypeConformsTo': ['public.data'], 'UTTypeDescription': 'VLC player layout item'}
exported = [t for t in info.get('UTExportedTypeDeclarations', [])
            if t.get('UTTypeIdentifier') != layout_type['UTTypeIdentifier']]
info['UTExportedTypeDeclarations'] = exported + [layout_type]
with open(target, 'wb') as destination:
    plistlib.dump(info, destination, fmt=plistlib.FMT_BINARY)
PY
