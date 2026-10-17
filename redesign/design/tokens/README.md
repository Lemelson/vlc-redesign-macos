# Design tokens

Machine-readable tokens for the native macOS VLC interface. Every value was extracted from
`../figma/figma_file.json` (Figma REST dump of "VLC Redesign (Community)", version
2409521707817118521). The design is **VLC Redesign by Juxtopposed**, Figma community file
https://www.figma.com/community/file/1691465999134370980, licensed **CC BY 4.0**, so credit the
designer in the app's About/credits.

All sizes are Figma px at 1x, which map 1:1 to macOS points. The player mock-ups are
1920×1080 windows, and the PNG renders in `../figma/renders/` are 2×.

The extraction scripts (Python stdlib) are not part of the repo. To check a value, open the
node id listed next to it in `figma_file.json`.

## Files

### `colors.json`

- **`dark` / `light`**: one entry per Figma paint style (25 per theme). The key is a
  camelCase form of the style path, for example `Dark/BG/Accent Bright` → `bgAccentBright`
  and `Dark/Accent/DIm` → `accentDim`. Each entry has `hex`, `alpha`, `figmaStyle`,
  `styleId`, `usageCount`, `resolvedFrom` and `exampleNodes`.
  - `resolvedFrom: "nodes"` means the value was read from the fills or strokes of the nodes
    that reference the style. Each style resolved to exactly one value.
  - Some styles are never referenced by a node, so `figma_file.json` cannot resolve them,
    because the REST `/files` response does not include style values. For those entries,
    `resolvedFrom` names `../figma/palette/tokens.json`, a style dump made by another fork.
    The affected styles are:
    - Dark: `accentBright`, `bgB2Transparent`.
    - Light: `accentBright`, `accentDim`, `bgA1`–`bgA4`, `bgAccentDark`, `bgB1`, `fg1`,
      `fg2`, `fgA1`, `fgA4`, `fgB1`.
  - Where the nodes and `palette/tokens.json` overlap, they agree on every value
    (`meta.issues` is empty).
- **`accentSwatches`**: the 9 user-selectable accents in display order: orange (default),
  red, olive, green, teal, blue, purple, pink, gray.
  - Each swatch was checked against the onboarding frame that uses it and against the
    swatch node in Settings > General.
  - Only orange has a full set of named shades. The other accents follow a rule visible in
    the Figma frames, documented in `derivationRule`: the seek fill is the accent at 24 %
    opacity, the selected ring is the accent at 30 %, and glyphs on the accent use
    `fgB1 #161616`.
- **`rawColors`**: recurring colors that are not bound to a style, for example the icon
  button hover `#FFFFFF` at 6 %, the thumbnail placeholder `#303030` and the subtitle-cue
  blocks `#FFFFFF` at 14 %.
- **`gradients`**: the volume cone gradient (`#95D318` → `#B2A918` → `#D37918` → `#FF3737`,
  with a 20 % black overlay) and the "System" theme tile split.

Known problems in the source, which are also recorded in the file:

- Light `fg1` and `fg2` are copies of the dark values (near-white).
- Only 13 of the 25 Light styles are used, all of them in `Player - Light`, and that frame
  still uses Dark styles in places. Treat the light palette as provisional.
- `accentBright` and `bgB2Transparent` are defined but unused.
- `bgAccentDark` is mostly used for slider tick marks drawn on the filled part of a slider.

### `typography.json`

The file defines no text styles, so this file lists every distinct (family, weight, size,
line height, letter spacing) combination found on the TEXT nodes.

- There are 21 real styles. Each has a proposed `name` and `role`, plus `usageCount`,
  `exampleNodes`, `sampleText` and the colors it is drawn in.
- Fonts are **Inter** (300/400/500/600/700) and **DM Mono** 400, which is used for the key
  fields in the Keyboard Shortcuts dialog. Bundle both fonts; they are OFL-licensed.
- Line height `auto` is Figma's intrinsic line height, about 1.21 em for Inter (for example
  14 → 16.94). Letter spacing is 0 everywhere.
- `excluded` lists combinations that are not real styles: text in the 0.55× player preview
  inside onboarding (sizes 7.7, 8.8, 8.25 and 4.4) and the 700 px canvas labels.
- `inlineOverrides` lists the mixed-style runs, such as the SemiBold time in the resume toast
  and the dimmed "(optional)" and "%" suffixes.

### `metrics.json`

- **`radius`**: the scale (2, 3, 4, 6, 10, 14, 16, 19, 20), which UI parts use each value,
  and the frequency of each value across the whole file.
- **`spacing`**: frequency of auto-layout gaps and paddings. Padding is listed as
  `[top, right, bottom, left]`.
- **`stroke`**: dividers (1 px `dividerDim`), the 1 px top border on the control bar, icon
  strokes (1.5 px default, 2 px active), dash patterns, and the 20 px window frame stroke.
