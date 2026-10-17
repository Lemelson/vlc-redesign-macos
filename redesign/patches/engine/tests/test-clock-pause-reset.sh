#!/bin/sh
# Pause/reset/resume regression for the clock patches of the engine series
# (D031). It compiles the actual src/clock/clock.c, by default with the series
# applied to a copy under the output directory; the checkout is not modified.
# With --unpatched it compiles the checkout's clock.c and is expected to fail
# (7 of 13 cases on upstream 4ca4eb0c3e).
# A configured native build provides config.h, generated headers and the core
# mutex/logging support library only. No player or hardware is started.
set -eu
clock_test_mode=patched
if [ "${1:-}" = --unpatched ]; then
    clock_test_mode=unpatched
    shift
fi
if [ "$#" -ne 2 ]; then
    echo "usage: $0 [--unpatched] <configured-native-build> <output-directory>" >&2
    exit 64
fi
clock_test_tests=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
clock_test_source=$(CDPATH= cd -- "$clock_test_tests/../../../.." && pwd -P)
clock_test_build=$(CDPATH= cd -- "$1" && pwd -P)
clock_test_out=$2
clock_test_lib="$clock_test_build/macos-install/lib"
if [ ! -f "$clock_test_build/config.h" ] || [ ! -f "$clock_test_lib/libvlccore.dylib" ]; then
    echo "configured build headers and installed libvlccore.dylib are required" >&2
    exit 66
fi
mkdir -p "$clock_test_out"
clock_test_clock="$clock_test_source/src/clock"
if [ "$clock_test_mode" = patched ]; then
    rm -rf "$clock_test_out/patched-source"
    sh "$clock_test_tests/../engine-patches.sh" files \
        "$clock_test_out/patched-source" "$clock_test_source"
    clock_test_clock="$clock_test_out/patched-source/src/clock"
fi
clock_test_internal="$clock_test_clock/clock_internal.c"
[ -f "$clock_test_internal" ] || clock_test_internal="$clock_test_source/src/clock/clock_internal.c"
echo "clock regression: $clock_test_mode clock.c from $clock_test_clock"
xcrun clang -O2 -DHAVE_CONFIG_H \
    -I"$clock_test_build" -I"$clock_test_build/include" \
    -I"$clock_test_source/include" -I"$clock_test_source/src/clock" \
    "$clock_test_tests/test-clock-pause-reset.c" \
    "$clock_test_clock/clock.c" \
    "$clock_test_internal" \
    -L"$clock_test_lib" -lvlccore -Xlinker -rpath -Xlinker "$clock_test_lib" \
    -o "$clock_test_out/clock-pause-reset-test"
"$clock_test_out/clock-pause-reset-test"
