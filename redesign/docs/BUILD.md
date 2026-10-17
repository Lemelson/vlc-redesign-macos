# Building VLC.app with the `macosx_redesign` interface

Applies to Apple Silicon (arm64) and upstream base `4ca4eb0c3e` (tag `upstream-base-2026-10-14`). Read
`ARCHITECTURE.md` for the why. Markers: **[verified]** = checked on this machine or in the code;
**[unverified]** = expected but not yet run; **[estimate]** = not measured.

The interface module and the three upstream build integration points are now implemented.
`--enable-macosx-redesign` selects the SwiftUI/AppKit interface. The original stock
build remains a separate baseline.

## Supported paths (read this first)

Paths used throughout this document:

```sh
export SRC=<this checkout>                       # e.g. .../codex-redesign
export BUILD=<configured redesign build dir>     # e.g. ../build/codex-arm64, configured by tools/build-native.sh
export STOCK=<stock baseline build dir>          # read-only contribs and stock reference (e.g. ../build/arm64)
M="$SRC/modules/gui/macosx_redesign"
```

There is exactly one installed copy of the app, `/Applications/VLC Redesign.app`
(`org.example.vlc-redesign.codex`). Never run or replace `/Applications/VLC.app`, and
never leave another VLC bundle (a build-dir `VLC.app`, a stock test clone) behind.

1. **Build and install** (the only way to produce the app), with the app closed:

   ```sh
   "$M/tools/install-app.sh" "$BUILD"        # default build dir: $SRC/../build/codex-arm64
   ```

   It recovers configure's toolchain `PATH` from `$BUILD/config.log` (so a changed
   `Makefile.am` can rerun automake), runs `make`, `make VLC.app` (which signs plugins,
   generates `plugins.dat` and seals the bundle via `extras/package/macosx/codesign.sh`),
   verifies a staged copy (`finalize-app.py --verify-only`: identity, no stock interface,
   `plugins.dat` newer than every plugin, `codesign --verify --deep --strict`), swaps it
   in with rollback on any failure, and deletes the build-dir `VLC.app`. It refuses a
   running app and foreign or stock bundle identities. A lock left by a killed run is
   reclaimed when its recorded pid is gone.

2. **Fast loop for the plugin only** (app closed, installed by step 1 once):

   ```sh
   make -C "$BUILD/modules" -j10 libmacosx_redesign_plugin.la
   "$M/tools/dev-sync.sh" "$BUILD" "/Applications/VLC Redesign.app"
   ```

   `dev-sync.sh` copies the plugin dylib and our two resource bundles, re-signs only
   that dylib, regenerates and signs `plugins.dat` (everything in `Contents/Frameworks`
   must carry a signature, or the seal fails), and reseals the app (non-deep).

3. **Tests:** `make -C "$BUILD/modules" check-macosx-redesign` (generators, native
   contracts, all Swift tests, tooling tests); while iterating,
   `swift test --filter <Suite>`, `python3 "$M/tools/run-swift-tests.py" "$M" <scratch>`
   and `python3 "$M/tools/native-tests.py" --engine-build "$BUILD" [--suite …]`.
   After installing, `make -C "$BUILD/modules" check-macosx-redesign-app MXR_SMOKE_MEDIA=…`
   runs a real start/play/quit of the installed app (see `WORKFLOW.md`).

   `native-tests.py` details (2026-10-17):
   - Every suite runs in a fresh work directory (removed after a pass; `--keep` keeps
     it; a failure always keeps it and prints `Native evidence retained at <dir>`).
     Each step prints its duration.
   - The plugin bank is indexed with `$BUILD/bin/vlc-cache-gen` before any harness runs,
     like the shipped bundle's `plugins.dat`. Without the cache the core dlopens every
     plugin and `libvlc_InternalCleanup` dlcloses them all: the silent 1.5 s idle
     (> 8 s under load) after "removing keystore memory" that made the
     audio-preferences shutdown deadline flake. With it, that shutdown takes ~40 ms.
     The step is mandatory for every suite: a missing `$BUILD/bin/vlc-cache-gen` (partial
     build: `make -C "$BUILD/bin" vlc-cache-gen`) or a run that writes no `plugins.dat`
     stops the runner before any harness (`tools/test-native-runtime-isolation.py`).
   - Harnesses that include `module/bridge/tests/MXRNativeTestDiagnostics.h` print
     `[+ms] phase: …` markers and timestamped engine log lines. On a missed deadline
     they print the running phase, the last engine log line and a `sample` call graph
     of every thread, also written to `$MXR_NATIVE_EVIDENCE_DIR` (the work directory).
     `tools/test-native-diagnostics.py` proves that output on a deliberately stuck harness.
   - Harnesses link a weak `vlc_module_name` (the real plugin gets it from its module
     descriptor), so bridge helpers may log with `msg_*`.
   - Hold the shared native lock around suites and `make` when other agents work on the
     same machine: `redesign/research/final-polish/workflows/lock.sh acquire <who>` …
     `lock.sh release`. Its directory comes from `MXR_LOCK_DIR` (default
     `../build/locks/native.lock`); `lock.sh status` shows the holder.