- **`effects`**:
  - Background blur 50 (style "bg blur").
  - The menu and dialog shadow, style "bg blur + shadow": y 8, blur 15, black at 46 %.
  - The shadows for the mini player, onboarding window, dropdown list, preset list and
    keycaps, the album-art glow, and the 20 px layer blur on the album backdrop.
- **Component metrics, read from the named node**: `window`, `controlBar`, `volume` (fill
  width for each step from 0 to 200 %), `sidePanels` (400 px wide panels; placement 20 px
  from the right, 20 px above the control bar and 20 px below the top bar), `library`,
  `miniplayer`, `menus`, `controls` (toggle, segmented, dropdown, stacked choice, buttons)
  and `dialogs` (settings, Add Subtitles, Open Network Stream, New Playlist, onboarding,
  resume toast). Each entry has `node`, `w`, `h` and, where they apply, `radius`, `gap` and
  `padding`.
- **`standardHeights` / `standardWidths`**: a quick reference. Examples: top bar 40, control
  bar 54, control items 28, icon button 30×32, tab strip 50, list row 32, menu row 48,
  dropdown 48, dialog header 50 or 96, dialog footer 72, button 100×32.

## How values were derived

1. Paint styles were resolved through the node `styles` map: style id → node paints → hex
   and alpha. Only visible SOLID paints count.
2. Text styles were computed by grouping the `style` object of every TEXT node.
3. Each named metric was read from the `absoluteBoundingBox`, `cornerRadius`,
   `rectangleCornerRadii`, `itemSpacing`, `padding*`, `strokes` and `effects` of the cited
   node. Distributions count every node in the document.
4. Where the specs disagree with Figma (`../spec/spec-part1.md` and `spec-part2.md` measured
   compressed video frames), these files follow Figma. For example, the spec's "52 px"
   control bar is 54 in Figma, and its 38 px top bar is 40.

## Proposed Swift naming

This is a naming scheme only, not code. Keep a single `Theme` namespace and mirror the JSON
keys so a token can be traced back to a file by searching for its name.

- **Colors**: `Theme.Color.<key>`, using the `colors.json` key unchanged. Resolve each color
  from the active appearance (dark or light) and accent.
  - Examples: `Theme.Color.fgA2`, `Theme.Color.bgB1Transparent`, `Theme.Color.dividerDim`.
  - Accent-dependent colors read from `Theme.Accent.current`: `Theme.Color.accentMain`,
    `accentDim`, `accentBright`, `accentLogo`, `bgAccentBright`, `bgAccentDark`.
  - Accent options are `Theme.Accent.orange` … `Theme.Accent.gray`.
  - Raw colors get semantic names, for example `Theme.Color.iconHover` (`#FFFFFF` at 6 %),
    `Theme.Color.thumbPlaceholder`, `Theme.Color.subtitleCue`, `Theme.Color.volumeBody`.
  - The volume gradient is `Theme.Gradient.volumeCone`.
- **Typography**: `Theme.Font.<name>`, using the `typography.json` `name`.
  - Examples: `Theme.Font.body` (Inter 400 14), `Theme.Font.caption` (Inter 400 12),
    `Theme.Font.bodyLarge` (Inter 400 16), `Theme.Font.sectionHeader` (Inter 500 16),
    `Theme.Font.time` (Inter 400 15, tabular figures), `Theme.Font.button` (Inter 600 14),
    `Theme.Font.buttonLarge`, `Theme.Font.keycap` (DM Mono 400 14),
    `Theme.Font.welcomeTitle`.
  - Store the line height next to the font, for example `Theme.Font.body.lineHeight`, so that
    rows reproduce Figma's text box heights.
- **Metrics**: `Theme.Metric.<camelCase>`.
  - Heights and widths: `Theme.Metric.topBarHeight` (40), `controlBarHeight` (54),
    `controlItemHeight` (28), `sidePanelWidth` (400), `panelInset` (20), `tabStripHeight`
    (50), `listRowHeight` (32), `menuRowHeight` (48), `libraryRailWidth` (50),
    `libraryPanelWidth` (377), `settingsWindowSize` (1048×865), `dialogFooterHeight` (72).
  - Radii: `Theme.Radius.xs/sm/md/lg/xl/xxl` (2, 3, 4, 6, 10, 14), plus
    `Theme.Radius.toast` (16), `videoFrame` (19) and `albumArt` (20).
  - Spacing: `Theme.Spacing.gap(4|5|8|10|12|14|20)` and component paddings named after the
    component, for example `Theme.Spacing.menuRowPadding` = (2, 14, 2, 14).
  - Strokes: `Theme.Stroke.hairline` (1), `icon` (1.5) and `iconActive` (2).
- **Effects**: `Theme.Effect.backgroundBlur` (radius 50, used with an `NSVisualEffectView`
  or a custom blur), `Theme.Effect.menuShadow`, `miniplayerShadow`, `onboardingShadow`,
  `dropdownShadow` and `keycapShadow`.
- **Icons**: `Theme.Icon.<name>(state:, twoTone:)`, mapped to the files listed in
  `../figma/ICONS.md`.
