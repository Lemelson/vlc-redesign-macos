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
python3 - "$mxr_app/Contents/Info.plist" "$mxr_id" "$mxr_name" <<'PY'
import plistlib
import sys
target, bundle_id, name = sys.argv[1:]
with open(target, 'rb') as source:
    info = plistlib.load(source)
info.update(CFBundleIdentifier=bundle_id, CFBundleName=name, CFBundleDisplayName=name,
            LSMinimumSystemVersion='14.0', NSPrincipalClass='NSApplication',
            NSAppleScriptEnabled=False, CFBundleIconFile='VLCRedesign',
            NSLocalNetworkUsageDescription='Find media servers and playback devices when you open Network or Cast.')
for key in ('NSMainNibFile', 'NSAccentColorName', 'SUFeedURL', 'SUPublicDSAKeyFile', 'SUPublicEDKey'):
    info.pop(key, None)
# Customize drags (LayoutDrag.swift UTType(exportedAs:)) need their type declared by the app.
layout_type = {'UTTypeIdentifier': 'org.videolan.vlc-redesign.player-layout-item',
               'UTTypeConformsTo': ['public.data'], 'UTTypeDescription': 'VLC player layout item'}
exported = [t for t in info.get('UTExportedTypeDeclarations', [])
            if t.get('UTTypeIdentifier') != layout_type['UTTypeIdentifier']]
info['UTExportedTypeDeclarations'] = exported + [layout_type]
with open(target, 'wb') as destination:
    plistlib.dump(info, destination, fmt=plistlib.FMT_BINARY)
PY