The source tree keeps the engine unchanged (D031). Earlier build directories
(`codex-final-*`, `codex-paused-seek-*`, the stock baseline) are historical
evidence; do not launch their bundles as current builds or use their hashes as proof
for the current commit. The sections from §0 on retain the original stock-baseline
procedure and measurements; where they differ from the three paths above, the paths
above win.

### Engine patches (D031)

The checkout builds an unmodified engine: `src/` is identical to upstream. The
paused-seek fix from D020 is kept as an optional patch series in
`redesign/patches/engine/` (see its `README.md` for each patch, its
reproduction and its upstream status). Builds include it only on request, and
the series is applied to a copy, never to the checkout:

```sh
MXR_ENGINE_PATCHES=1 "$M/tools/build-native.sh" "$BUILD-engine-patches" "$STOCK" <stock-source-with-extras-tools>
"$M/tools/install-app.sh" "$BUILD-engine-patches"   # install the patched build (replaces the single copy)
```

`build-native.sh` configures and builds (`make`) only; it never packages a bundle.

- The script mirrors the checkout into `<build-dir>/engine-source`, applies the
  series there and configures against that copy. Re-run the script (not a bare
  `make`) after edits so the copy is re-synced; unchanged files keep their
  timestamps, so the rebuild stays incremental.
- Use a separate build directory. The script refuses to switch a configured
  directory between the checkout and a patched copy, so `codex-arm64` always
  holds the unmodified engine.
- Patched builds report a revision ending in `-engine-patches`.
- Every build checks the series. If a patch is already in `src/` (upstream merged
  it, or someone edited `src/`), the build stops and names it. If a patch no
  longer applies, patched builds stop; plain builds print a warning.

The clock regression compiles the real `clock.c`, with the series applied to a
copy, and does not start a player or audio device (`--unpatched` reproduces the
bug: 7 of 13 cases fail):

```sh
sh redesign/patches/engine/tests/test-clock-pause-reset.sh "$BUILD" <scratch-dir>
```

The manual four-topology media regression is
`redesign/patches/engine/tests/run-paused-seek-smoke.sh`. Run it against a core
built with `MXR_ENGINE_PATCHES=1` (the unpatched core fails). Its usage
requires explicit configured build, core library directory, plugin directory,
generated 60-second media, decoder/output and video/silent/audio mode. Recorded
commands, source/core hashes, original RED and final GREEN results are in
`../build/codex-paused-seek-evidence-v6/native/paused-seek-final-proof-committed.json`.
Do not run hardware-output probes concurrently with a user-operated app.

For comparable visual checks, the snapshot executable must declare the actual
SDK 27 and minOS 14 used by the native app. On this installed Swift toolchain,
the default `swiftbuild` snapshot link declares SDK 14 despite compiling with
SDK 27; it changes some native Picker layouts. This is separate from the
offscreen execution-context difference: full runs outside the sandbox gave
12 PASS / 49 REVIEW / 37 FAIL, while the matching sandbox context reproduced
13 PASS / 55 REVIEW / 30 FAIL without source, asset or threshold changes.
Both diagnostics are preserved; their low-level renderer cause is not claimed.
The supported `--build-system native` snapshot runner declares SDK 27 and is frozen
in `../build/codex-final-runner-c5793f739e-sdk27/`; the comparable final report is
`../build/codex-independent-visual-c5793f739e-sdk27-sandbox/MANUAL_REVIEW.md`.
Query `--show-bin-path` with
the same build-system option rather than assuming an old scratch output path.
The native module/main executable also declare SDK 27. Do not compensate source
colors or change comparison thresholds for a test-runner compatibility mismatch.

The sections below retain the original stock-baseline build measurements and
upstream build procedure; `$BUILD` there means any out-of-tree build dir.

---

## 0. What it costs

(corrected 2026-10-14 after build: the rows below were measured during a stock build of `main`; see `NOTES.md`,
entry "Stock VLC.app baseline build".)

| Item | Disk | Time | Status |
|---|---|---|---|
| `extras/tools` (autoconf, automake, libtool, pkg-config, cmake, nasm, meson, ninja, gettext, bison, m4, xz, zstd, help2man, ant, built from source into `$SRC/extras/tools/build`) | 1.4 GB in `$SRC/extras/tools`: `build/` is only 139 MB, the rest is unpacked sources and objects (cmake 590 MB, gettext 374 MB). Don't delete them: make re-unpacks and rebuilds. | 19 min, once (4–6 min of it downloads) | **verified** |
| Prebuilt contribs tarball (`vlc-contrib-aarch64-apple-darwin19-<sha>.tar.zst`) | 215 MB in `$BUILD/contrib/contrib-<triplet>/` (deleted after unpacking; nothing needs it again) | 1 m 58 s download | **verified**: 215,431,447 bytes |
| Unpacked contribs (`$BUILD/contrib/aarch64-apple-darwin19`) | 1.0 GB (lib 918 MB, include 44 MB, share 30 MB; 123 static libs; includes Sparkle and Breakpad frameworks) | about 5 s unpack + `change_prefix.sh` | **verified** |
| Contrib native tools (`make tools`: builds `luac` from lua 5.4.4 and `protoc` from protobuf 3.21.1) | 56 MB build dir + 4.4 MB `contrib/bin`; 10 MB of tarballs in **`$SRC/contrib/tarballs/`** | about 40 s to build, plus downloads (see §3 for network failures) | **verified** |
| `./bootstrap` + configure | (git-ignored files in `$SRC`) | 17 s + 52 s (30 s on a rerun) | **verified** |
| VLC build tree (debug, 392 plugins) | about 1.2 GB (`modules/` 923 MB). DWARF stays in the `.o` files, so no dSYMs | `make -j10`: about 5 min clean (2,521 compiles, 707 links). A no-op `make -j10`: 12.7 s | **verified** |
| `macos-install/` + `VLC.app` | 157 MB + 157 MB | `make VLC.app`: 2 m 03 s | **verified** |
| SwiftPM scratch for the plugin (and Gallery) | 0.1–0.8 GB | first build 1–3 min, incremental seconds | estimate (a small prototype package used 54–89 MB) |
| **Total** | **about 3.7 GB** (`$BUILD` 2.3 GB + `extras/tools` 1.4 GB), plus SwiftPM scratch | **about 30 min the first time** when the network behaves | **verified** for the stock build |

