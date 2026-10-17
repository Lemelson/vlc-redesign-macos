# Native media services checks

These tests compile the actual Objective-C helper and link the built VLC core.
`MXRMediaServicesTests.m` checks source/destination validation and round-trips
quoted Unicode paths through VLC's own `config_ChainCreate` parser.
`MXRMediaServicesRuntimeTests.m` checks real remux, H.264/AAC, MP3, localhost UDP
MPEG-TS packets, cancellation, engine errors, Lua catalog/trigger, and shutdown.
FFmpeg creates the input fixture only; VLC performs every tested media operation.

Run them from `modules/gui/macosx_redesign` against a configured, built engine
(`$BUILD`); the runner compiles each harness, isolates plug-ins (symlinks to the
built dylibs, never `.dSYM` trees), data and user data in a fresh temporary
directory, and removes it after a pass (`--keep` retains it):

```sh
python3 tools/native-tests.py --engine-build "$BUILD"                  # MXRMediaServicesTests (part of the default contracts)
python3 tools/native-tests.py --engine-build "$BUILD" --suite media    # MXRMediaServicesRuntimeTests
```

The media suite generates the MPEG-TS input with FFmpeg and installs a trigger-only
Lua extension (`runtime-trigger.lua`) under the isolated user data; the harness
checks that listing the catalog never runs it.

The existing local engine was configured without `HAVE_CLOCK_GETTIME`, so its
upstream compatibility clock reads `sysctl(KERN_BOOTTIME)`. Codex's sandbox
denies that read and VLC aborts before demuxing; run the narrow runtime check
outside that sandbox. No production source changes or clock substitutions are
needed. The runtime test disables preparsing because its headless executable
does not install VLC's external preparser process binary.

## Local Lua extension installation and removal

`MXRExtensionServicesRuntimeTests.m` exercises the actual Lua manager: installation,
descriptor discovery, no overwrite, invalid-script rollback, protected stock files,
path and symlink rejection, queued duplicate installs, active Lua deactivation,
removal, reload, trigger-only Run and exactly one completion per request. It creates all source,
user-data and system-data fixtures inside a fresh `/private/tmp` directory and
removes that directory after success. It disables user configuration and autosave,
and uses the dummy audio output.

```sh
python3 tools/native-tests.py --engine-build "$BUILD" --suite extensions
```

The runner's plug-in directory contains only symlinks to the built `liblua_plugin.dylib`
and `libadummy_plugin.dylib`. This executable sets `VLC_USERDATA_PATH`,
`VLC_DATA_PATH` and `VLC_LIBEXEC_PATH` to its own fixtures before initializing VLC.
The compatibility-clock sandbox limitation above also applies to Lua activation.
Failed checks preserve their isolated fixture directory for inspection.

Local installation accepts regular `.lua` files and removal preserves stock files
and symlinks. Installation and removal reload the manager on the existing serial
service queue; as with Rescan, this deactivates and joins running extensions.
Snapshot capability flags reflect the loaded manager and writable user directory.
Lua extension windows and the online addon catalog remain explicitly unavailable.

Renderer discovery and selection use real VLC APIs but receiving playback on
physical renderer devices, discs and capture hardware requires a separate
hardware acceptance pass.
