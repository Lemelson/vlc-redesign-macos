#!/bin/sh
# Build in a new directory while reusing an existing, read-only contrib/tool installation.
# Example: build-native.sh /path/to/codex-arm64 /path/to/stock-arm64 /path/to/stock-source
#
# The engine is built unmodified (D031). MXR_ENGINE_PATCHES=1 builds it with the
# optional series in redesign/patches/engine/ instead: the series is applied to
# a copy of this checkout at <build-dir>/engine-source, and the build directory
# is configured against that copy. The checkout itself is never modified. Use a
# separate build directory for patched builds; this script refuses to switch an
# existing build directory between the checkout and the patched copy.
set -eu
if [ "$#" -ne 3 ]; then
    echo "usage: $0 build-dir stock-build-dir stock-source-dir" >&2
    exit 2
fi
mxr_source=$(cd "$(dirname "$0")/../../../.." && pwd)
mxr_destination=$1
mxr_stock=$(cd "$2" && pwd)
mxr_tools_source=$(cd "$3" && pwd)
mkdir -p "$mxr_destination"
mxr_destination=$(cd "$mxr_destination" && pwd)
if [ "$mxr_destination" = "$mxr_stock" ]; then
    echo "refusing to reconfigure the stock build" >&2
    exit 1
fi
mxr_engine_patches="$mxr_source/redesign/patches/engine/engine-patches.sh"
case "${MXR_ENGINE_PATCHES:-0}" in
    0) mxr_engine_source=$mxr_source
       mxr_expected=$(cd "$mxr_source" && pwd -P) ;;
    1) mxr_engine_source="$mxr_destination/engine-source"
       mxr_expected="$(cd "$mxr_destination" && pwd -P)/engine-source" ;;
    *) echo "MXR_ENGINE_PATCHES must be 0 or 1" >&2; exit 2 ;;
esac
if [ -f "$mxr_destination/Makefile" ]; then
    mxr_configured=$(sed -n 's/^abs_top_srcdir = //p' "$mxr_destination/Makefile")
    if [ "$(cd "$mxr_configured" 2>/dev/null && pwd -P)" != "$mxr_expected" ]; then
        echo "$mxr_destination is configured for $mxr_configured, not $mxr_engine_source;" >&2
        echo "use a separate build directory for MXR_ENGINE_PATCHES=${MXR_ENGINE_PATCHES:-0}" >&2
        exit 1
    fi
fi
mxr_contrib="$mxr_stock/contrib/aarch64-apple-darwin19"
test -d "$mxr_contrib"
test -x "$mxr_tools_source/extras/tools/build/bin/autoconf"
export PATH="$mxr_tools_source/extras/tools/build/bin:$mxr_stock/contrib/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PKG_CONFIG_LIBDIR="$mxr_contrib/lib/pkgconfig"
export CLANG_MODULE_CACHE_PATH="$mxr_destination/module-cache"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export MACOSX_DEPLOYMENT_TARGET=10.13
# Libtool's Darwin probe uses sysctl, which can be restricted in an agent sandbox.
# getconf queries the same ARG_MAX without leaving an empty command-size limit.
export lt_cv_sys_max_cmd_len=$(($(getconf ARG_MAX) / 4 * 3))
mkdir -p "$CLANG_MODULE_CACHE_PATH"
export CC="$(xcrun -f clang)"
export CXX="$(xcrun -f clang++)"
export OBJC="$CC"
export OBJCXX="$CXX"
export CFLAGS='-g -arch arm64 -Werror=incompatible-function-pointer-types'
export CXXFLAGS="$CFLAGS"
export OBJCFLAGS="$CFLAGS"
export OBJCXXFLAGS="$CFLAGS"
export LDFLAGS='-arch arm64'
# Use upstream's deployment-target symbol exclusions and libtool C/ObjC compatibility.
set -- none
. "$mxr_source/extras/package/macosx/env.build.sh"
vlcSetSymbolEnvironment
if [ ! -x "$mxr_source/configure" ]; then
    (cd "$mxr_source" && ./bootstrap)
fi
if [ "$mxr_engine_source" = "$mxr_source" ]; then
    # Fails if a patch of the series is already in src/ (upstream merged it, or
    # src/ was edited against D031).
    sh "$mxr_engine_patches" check "$mxr_source"
else
    # Fails loudly if a patch no longer applies or is already upstream.
    sh "$mxr_engine_patches" copy "$mxr_engine_source" "$mxr_source"
fi
cd "$mxr_destination"
"$mxr_engine_source/configure" --prefix=/ --disable-macosx --enable-macosx-redesign \
    --with-macosx-redesign-bundle-id=org.example.vlc-redesign.codex \
    --with-macosx-redesign-app-name='VLC Redesign' --disable-ncurses \
    --disable-macosx-ui-shaders --enable-merge-ffmpeg --enable-osx-notifications \
    --enable-flac --enable-theora --enable-shout --enable-twolame --enable-libass \
    --enable-macosx-avfoundation --disable-xcb --disable-caca --disable-pulse \
    --disable-vnc --without-x --build=aarch64-apple-darwin19 --host=aarch64-apple-darwin19 \
    --with-contrib="$mxr_contrib" --with-macosx-version-min=10.13 \
    --with-macosx-sdk="$SDKROOT"
make -j8
# No `make VLC.app` here: tools/install-app.sh <build-dir> packages, verifies and installs
# the single /Applications/VLC Redesign.app and removes the build-dir bundle.
