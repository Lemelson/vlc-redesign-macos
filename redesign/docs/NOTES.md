# Notes

Non-obvious facts learned while working (VLC API quirks, build tricks, gotchas). Add new entries at the top with a date.

## 2026-10-14: Stock VLC.app baseline build (task A1)

This was a stock build of `main` (upstream base `4ca4eb0c3e`; the `macosx_redesign` module is not hooked in yet).
Command: `extras/package/macosx/build.sh -a aarch64 -j 10` in `../build/arm64`, with
`VLC_FORCE_KERNELVERSION=19`, the artifacts URL from `BUILD.md` §3 and
`VLC_CONFIGURE_ARGS="--disable-macosx-ui-shaders --disable-ncurses"`. Machine: 10-core arm64, macOS 27.2,
Xcode 27, network through the owner's VPN. Logs (outside the repo): `../build/logs/`.
`BUILD.md` §0, §1, §3, §4, §5, §7 and §10 were corrected from this run.

**Times and disk (measured):**

| Step | Wall time | Disk |
|---|---|---|
| `extras/tools` (15 tools, including ant) | 19 m 05 s (4–6 min of it downloads) | 1.4 GB in `$SRC/extras/tools` (`build/` 139 MB, the rest unpacked sources and objects) |
| Prebuilt contribs (215,431,447 bytes) | 1 m 58 s download, about 5 s unpack | 1.0 GB unpacked. The tarball (205 MB) was deleted afterwards |
| `make tools` (`luac`, `protoc`) | about 40 s plus downloads | 56 MB build dir + 10 MB tarballs in `$SRC/contrib/tarballs/` |
| `./bootstrap`, configure | 17 s, 52 s (30 s on a rerun) | |
| `make -j10` | about 5 m 10 s (2,521 compiles, 707 links; split over two runs, see gotcha 2) | `modules/` 923 MB |
| `make VLC.app` | 2 m 03 s | `macos-install` 157 MB + `VLC.app` 157 MB, 392 plugins |
| **Total** | about 30 min of work, about 45 min wall time with the network failures | `$BUILD` 2.3 GB + `extras/tools` 1.4 GB |

- No-op `make -j10` in `$BUILD`: 12.7 s. `make -C modules <plugin>.la` when it is up to date: 2.5 s.
- A debug build is small because DWARF stays in the `.o` files on macOS. No dSYMs are made.

**Gotchas:**
1. **Metal.** Xcode 27 has a `metal` stub but no `metallib` (MetalToolchain component "uninstalled"). With
   `--enable-macosx` (the `configure.sh` default), configure fails: "metallib was not found, required for
   macosx-ui-shaders". The stock baseline needs `--disable-macosx-ui-shaders`. This doesn't matter with
   `--disable-macosx`.
