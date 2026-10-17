#!/bin/sh
# Native runtime check for the engine patch series (D031); not part of Swift
# unit CI. Point it at a core built with MXR_ENGINE_PATCHES=1 to verify the
# series, or at the unpatched core to reproduce the bug (expected to fail).
set -eu
if [ "$#" -ne 7 ]; then
    printf '%s\n' 'usage: run-paused-seek-smoke.sh CONFIGURED_BUILD CORE_LIBRARY_DIR VLC_PLUGIN_DIR MEDIA software|videotoolbox auhal|amem video|silent|audio' >&2
    exit 2
fi
mxr_build=$1
mxr_core=$2
mxr_plugins=$3
mxr_media=$4
mxr_decoder=$5
mxr_output=$6
mxr_scene=$7
mxr_tests=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mxr_source=$(CDPATH= cd -- "$mxr_tests/../../../.." && pwd)
[ -f "$mxr_build/config.h" ]
[ -f "$mxr_core/libvlccore.dylib" ]
[ -d "$mxr_plugins" ]
[ -f "$mxr_media" ]
case "$mxr_decoder" in software|videotoolbox) ;; *) exit 2 ;; esac
case "$mxr_output" in auhal|amem) ;; *) exit 2 ;; esac
case "$mxr_scene" in video|silent|audio) ;; *) exit 2 ;; esac
mxr_stage=$(mktemp -d "${TMPDIR:-/tmp}/mxr-paused-seek.XXXXXX")
trap 'rm -rf "$mxr_stage"' EXIT HUP INT TERM
mkdir "$mxr_stage/plugins"
xcrun clang -O2 -dynamiclib -DVLC_DYNAMIC_PLUGIN -DHAVE_CONFIG_H \
    '-DMODULE_STRING="mxr_seek_vmem"' -DMODULE_NAME=mxr_seek_vmem \
    -I"$mxr_build" -I"$mxr_build/include" -I"$mxr_source/include" \
    -I"$mxr_source/modules" "$mxr_tests/paused-seek-vmem.c" -L"$mxr_core" -lvlccore \
    -o "$mxr_stage/plugins/libmxr_seek_vmem_plugin.dylib"
xcrun clang -O2 -fobjc-arc -fobjc-exceptions -DHAVE_CONFIG_H \
    -I"$mxr_build" -I"$mxr_build/include" -I"$mxr_source/include" \
    "$mxr_tests/paused-seek-smoke.m" -L"$mxr_core" -lvlccore \
    -framework Foundation -o "$mxr_stage/paused-seek-smoke"
VLC_PLUGIN_PATH="$mxr_stage/plugins:$mxr_plugins" \
DYLD_LIBRARY_PATH="$mxr_core" \
    "$mxr_stage/paused-seek-smoke" "$mxr_media" "$mxr_decoder" "$mxr_output" "$mxr_scene"