- Free disk on this machine was 14–23 GB during this analysis and 26–34 GB during the first build. Keep **at least
  6 GB** free before the first build.
- Building contribs **from source** instead (`-c`) costs an extra 1–2.5 h and roughly 5–10 GB of sources and
  objects [estimate]. Avoid it: see §3.
- The Gallery workflow (§9) needs **no** VLC build: only Xcode, a few hundred MB, and seconds to build.

---

## 1. Prerequisites

Required:
- **Xcode 27** with its command-line tools selected. Accept the licence and run the first-launch tasks.
  ```sh
  xcode-select -p                         # /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept && xcodebuild -runFirstLaunch
  xcrun swift --version                   # Swift 6.x  (here: 6.4)  [verified]
  xcrun -f actool                         # used by SwiftPM for asset catalogs [verified present]
  ```
  The Metal toolchain is **not** needed: only the stock GUI's shaders use it (`configure.ac:4695-4740`), and we
  build with `--disable-macosx`.
  (corrected 2026-10-14 after build) **A stock build does need it, or a flag.** Xcode 27 ships a `metal` stub but
  no `metallib` until `xcodebuild -downloadComponent MetalToolchain` (`xcodebuild -showComponent MetalToolchain`
  says "uninstalled" here). `configure.sh` passes `--enable-macosx`, which turns the shaders on, so configure
  stops with "metallib was not found, required for macosx-ui-shaders". For the stock baseline, pass
  `--disable-macosx-ui-shaders` (it only drops the snow shader). With `--disable-macosx` the shader option follows
  `enable_macosx` and is off.
- `git`, `curl`, `python3`. The system ones are fine: `/usr/bin/python3` is 3.9.6 here, and `build.sh` only checks
  that `python3` runs (`build.sh:142-145`).