2. **ncurses.** The prebuilt `ncursesw.pc` contains `-isysroot …/MacOSX26.2.sdk` (the CI's Xcode). Here only
   `MacOSX27.0.sdk` exists, so linking `libncurses_plugin.la` fails: `no such sysroot directory`, then
   `ld: library 'm' not found`. Fix: `--disable-ncurses`. **This also applies to our build**, because `configure.sh`
   passes `--enable-ncurses`. To reconfigure, run `rm $BUILD/Makefile` and then build.sh again. `config.h` was
   unchanged, so make carried on where it stopped and did not start over.
3. **Network.** `downloads.videolan.org` takes about 20 s per request and 404s for meson 1.12.0 and the Kitware
   ninja tarball, so the rules fall back to github.com and lua.org. Through the VPN those connects timed out
   repeatedly. The protobuf download failed after `curl --retry 3`, and build.sh stopped in `make tools` (rc 2).
   The fix is a manual fetch into a scratch directory: check it against `contrib/src/protobuf/SHA512SUMS`, copy it
   to `$SRC/contrib/tarballs/` and rerun. The rerun resumes: the tools step is a 4 s no-op, and the prebuilt step is
   skipped because `$BUILD/contrib/aarch64-apple-darwin19` exists.
4. **Harmless warnings.**
   - `ld: warning: object file (…libvlccore_objc…/dirs.o) was built for newer 'macOS' version (27.0) than being
     linked (11.0)`: upstream ObjC sources are compiled without a deployment target. Our plugin must pass
     `-mmacosx-version-min` explicitly.
   - `ld: warning: search path …MacOSX26.2.sdk/…/Accelerate.framework not found`, from `libchromaprint.pc`.
   - `ninja: error: Could not initialize jobserver` in `extras/tools`.
5. The prebuilt artifact's `Last-Modified` header is 2026-10-13 20:06 GMT, so CI re-uploads it. Retention is
   still unknown.
6. **Do not delete `extras/tools/<tool>/` source dirs to save space.** Their make targets depend on the unpacked
   dir, so the next build.sh would re-unpack and rebuild those tools (about 19 min).

**Smoke test (passed):**
- **Bundle id clash.** `/Applications/VLC.app` is VLC 3.0.21 with bundle id `org.videolan.vlc`, the same id as
  the stock build. Running the stock build as built would therefore use the installed VLC's vlcrc, defaults
  plist and data directories.
- **What we ran instead.** An APFS clone (`cp -cR`) with `CFBundleIdentifier` set to
  `org.videolan.vlc.mxr-stocktest` and re-signed ad hoc (`codesign --force -s -`; `--verify --strict` OK). The
  clone was deleted afterwards, and the installed VLC's files kept their 1 October mtimes.
- **Command.** `VLC --verbose=2 --no-media-library --run-time=6 --play-and-exit E01.mp4 E02.mp4 > log 2>&1`. It
  quit on its own with exit status 0, before the 30 s watchdog.
- **What the log showed:**
  - interfaces: `using interface module "hotkeys"`, then "macosx" ("Finished loading macosx interface");
  - video window: `using vout window module "macosx"` and "Opening video window";
  - video: `using vout display module "samplebufferdisplay"`, video decoder `videotoolbox`;
  - audio: `faad` decoding to `auhal`;
  - subtitles: `autodetected subtitle: …/Test Show S01E01.srt` and "loaded 5 subtitles" (`subsdec` plus the
    `freetype` text renderer);
  - playback: "Received first picture", "EOF reached", then the second item played with its own `.srt`;
  - shutdown: "exiting", then every module was removed cleanly.
- **Errors in the log**, all expected:
  - 23× `services discovery error: cannot join multicast group` (SAP discovery on port 9875 binding IPv6 multicast groups to lo0 and other interfaces; harmless);
  - 1× `macosx interface error: Cannot set size for nonexisting window` (stock behaviour).
- **Leftover test data** (outside the build dir, so it was not deleted; safe to remove):
  - `~/Library/Preferences/org.videolan.vlc.mxr-stocktest/`;
  - `~/Library/Preferences/org.videolan.vlc.mxr-stocktest.plist`;
  - `~/Library/Caches/org.videolan.vlc.mxr-stocktest/`.

**Test media** (for later tasks), in `../build/media/`:
- `Test Show S01E01.mp4` and `Test Show S01E02.mp4`, about 21 MB each.
- Each is 60 s of 1920×1080 at 30 fps: `testsrc2` as H.264 (E02 hue-shifted), with a 440 Hz (E01) or 660 Hz (E02)
  sine as AAC 48 kHz, and the `title` tag set.
- Each has a matching `.srt` with 5 or 4 cues; E01 has a two-line cue and an `<i>` cue.
- Made with Homebrew ffmpeg. That is fine for test media; ffmpeg was never on the build `PATH`.

## 2026-10-14: Core API and mock backend (MXRCore, MXRMockBackend)

Guide for UI code: `CORE_API.md`. Code: `Sources/MXRCore/{Backends,Models,Stores,Values,App,Settings}`, `Sources/MXRMockBackend`.

- **Events are payload-free.** `PlayerEvent.volume` etc. only say "re-read this"; models then read the backend's
  cached properties. Listeners are registered with an owner (`EventChannel`) and drop out when the owner dies, so
  models never unregister in `deinit` (nonisolated in Swift 6; `isolated deinit` needs a newer runtime than macOS 14).
- **First frame is populated.** Async library queries would leave the first SwiftUI frame (and every snapshot) empty.
  `LibraryBackend.cachedPage/cachedHomeSections/cachedBreadcrumb/cachedBookmarks` are synchronous fast paths (default
  nil) that `LibraryModel`/`BookmarksModel` apply before the async refresh; the mock answers all of them.
- **Clock.** `TimerPoint.hostTime` is in the `CACurrentMediaTime()` base; nil disables interpolation (paused, frozen
  mock). `PlaybackClock` wakes itself on second boundaries while running so `displaySecond` flips on time between
  VLC's 250 ms points; tests pass `schedulesTicks: false` and inject `now`.
- **VLC 4 dropped `freetype-fontsize`/`freetype-rel-fontsize`** (obsolete in `modules/text_renderer/freetype`). Relative
  subtitle size is `sub-text-scale` (10–500 %); the design's "Pixels" mode has no engine option and maps to the app option
  `macosx-redesign-sub-pixel-size` (the bridge must convert). Also `input-fast-seek` is the inverse of "Seek precisely"
  (`inverted: true` rows in the settings map).
- **Figma volume cone:** every player frame uses the `volume` variant `Property 1=50%`, i.e. 100 % of a 0–200 % scale,
  which matches the "100 %" tooltip. The mock starts at volume 1.0.
- **Figma is internally inconsistent** in a few texts (queue rows "The Wand_S01E11.mp4" vs library "The_Wand_S01E11.mp4";
  "4 items - 2h 3m" for ~95 min; Playlists panel vs Home playlists). The mock follows the panel each screen comes from and
  computes sums; output devices are the Figma "Speakers"/"Headphones" rather than real device names.
- **Settings map rows marked "verify"** (and app options `macosx-redesign-*`) must be declared/confirmed by the VLC
  module; the D013 drift check should list unknown names.

## 2026-10-14: Visual-verification tooling (mxr-snapshot, Gallery)

How to use it: `WORKFLOW.md`, step 3 "Compare to Figma". Code: `Sources/MXRGalleryCatalog/GalleryCatalog.swift`
(renderer, Figma index and crop, comparator), `Sources/MXRSnapshot`, `Sources/MXRGallery`.

- **Crop math.** A frame render covers the frame's `absoluteRenderBounds` (frame plus shadow bleed), so a
  node's crop is `(node.absoluteBoundingBox − frame.absoluteRenderBounds.origin) × 2`; `INDEX.md` maps
  frames to render files. Checked pixel-for-pixel against a Pillow crop of `play.png` (max delta 1, from
  premultiplied alpha).
- **Render geometry: the scale is exactly 2, the origin can be fractional.** Every render is
  `ceil(renderBounds × 2)` px with pixel (0, 0) at the exact, possibly fractional, render-bounds origin.
  The Onboarding frames (origin x.2 / y.8, bounds 1113.6×782.6, PNG 2228×1566) and Components/Designs
  have such origins. Measured edges in `Onboarding-1.png` sit at 701.63 / 901.63 / 1879.63 / 2079.62 px,
  matching origin + 2.0× exactly (not the PNG/bounds ratio 2.0007, and not a snapped origin). Crops that
  start between pixels are shifted bilinearly; rounding the origin clipped content by up to ½ px.
- **Neighbouring tokens are 2/255 apart.** `bgA3` #1B1B1B vs `bgA4` #191919 differ by 2; other dark
  surfaces by 3–5. Flat areas in the renders are exact token values (`Onboarding.png` is 90 % #0E0E0E
  `bgB1`), and Figma's noise is ±1, so the flat-color test counts deltas of 2 and up (it was > 6, which
  passed a panel painted with the neighbouring token).
