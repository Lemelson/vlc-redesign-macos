#!/bin/sh
# Build the static Swift product with VLC's compiler flags removed from its environment.
set -eu
if [ "$#" -ne 7 ]; then
    echo "usage: $0 package scratch arch configuration sanitizer archive resources" >&2
    exit 2
fi
mxr_package=$1
mxr_scratch=$2
mxr_arch=$3
mxr_configuration=$4
mxr_sanitizer=$5
mxr_archive=$6
mxr_resources=$7
mxr_build_system=${MXR_SWIFT_BUILD_SYSTEM:-}
if [ -z "$mxr_build_system" ]; then
    case "$(xcrun swift build --help)" in
        *swiftbuild*) mxr_build_system=swiftbuild ;;
        *) mxr_build_system=native ;;
    esac
fi
case "$mxr_build_system" in
    native|swiftbuild) ;;
    *) echo "unsupported Swift build system: $mxr_build_system" >&2; exit 2 ;;
esac
mkdir -p "$mxr_scratch/cache" "$mxr_scratch/config" "$mxr_scratch/security" "$mxr_scratch/module-cache"

mxr_swift() {
    env -u CC -u CXX -u OBJC -u OBJCXX -u CFLAGS -u CXXFLAGS -u OBJCFLAGS \
        -u OBJCXXFLAGS -u CPPFLAGS -u LDFLAGS -u SDKROOT -u MACOSX_DEPLOYMENT_TARGET \
        CLANG_MODULE_CACHE_PATH="$mxr_scratch/module-cache" \
        SWIFTPM_MODULECACHE_OVERRIDE="$mxr_scratch/module-cache" \
        xcrun swift build --package-path "$mxr_package" --scratch-path "$mxr_scratch" \
        --cache-path "$mxr_scratch/cache" --config-path "$mxr_scratch/config" \
        --security-path "$mxr_scratch/security" --disable-sandbox \
        --build-system "$mxr_build_system" --arch "$mxr_arch" \
        --configuration "$mxr_configuration" --product MXRPlugin "$@"
}
if [ -n "$mxr_sanitizer" ]; then
    mxr_swift -Xswiftc -g --sanitize="$mxr_sanitizer"
else
    mxr_swift -Xswiftc -g
fi
mxr_bin=$(mxr_swift --show-bin-path)
test -f "$mxr_bin/libMXRPlugin.a"
mxr_design_resources="$mxr_bin/MacOSXRedesign_MXRDesign.bundle"
if [ -d "$mxr_design_resources/Contents/Resources" ]; then
    mxr_design_resources="$mxr_design_resources/Contents/Resources"
fi
# SwiftPM's native engine copies asset catalogs rather than compiling them.
# Recompile only when the catalog changed, so a no-op make stays a no-op.
mxr_catalog="$mxr_package/Sources/MXRDesign/Resources/Icons.xcassets"
if [ ! -f "$mxr_design_resources/Assets.car" ] || { [ "$mxr_build_system" = native ] &&
        [ -n "$(find "$mxr_catalog" -newer "$mxr_design_resources/Assets.car" -print -quit)" ]; }; then
    xcrun actool --errors --warnings --notices --platform macosx --target-device mac \
        --skip-app-store-deployment --minimum-deployment-target 14.0 \
        --output-format human-readable-text --compile "$mxr_design_resources" \
        "$mxr_catalog"
fi
if [ ! -f "$mxr_design_resources/Assets.car" ]; then
    echo "the Swift build did not compile the redesign asset catalog" >&2
    exit 1
fi
mkdir -p "$(dirname "$mxr_archive")" "$mxr_resources"
# Copy only a changed archive: a fresh mtime would relink the plugin on every make.
cmp -s "$mxr_bin/libMXRPlugin.a" "$mxr_archive" || cp "$mxr_bin/libMXRPlugin.a" "$mxr_archive"
for mxr_name in MacOSXRedesign_MXRCore.bundle MacOSXRedesign_MXRDesign.bundle; do
    test -d "$mxr_bin/$mxr_name"
    mkdir -p "$mxr_resources/$mxr_name"
    rsync -a --delete "$mxr_bin/$mxr_name/" "$mxr_resources/$mxr_name/"
done