- Network access to `artifacts.videolan.org` (prebuilt contribs) and the source mirrors `extras/tools` downloads from.
  (corrected 2026-10-14 after build) Also `www.lua.org` and `github.com`: after the prebuilt contribs, `make tools`
  downloads lua and protobuf (§3). `downloads.videolan.org` answers slowly (about 20 s per request here) and 404s
  for several tool tarballs (meson 1.12.0, Kitware's ninja), so most downloads fall back to the upstream URLs.

**Homebrew packages: none are required.** Two deliberate points:
- `build.sh` **resets `PATH`** to `$SRC/extras/tools/build/bin:<python.org python>:$VLC_PATH:/bin:/sbin:/usr/bin:/usr/sbin`
  (`extras/package/macosx/env.build.sh:96`). Homebrew is therefore invisible unless you put it into `VLC_PATH`.
  `extras/tools/bootstrap` then builds whatever is missing from source: on this machine that is autoconf, automake,
  GNU libtool, pkg-config, cmake, xz, nasm, gettext, help2man, meson, ninja and zstd [verified with
  `env -i PATH=/bin:/sbin:/usr/bin:/usr/sbin`]. Bison and m4 in `/usr/bin` are too old, so they get built too.
  (corrected 2026-10-14 after build) Apache ant 1.9.7 is installed as well (38 MB, a binary distribution).
- **Do not set `VLC_PATH=/opt/homebrew/bin`.**
  - VLC's configure only *prepends* the contrib dir to `PKG_CONFIG_PATH` (`configure.ac:690`).
  - Homebrew's `pkgconf` would still search `/opt/homebrew/lib/pkgconfig`. This Mac has 381 `.pc` files there,
    including ffmpeg, x264, x265, libvpx, dav1d, libarchive, libmatroska and Qt.
  - Configure could then link optional modules against Homebrew dylibs, and the app would break on other Macs.

Optional:
- `brew install ccache`, then point `VLC_CCACHE_BINS_PATH` at a directory containing `cc` and `c++` symlinks to
  `ccache` (`env.build.sh:78-89`). This speeds up rebuilds after upstream merges.
- `pip3 install dmgbuild` (on the build `PATH`) for the "fancy" DMG (`configure.ac` `DMGBUILD`,
  `package.mak:102-106`). Without it `hdiutil` builds a plain DMG.

---

## 2. Source tree

The clone is blobless (`upstream … [blob:none]`). The working tree is complete, so the build needs no extra
fetches. Keep `upstream` fetched so the contrib SHA can be computed:

```sh
cd "$SRC"
git fetch upstream            # downloads commits/trees; blobs only on demand
git status --short            # build products are .gitignored (configure, Makefile.in, extras/tools/build, …)
```

`build.sh` writes some files **into the source tree**: `extras/tools/build/` and its tarballs, plus `./bootstrap`
output (`configure`, `Makefile.in`, `aclocal.m4`, …). All of these are git-ignored [verified with
`git check-ignore`]. Everything else goes to `$BUILD`.
(corrected 2026-10-14 after build) Two more: the unpacked tool sources in `extras/tools/<tool>/` (about 1.26 GB;
deleting them makes the next `build.sh` rebuild those tools), and the contrib tool tarballs in
`contrib/tarballs/` (lua, protobuf). Both are git-ignored [verified with `git status --ignored`].

Using git worktrees for parallel agents: each worktree is a separate source tree.
Use one isolated VLC build tree for Codex integration, reusing the stock contribs
read-only. Domain worktrees use the Gallery (§9) and separate SwiftPM scratch
directories; they do not reconfigure or rebuild the preserved stock tree.

---

## 3. Prebuilt contribs (the only fast way)

How it works [verified in code]:
- `build.sh:204-226` runs `make prebuilt` in `$BUILD/contrib/contrib-<triplet>` unless `-c` is given. It uses
  `PREBUILT_URL=$VLC_PREBUILT_CONTRIBS_URL` when that is set (`build.sh:207-208`).
- The rule (`contrib/src/main.mak:764-779`) downloads the tarball, unpacks it to `$BUILD/contrib/<triplet>`, runs
  `change_prefix.sh` and regenerates the meson machine file.
- `build.sh` then runs `make tools` (`build.sh:224`) to build native helper tools that aren't found.
  (corrected 2026-10-14 after build) Here those are `luac` (lua 5.4.4) and `protoc` (protobuf 3.21.1), installed in
  `$BUILD/contrib/bin`. Their tarballs are **downloaded** into `$SRC/contrib/tarballs/`, first from
  `downloads.videolan.org/pub/contrib/<pkg>/`, then from `www.lua.org` / `github.com`. `curl --retry 3` gives up
  on a connect timeout, and `build.sh` (`set -e`) stops with
  `make: *** [.../contrib/tarballs/protobuf-3.21.1.tar.gz] Error 28`. That happened here behind a VPN. Recovery:
  ```sh
  mkdir -p "$BUILD/../downloads/protobuf" && cd "$BUILD/../downloads/protobuf"   # an empty scratch dir
  curl -fL -C - --connect-timeout 30 -o protobuf-3.21.1.tar.gz \
       https://downloads.videolan.org/pub/contrib/protobuf/protobuf-3.21.1.tar.gz   # or the github.com URL in rules.mak
  shasum -a 512 protobuf-3.21.1.tar.gz   # must equal the line in $SRC/contrib/src/protobuf/SHA512SUMS
  cp protobuf-3.21.1.tar.gz "$SRC/contrib/tarballs/"
  # rerun build.sh: the tools step is a 4 s no-op, and the prebuilt step is skipped because $BUILD/contrib/<triplet> exists
  ```
- (corrected 2026-10-14 after build) **Prebuilt `.pc` files carry the CI's SDK path.** `ncursesw.pc` has
  `Libs: … -isysroot /Applications/Xcode.app/…/SDKs/MacOSX26.2.sdk …`. Xcode 27 only has `MacOSX27.0.sdk`, so linking
  `libncurses_plugin` fails with `clang: warning: no such sysroot directory` and `ld: library 'm' not found`.
  `configure.sh` passes `--enable-ncurses`, so always add **`--disable-ncurses`** to `VLC_CONFIGURE_ARGS` (§4).
  `libchromaprint.pc` has a similar `-F …MacOSX26.2.sdk…` path, but that only causes a linker warning.

Two pitfalls [verified with HTTP checks today]:
1. **The default URL is dead for this triplet.**
   `https://download.videolan.org/pub/videolan/contrib/aarch64-apple-darwin19/vlc-contrib-aarch64-apple-darwin19-latest.tar.zst`
   returns **404**, and so does `…darwin27…`. Without `VLC_PREBUILT_CONTRIBS_URL`, `build.sh` silently falls back
   to building contribs from source (`build.sh:216-218`).
2. **The triplet depends on the kernel version.** Here `uname -r` gives Darwin 27, so the host triplet would be
   `aarch64-apple-darwin27` (`env.build.sh:27-42`). VideoLAN CI forces `VLC_FORCE_KERNELVERSION: 19`
   (`extras/ci/gitlab-ci.yml:71-76`), and artifacts exist only for `aarch64-apple-darwin19`.

What works, mirroring CI (`gitlab-ci.yml:7-9`, `extras/ci/get-contrib-sha.sh`):

```sh
cd "$SRC"
# The contrib SHA = last commit touching contrib inputs. Compute it on the UPSTREAM merge-base, because our own
# commit to extras/package/macosx/package.mak (ARCHITECTURE.md §6.3) would otherwise become "the" SHA.
BASE=$(git merge-base HEAD upstream/master)             # = 4ca4eb0c3e… today
CONTRIB_SHA=$(git rev-list -1 "$BASE" -- extras/tools contrib extras/ci extras/package/macosx)
export VLC_FORCE_KERNELVERSION=19
export VLC_PREBUILT_CONTRIBS_URL="https://artifacts.videolan.org/vlc/macos-arm64/vlc-contrib-aarch64-apple-darwin19-${CONTRIB_SHA}.tar.zst"
curl -sIL "$VLC_PREBUILT_CONTRIBS_URL" | grep -E '^HTTP|content-length'
#   HTTP/2 200 / content-length: 215431447   ← verified for CONTRIB_SHA=4ca4eb0c3e3d1181a48f1e216f4324c6e2670ef7
```

- (corrected 2026-10-14 after build) Used for the first build: the download took 1 m 58 s. The server's
  `Last-Modified` was 2026-10-13 20:06 GMT, so CI re-uploads these artifacts. Retention is still unknown.
- If it returns 404 (CI artifacts are not kept forever [unverified retention]), try the previous upstream commits
  that touched those paths:
  `git rev-list -5 "$BASE" -- extras/tools contrib extras/ci extras/package/macosx`.
- Only as a last resort, build contribs from source with `build.sh -c`.
- Never commit changes under `contrib/`, `extras/tools/` or `extras/ci/`: prebuilt contribs would stop matching.

---

## 4. First build of VLC.app with our module

```sh
mkdir -p "$BUILD" && cd "$BUILD"
export VLC_FORCE_KERNELVERSION=19
export VLC_PREBUILT_CONTRIBS_URL=…                       # from §3
export VLC_CONFIGURE_ARGS="--disable-macosx --disable-ncurses --enable-macosx-redesign"
# optional: --with-macosx-redesign-bundle-id=<id>   (placeholder default until DECISIONS D010)
"$SRC/extras/package/macosx/build.sh" -a aarch64 -j 10
```

(corrected 2026-10-14 after build) `--disable-ncurses` is required with the prebuilt contribs (§3, the
`ncursesw.pc` SDK path). **Stock baseline** (no module; used for the first build and for side-by-side
comparisons): `VLC_CONFIGURE_ARGS="--disable-macosx-ui-shaders --disable-ncurses"` [verified]. The stock build
has the plugins `libmacosx_plugin`, `libmacosx_dialogs_plugin`, `libvout_macosx_plugin` and
`libwindow_macosx_plugin`, 392 plugins in all, `CFBundleIdentifier` `org.videolan.vlc`, and
`LSMinimumSystemVersion` 10.13.0. No plugin links anything under `/opt/homebrew` (`otool -L`).

What `build.sh` does, in order (line numbers in `extras/package/macosx/build.sh`):
1. Sources `env.build.sh`, sets `SDKROOT` and resets `PATH` (11-14, 135-139).
2. Builds `$SRC/extras/tools` (155-163).
3. Sets up contribs in `$BUILD/contrib`: prebuilt download (§3), or a source build (174-226).
4. Runs `$SRC/bootstrap` once, if `configure` is missing (236-241).
5. Runs `extras/package/macosx/configure.sh` (which adds `--enable-macosx` and other defaults, then `"$@"`) with
   `--with-contrib=contrib/aarch64-apple-darwin19 --with-macosx-version-min=10.13 … $VLC_CONFIGURE_ARGS` (262-272).
   - Our later `--disable-macosx` overrides the script's `--enable-macosx`.
   - **Configure only reruns when `configure` is newer than `Makefile`.** To change `VLC_CONFIGURE_ARGS` later,
     run `rm "$BUILD/Makefile"` or `./config.status --recheck`.
6. Runs `make -j10` (283-284). This compiles our plugin, including `swift build` of the `MXRPlugin` product
   (`ARCHITECTURE.md` §7.3).
7. Runs `make VLC.app` (286-287) (`extras/package/macosx/package.mak:25-93`):
   - `make install` into `$BUILD/macos-install`;
   - copies resources (ours via `share/macosx/Contents/Resources`), `Info.plist`, Sparkle, Lua scripts, libraries
     and **all plugins**;
   - runs our `app-bundle-hook.sh` (bundle id and other Info.plist keys);
   - regenerates the plugin cache with `vlc-cache-gen`;
   - signs ad hoc with `codesign.sh -i -`.

Useful `build.sh` flags (`build.sh:20-48`):
- `-d`: no debug (configure `--disable-debug`). The default is a debug build (`-g`, asserts).
- `-x`: `--enable-extra-checks` (CI uses it).
- `-r`: rebuild everything (destructive: cleans tools, contribs and the build).
- `-c`: contribs from source.
- `-i z|n|u`: zip, nightly DMG or release archive.
- `-C <dir>`: build dir instead of `$PWD`.
- `-k <sdk>`: SDK path.

For the redesign, stop after configure/`make` (`tools/build-native.sh` does exactly
that) and let `tools/install-app.sh` run `make VLC.app` and install the single copy.

**Sanity checks** on the installed app:

```sh
APP="/Applications/VLC Redesign.app"
ls "$APP/Contents/Frameworks/plugins/" | grep -E 'macosx'    # only libmacosx_redesign_plugin.dylib
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist"   # 14.0
otool -l "$APP/Contents/Frameworks/plugins/libmacosx_redesign_plugin.dylib" | grep -A3 LC_BUILD_VERSION  # minos 14.0
```

---

## 5. Running

```sh
APP="/Applications/VLC Redesign.app"
open "$APP"                                                  # default: highest-score interface = ours
"$APP/Contents/MacOS/VLC" --intf macosx_redesign -vv         # explicit, verbose log to the terminal
"$APP/Contents/MacOS/VLC" -I mxr -vv ~/Movies/sample.mkv     # shortcut + a file
```

Handy options [verified to exist in `src/libvlc-module.c`]:
- `-vv` / `--verbose=2` (2241): our Swift logs go through `vlc_Log` too (`ARCHITECTURE.md` §5.9).
- `--reset-config` (2869), `--reset-plugins-cache` (2872), `--no-plugins-cache` (2113).
- `--config=<file>` (2878): use a scratch vlcrc.
- `--no-media-library`: start without the ML database.

Where data lives (`src/darwin/dirs.m:191-224`), keyed by the **bundle id** of the app being run. That is why our
app doesn't share data with an installed stock VLC:
- `~/Library/Preferences/<bundle-id>/vlcrc`
- `~/Library/Application Support/<bundle-id>/` (media-library database)
- `~/Library/Caches/<bundle-id>/` (thumbnails, art)

To reset our app completely, quit it and delete those three directories.

`--run-time=<s> --play-and-exit` is a reliable way to get a full start-play-quit log without killing the app;
`make -C "$BUILD/modules" check-macosx-redesign-app` uses it for the installed-app gate. The console logger
(score 10) writes to stderr when the binary is run directly. (Historical: the stock baseline uses
`org.videolan.vlc`, the id of the owner's VLC; it was only ever run as a temporary clone with its own id,
deleted right after. Do not recreate such clones.)

The build-tree launcher `$BUILD/vlc` (a symlink to `bin/vlc-osx-static`, which loads plugins from
`$BUILD/modules` via `VLC_PLUGIN_PATH`, `bin/darwinvlc.m:144-149`) also works. It probably runs with the
**stock** bundle id through the pseudo-bundle (`package.mak:9-15`), so it would share data with an installed VLC
[unverified]. Prefer `VLC.app`.

---

## 6. Fast iteration loop (only our plugin)

See path 2 at the top. With the app closed:

```sh
make -C "$BUILD/modules" -j10 libmacosx_redesign_plugin.la      # SwiftPM incremental + ObjC + link
"$M/tools/dev-sync.sh" "$BUILD" "/Applications/VLC Redesign.app"
"/Applications/VLC Redesign.app/Contents/MacOS/VLC" -I macosx_redesign -vv
```

- If `Makefile.am`/`configure.m4` changed, `make` reruns automake; put configure's tool
  directory first: `export PATH="$(sed -n 's|^PATH: \(.*\)/$|\1|p' "$BUILD/config.log" | paste -sd: -):$PATH"`
  (`install-app.sh` does this itself).
- A no-op `make` does not relink the plugin: `swiftpm-build.sh` copies `libMXRPlugin.a`
  and recompiles the asset catalog only when they changed. SwiftPM itself is always
  invoked (so deleted inputs are seen); the `GEN libMXRPlugin.a` line is expected.
  Measured 2026-10-17: after a rebuilding `make -j8`, the next one left
  `libMXRPlugin.a`, `libmacosx_redesign_plugin.dylib` and `.la` mtimes unchanged
  (1792192822 / 1792192823 / 1792192824), 54 s wall, mostly SwiftPM planning and Qt
  `qml.deps` generation.
- Frameworks used only from Swift (for example Accelerate in `MXRMenuCard.swift`) are
  autolinked from the Swift objects; `otool -L` on the plugin lists
  `Accelerate.framework` without an entry in `Makefile.am`, so a Swift-only framework
  needs no explicit `-framework` flag (the Objective-C sources' frameworks do).
- `dev-sync.sh` signs only the copied dylib, regenerates and signs `plugins.dat` and reseals the
  app without `--deep`, so the installed app stays valid and starts without a stale
  plugin cache.

Variants:
- **UI-only changes:** don't touch VLC at all. Use the Gallery or Xcode Previews (§9) and only sync into
  the installed app for integration checks.
- **After `git merge upstream/master`:** run `tools/install-app.sh "$BUILD"`. If configure inputs changed,
  rerun `$SRC/bootstrap`, then `./config.status --recheck`. Recompute the contrib SHA (§3). A different SHA means
  new contribs: remove `$BUILD/contrib/aarch64-apple-darwin19` and rerun `build.sh`.
- **Swift debug configuration** (slower UI, full stepping):
  `make -C "$BUILD/modules" libmacosx_redesign_plugin.la MXR_SWIFT_CONFIGURATION=debug`.
- **Tests:** `make -C "$BUILD/modules" check-macosx-redesign` needs the built engine (native
  contracts compile against it). Swift-only: `python3 "$M/tools/run-swift-tests.py" "$M" <scratch>`.

---

## 7. Debugging

**LLDB from the terminal.** The ad-hoc signed build has no hardened runtime, so the debugger can attach.

```sh
lldb -- "/Applications/VLC Redesign.app/Contents/MacOS/VLC" -I macosx_redesign -vv
(lldb) breakpoint set -n MXROpenIntf            # pending until the plugin is dlopen()ed: fine
(lldb) breakpoint set -f MXRPlayerBridge.m -l 120
(lldb) run
```

**Xcode.**
- Open `$SRC/modules/gui/macosx_redesign/Package.swift`. Then either use **Debug ▸ Attach to Process by PID or
  Name… ▸ "VLC"** (launch VLC.app first, or tick "wait for launch"), or edit the `MXRPlugin` scheme's
  *Run ▸ Executable* to `/Applications/VLC Redesign.app` [unverified that Xcode offers a custom executable for package schemes].
- Breakpoints in Swift and Objective-C sources resolve once the plugin loads.
- `po`/`expr` on Swift values in the statically linked plugin needs the `.swiftmodule`s (`ARCHITECTURE.md` §7.7):
  `(lldb) settings append target.swift-module-search-paths <SwiftPM bin path>/Modules` [unverified path under
  swiftbuild's `.build/out`].

**Logs.**
- `-vv` in the terminal.
- In Console.app, filter on subsystem `<bundle-id>.ui` (our `os.Logger`).
- `log stream --predicate 'subsystem BEGINSWITH "<bundle-id>"'`.

**Instruments** (performance budgets in `ARCHITECTURE.md` §8). Templates: Time Profiler, SwiftUI, Core Animation,
Energy Log. Profile `VLC.app` directly. Compare with an official nightly VLC.app of the same upstream revision
playing the same file.

**Sanitizers.** These need a separate build dir because configure flags change.

```sh
export VLC_CONFIGURE_ARGS="--disable-macosx --disable-ncurses --enable-macosx-redesign --with-sanitizer=address"   # or thread / undefined
BUILD="$BUILD-asan"   # a separate build dir, then §4
```

- `--with-sanitizer` adds `-fsanitize=…` to C, ObjC and link flags (`configure.ac:1518-1531`). `configure.m4`
  forwards it to `swift build --sanitize=…`.
- Expect noise from the engine under TSan.

**Common failures:**

| Symptom | Cause / fix |
|---|---|
| Contrib download 404, then a multi-hour source build | `VLC_PREBUILT_CONTRIBS_URL` or `VLC_FORCE_KERNELVERSION=19` not exported (§3) |
| `configure: error: metallib was not found, required for macosx-ui-shaders` (stock build only) | Metal toolchain not installed: add `--disable-macosx-ui-shaders` (§1) |
| `ld: library 'm' not found` linking `libncurses_plugin.la`, after `no such sysroot directory: …MacOSX26.2.sdk` | Prebuilt `ncursesw.pc` carries the CI SDK path: add `--disable-ncurses` (§3) |
| `make: *** [.../contrib/tarballs/protobuf-3.21.1.tar.gz] Error 28` (or lua) | Network timeout in `make tools`: fetch the tarball by hand, check its SHA-512, put it in `$SRC/contrib/tarballs/`, rerun (§3) |
| `ld: warning: object file (…libvlccore_objc…/dirs.o) was built for newer 'macOS' version (27.0) than being linked (11.0)` | Upstream Objective-C sources built without a deployment target. Harmless for local builds; not ours to fix |
| `configure: error: --enable-macosx-redesign replaces the stock interface; add --disable-macosx` | Add `--disable-macosx` (`ARCHITECTURE.md` §1.3) |
| "Class VLCPlayerController is implemented in both …" | The stock `libmacosx_plugin.dylib` is in the plugins dir. Remove it and rebuild with `--disable-macosx` |
| Modules linked against `/opt/homebrew/...` (`otool -L`) | Homebrew leaked in through `VLC_PATH` / pkg-config (§1). Rebuild without it |
| `ld: warning: object file … built for newer macOS version (14.0) than being linked (11.0)` | `-mmacosx-version-min=$(MXR_MIN_MACOS)` missing from the plugin's `LDFLAGS` |
| `fatalError: unable to find bundle named …` | Code used `Bundle.module`. Use `MXRResources` (`ARCHITECTURE.md` §7.6) |
| `cp: …/share/macosx/: No such file or directory` in `make VLC.app` | Our resource install hook didn't run (`install-macosx-redesign-resources`) |

---

## 8. Code signing and notarization (overview)

Local builds are signed ad hoc by `make VLC.app` (`package.mak:92-93` → `codesign.sh -i -`). For distribution
(D012: own Developer ID, bundle id and update feed):

1. Build a release: `build.sh -d` (no debug). Use `-i u` for the stripped release archive flow
   (`build.sh:289-313`), or `make package-macosx` for a DMG.
2. Sign with hardened runtime, using `extras/package/macosx/codesign.sh`:
   `cd "$BUILD" && "$SRC/extras/package/macosx/codesign.sh" -i "Developer ID Application: <Name> (<TEAMID>)" -r -g`.
   - `-r` adds `--options runtime --entitlements vlc-hardening.entitlements`
     (`allow-jit`, `disable-library-validation`, `audio-input`, `camera`, `apple-events`).
   - `-g` checks with `spctl`.
   - It signs Sparkle, Breakpad, every plugin, `plugins.dat`, the libraries, the Lua files, `vlc-preparser` and the
     app, then verifies (`codesign.sh:105-185`).
   - Our resource bundles are sealed as resources by the app signature; nothing extra is needed [unverified].
3. Notarize and staple:
   ```sh
   ditto -c -k --keepParent VLC.app VLC.zip
   xcrun notarytool submit VLC.zip --keychain-profile "<profile>" --wait
   xcrun stapler staple VLC.app
   # or notarize/staple the DMG produced by `make package-macosx`
   ```
4. Updates: our Sparkle appcast and EdDSA key go into `SUFeedURL`/`SUPublicEDKey` through `app-bundle-hook.sh`.
   Never ship VideoLAN's feed or keys (`share/Info.plist.in:60-65`).
5. The product name and icon need a decision first (D010). GPL obligations: publish the source of the exact build.

---

## 9. Gallery app and previews (no VLC build)

All UI work starts here (WORKFLOW.md step 2). The `MXRGallery` executable and the Xcode Previews link `MXRUI` with
`MXRMockBackend` only. `MXRBridgeAPI`, `MXRVLCBackend` and `module/` are not compiled, so no contribs, configure
or VLC headers are involved.

```sh
cd "$SRC/modules/gui/macosx_redesign"
swift build --product MXRGallery                 # first build ~1 min, then seconds [estimate]
swift run MXRGallery                             # opens the component/screen gallery with mock data
swift run MXRGallery --entry S01.App/default --snapshot-window /tmp/gallery-window.png
swift run mxr-snapshot render --id S01.App/default --scale 2 --out /tmp/S01.png
swift run mxr-snapshot check --id S01.App/default --out-dir /tmp/S01-comparison
swift test --filter <Suite>                      # targeted; the full gate is tools/run-swift-tests.py
open Package.swift                               # Xcode: scheme MXRGallery ▸ Run, or the canvas for #Preview
```

- Verified on this machine with the implemented package [verified]: Swift 6.4's SwiftPM (default build system
  "swiftbuild") builds static libraries and executables, compiles `.xcassets` into the resource bundle, and handles
  `@Observable`.
- The Gallery is a plain executable, not an `.app`. It must call `NSApp.setActivationPolicy(.regular)` itself to
  get a Dock icon and the menu bar. Running from Xcode works the same way.
- `--entry` selects a Gallery entry; `--snapshot-window` captures the Gallery window,
  including its inspector, then quits. `mxr-snapshot render/check` renders only the
  chosen entry at its catalog size and scale, using ImageRenderer or NSView caching,
  and compares it with the corresponding Figma render. Use
  `swift run mxr-snapshot list` for valid entry IDs and `help` for all commands. Offscreen material capture
  does not establish WindowServer blur equivalence; see `CODEX_STATUS.md`.
- The settings screens use the checked-in `config-schema.snapshot.json` as their mock schema
  (`ARCHITECTURE.md` §5.2), so all 13 categories can be built and reviewed without VLC.
- Disk: `.build/` inside the package directory (git-ignored), about 100–500 MB [estimate]. To keep the source tree
  clean, pass `--scratch-path "$SRC/../build/gallery"`.

---

## 10. Not yet verified

The retained Phase 0 checklist distinguishes implemented build checks from remaining
distribution/debugging questions:
1. ~~The `m4_include`/`Makefile.am` glue, the libtool flags (`-force_load`,
   `-mmacosx-version-min`), and the resource install hook.~~ Verified in the isolated
   native module/app build and artifact manifest (`CODEX_STATUS.md`).
2. ~~Build and disk times, against the estimates in §0.~~ Done for the stock build (corrected 2026-10-14 after
   build; §0 and `NOTES.md`).
3. ~~That the `make tools` step needs no extra brew packages with prebuilt contribs.~~ Confirmed (corrected
   2026-10-14 after build): it builds `luac` and `protoc` from downloaded tarballs, with no Homebrew (§3).
4. The bundle id of `bin/vlc-osx-static` dev runs (§5).
5. Xcode custom-executable debugging of package schemes and Swift expression evaluation (§7).
6. Notarization of a bundle containing SwiftPM resource bundles (§8).
7. How long `artifacts.videolan.org` keeps contrib artifacts (§3).

## Installing the app (single copy)

See path 1 at the top: `tools/install-app.sh [build-dir]` is the only supported way. The
redesign's icon (flat Figma cone on dark chrome) is
`modules/gui/macosx_redesign/Resources/AppIcon.icns`, generated by `tools/gen-app-icon.swift`
and copied into the bundle by `tools/app-bundle-hook.sh`.