- **Core Text font smoothing makes text heavier than Figma.** Light text gets ~30 % more ink (Inter 15
  #8F8F8F: 241k vs Figma's 194k alpha). Setting `AppleFontSmoothing = 0` in the argument domain gives
  192k. Core Text reads the preference once, so `GalleryRenderer.matchFigmaTextRasterization()` must
  run before any text is drawn. Dark text gets less dilation than light text. SwiftUI ignores
  `CGContext.setShouldSmoothFonts`, and `ImageRenderer.render(rasterizationScale:)` into our own
  context placed text 1 px lower than `ImageRenderer.cgImage`, so the tools use `cgImage`.
- **Debug-build pixel loops.** SwiftPM builds the tools in debug. Loops written with generic `abs`/`max`
  and range iterators ran a 4K comparison in ~15 s; `while` loops on raw pointers with `&+` run it in
  ~1.5 s. `@_optimize(speed)` has no effect at `-Onone`.
- **Figma quirk: the pause glyph has two colors.** In `play` › `type=pause` (848:1713), the left bar is
  `Dark/BG/B1` #0E0E0E and the right bar `Dark/FG/B1` #161616. A single-tint icon differs by 8/255 on
  the left bar, which `mxr-snapshot` reports as a flat-color difference.
- **SwiftPM executables have no bundle id**, so desktop automation can't target `MXRGallery`, and the
  shell has no screen-recording permission. `MXRGallery --snapshot-window out.png` draws the window with
  `cacheDisplay` and quits; `--entry`, `--mode` and `--measure` set up what it shows.

## 2026-10-14: Design system (MXRDesign): tokens, fonts, icons

**Regenerating** (Python 3 stdlib, run from the repo root; both outputs are committed and deterministic):

- Tokens: `python3 -I modules/gui/macosx_redesign/tools/gen-tokens.py` reads
  `redesign/design/tokens/{colors,typography,metrics}.json` and writes
  `Sources/MXRDesign/Generated/Tokens.swift`. Use `--check` in CI (exit 1 if stale). Raw colors get
  semantic names from `RAW_COLOR_NAMES` in the script; a new raw color stops the run until it is named.
- Icons: `python3 -I modules/gui/macosx_redesign/tools/gen-icons.py` reads
  `redesign/design/figma/icons-svg/` and rewrites `Sources/MXRDesign/Resources/Icons.xcassets` plus
  `Sources/MXRDesign/Generated/Icons.swift` (`--check` too). Each SVG is split into single-color layers
  in document order. Each layer becomes a vector template imageset, and `MXRIcon` stacks and tints the
  layers by role: FG/A2 → `tint`, Accent/Main → `accentMain`, Accent/DIm → `accentDim`,
  `#303030` → `thumbPlaceholder`, `#373737` → `dividerBright`. An unknown color fails the run.

**Facts learned:**

- **Figma renders with Inter 3.19 metrics, not Inter 4.x.** Hug-width TEXT nodes: 618 of 626 match
  `ceil(advance)` with 3.19 but only 356 of 626 with 4.1 (the `1` digit is narrower in 4.x). Bundled:
  Inter 3.19 Desktop OTF Light/Regular/Medium/SemiBold (rsms/inter v3.19 release) and DM Mono Regular
  (google/fonts), with `Inter-OFL.txt` and `DMMono-OFL.txt`. Bold is not bundled: only `hdrBadge` uses
  700, and that text is part of the HDR icon artwork. SwiftUI text widths come within 1 pt of Figma for
  634 of 635 samples.
- Fonts are built from the bundled files by URL (`CTFontManagerCreateFontDescriptorsFromURL`), so a
  user-installed Inter 4 can never replace them. They are also registered for the process, so
  `Font.custom("Inter", …)` and `NSFont(name:)` work after `DesignSystem.bootstrap()`.
- **Line height.** SwiftUI and AppKit lay out each line as `round(ascent) + round(descent) + round(leading)`,
  which equals `NSLayoutManager.defaultLineHeight`. For Inter 16 that is 20, while Figma uses 19.36.
  `.mxrTextStyle` computes `lineSpacing` and half-leading padding from that rendered height, so fixed
  Figma line heights (24.5, 28, 42) come out exact. "Auto" line heights stay 0.06 to 0.64 pt taller per
  line; fixing that would need private API. `TextStyle.attributes()` places AppKit text exactly like
  SwiftUI does (checked with ink bounds).
- **Never call `Bundle.module` in shared code.** It calls `fatalError` inside VLC. Use
  `DesignSystem.resourceBundle`, which returns nil when the bundle is missing. It searches, in order:
  `MXR_RESOURCES_PATH`, `PACKAGE_RESOURCE_BUNDLE_PATH`, the main bundle, the plugin dylib's
  `../../Resources`, and the xctest products directory. SwiftPM also generates
  `GeneratedAssetSymbols.swift` for the asset catalog (internal `ImageResource` members); this is harmless.
- **`check` icon.** The Figma default variant (494:2400) is an *empty frame* (FRAME 494:2401 has no
  children). It is the trailing slot of every unchecked menu and dropdown row (75 instances), so ICONS.md
  calling it a missing "plain glyph" is wrong. `gen-icons.py` (`EMPTY_VARIANTS`) gives `.check` an empty
  default variant, as in Figma, instead of drawing a glyph. A row is therefore
  `MXRIcon(.check, state: isOn ? .active : .default)`: `.active` is the accent check, `.selected` the
  FG/A2 check. No glyph was drawn, because a visible default check would show in unchecked rows.
- **`MXRIcon` tint.** `tint: nil` leaves the gray layers without a `foregroundStyle`, so they take the
  style set on the icon or an ancestor. Writing `.foregroundStyle(.foreground)` on the layer instead
  resolves to the default label color, not the parent's style. `tint:` takes any `ShapeStyle`. These
  cases are shown in the "Tinting" section of `D.Icons/mono` (checked pixel by pixel at 2×).
- **Icon variants with special handling:**
  - `album-6206-13653` and `subtitle-2461-9663` have the same Figma properties as `album` and
    `subtitle`, but they are the Accent/DIm artwork, so they are filed as the two-tone variants.
  - `sort-active` and `view-active` have a 26×25 viewBox because the accent dot overflows the 24 frame.
    `MXRIcon` draws them from the top-left without clipping, like Figma. `nsImage` keeps the overflow
    and sets `alignmentRect`.
- **Accents.** Orange uses the Figma styles. For the other accents:
  - In the dark theme, `accentMain` and `accentLogo` are the swatch.
  - `bgAccentBright` is `accentMain` at 0.24 opacity.
  - `accentRing` is `accentMain` at 0.30. This also holds for orange (node 1902:4003).
  - Every other shade keeps the swatch's hue and scales its HSB saturation and brightness by orange's
    ratio (named style / orange swatch #D37918) for that token and theme. That covers dark `accentDim`,
    `accentBright` and `bgAccentDark`, and *all* light shades. For example, light `accentMain` is
    brightened the way `Light/Accent/Main` #E8851A brightens orange: red becomes #F75837 and teal
    #1ABBE8. The light values are provisional, because no light Figma frame shows a non-orange accent.
    Before this change, light non-orange accents kept the dark swatch while orange used #E8851A.
  - `Theme.Accent.swatch` is the dark-theme value as Figma shows it. Themed UI uses `Theme.Color.accentMain`.

  Checked against Onboarding-6 (teal): the cone, the play button, the seek fill and the playhead all
  take the accent, and the volume gradient does not.
- **Shadows.** For a SwiftUI shadow radius, use Figma blur / 2 (`Theme.Shadow.radius`). SwiftUI has no
  spread, so `.mxrShadow` ignores it.
- **Light palette bug (open).** Figma's Light/FG/1 and Light/FG/2 equal the dark values (#EAEAEA and
  #C6C6C6), so `fg1`/`fg2` text is invisible in the light theme (visible in `D.Colors/light`). The
  tokens are unchanged because they are Figma data; this needs a decision.
- Specimen pages: `D.Colors/dark`, `D.Colors/light`, `D.Accents/default`, `D.Typography/default`,
  `D.Icons/mono` and `D.Icons/twoTone`. `DesignThemeGallery` is the catalog's `GalleryThemeProvider`
  (accents through `.mxrAccent`).
