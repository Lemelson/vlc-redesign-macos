# Design system components

Reusable SwiftUI/AppKit components in `modules/gui/macosx_redesign/Sources/MXRDesign/`.
Tokens (`Theme.*`) are described in `Theme/Theme.swift` and generated from
`redesign/design/tokens/`; this file covers the components other views build on.

## Popups: menus, context menus, dropdowns (D024, D025, D026)

Folder: `Sources/MXRDesign/Popup/`. One presentation for every in-window menu: a borderless,
non-activating panel (child window of the anchor's window) that draws the Figma card. No
`NSPopover`, no arrow, no native `NSMenu` (the native menu is only the macOS menu bar).

Behaviour every popup gets for free:

- **Motion (D024):** fade + 6 pt slide from the anchor, 0.15 s ease-out in, 0.1 s fade out; none
  under Reduce Motion (`Theme.Popup`).
- **Dismissal (D024):** Esc, a click outside (the click is consumed, so it never also toggles
  playback; a secondary click outside may open the next context menu), app deactivation, the
  anchor window moving, resizing, closing or changing fullscreen state. Choosing an item closes
  the menu, then runs the action.
- **Keyboard (menus):** ↑ ↓ Home End move, → or Return opens a submenu, ← closes it, Return or
  Space choose, typing selects by title, ⌘-shortcuts close the menu and run from the menu bar.
  The root panel takes the keyboard while open; the player's hotkeys do not fire underneath.
- **Submenus:** open on hover after `Theme.Popup.submenuHoverDelay` (0.2 s), beside the row with
  the Figma 11 pt gap, first row aligned with the parent row; moving diagonally into an open
  submenu keeps it. They flip to the left near the screen edge.
- **Placement:** always on the anchor's screen (multi-screen, negative coordinates), kept 4 pt
  inside the visible frame, flipped above/below when there is no room, scrolling when taller
  than the screen.
- `MXRPopupCenter.shared.isPresenting` / `isPresentingAnchored` are observable; bars stay
  visible while a popup anchored in them is open (D023).

### Menus

```swift
@State private var open = false

Button { open.toggle() } label: { MXRIcon(.sort) }
    .mxrPopupMenu(isPresented: $open, placement: .below(.trailing), style: .contextMenu) {
        MXRMenuItem("Play", icon: .playback) { play() }
        MXRMenuItem("Favorite", icon: .favorite, isChecked: media.isFavorite) { toggleFavorite() }
        MXRMenuItem.separator
        MXRMenuItem.submenu("Add to Playlist", icon: .playlist) { playlistItems() }
        MXRMenuItem("Open", icon: .file, shortcut: app.keyBinding(for: .openFiles)) { app.perform(.openFiles) }
    }
```

- `MXRMenuItem(title, icon:, iconTone:, iconState:, shortcut:, isChecked:, isEnabled:, actions:) { action }`,
  `MXRMenuItem.submenu(title, icon:) { items }`, `MXRMenuItem.separator`. Items are built with
  `@MXRMenuBuilder` (`if`, `for`, arrays) and re-evaluated while shown, so checks and titles stay
  live. Submenu contents are evaluated when the submenu opens.
- `shortcut` is a `KeyBinding`; it is always shown in Mac glyphs (`⇧⌘O`, D026). Pass
  `app.keyBinding(for:)` so menus show the user's real binding.
- `isChecked` is Figma's `option` "selected" state: BG/A2 row and an orange check. The check
  sits in the icon slot when the row has no icon (Figma `Profiles`) and on the right when it has
  one (Figma `View Options`).
- `actions:` puts a `⋯` in the icon slot that opens the given items beside the row (Figma
  `Setting Preset`: rename/delete a custom preset).
- Styles (`MXRPopupStyle`): `.appMenu` (375 pt, Figma `menu`), `.contextMenu` (265 pt, Figma
  `context menu`, library menus, submenus), `.rightClickMenu` (292 pt), `.dropdown`, `.preset`.
  Cards grow for long titles up to 375 pt and truncate in the middle. For text-only radio lists
  without the icon slot (Figma `Sorting Options`) use `.textMenu` (trailing orange check).
- Placements (`MXRPopupPlacement`): `.below(alignment, gap:)`, `.above(…)`,
  `.awayFromWindowEdge(…)` (below in the window's upper half, above in its lower half: bar
  buttons that Customize Player can move), `.overField(rowOffset:)` (dropdowns), `.pointer`
  (context menus), `.beside` (submenus).

### Context menus

```swift
rowView.mxrContextMenu(style: .contextMenu) { fileItems(media) }
```

Opens on a secondary click or Control-click at the pointer; every other click passes through to
the view (the video keeps its click and double-click). The player's video uses
`.mxrVideoContextMenu()` (Figma `right-click menu`).

### Custom popup content

```swift
.mxrPopup(isPresented: $open, placement: .below(), surface: .contextMenu) { MyPopupContent() }
// inside MyPopupContent:
@Environment(\.mxrDismissPopup) private var dismissPopup
```

Same window, motion and dismissal; the content keeps its own keys (text fields, ⌘C/⌘V). With a
`surface` style the content is padded and drawn on that card; pass `nil` when the content draws
its own card. Use this for stateful popups (e.g. the library's "Add to Playlist" chooser) and
`\.mxrDismissPopup` where a popover used `\.dismiss`. Put `.appModel(app)` on the content when it
reads models from the environment.

### Dropdowns

```swift
MXRDropdown(selection: $hdr, options: HDRMode.allCases.map { MXRDropdownOption($0, title: $0.title) },
            accessibilityLabel: "HDR")
MXRDropdown(selection: $presetID, options: presetOptions, style: .preset, accessibilityLabel: "Preset") {
    MXRMenuItem("New Preset", icon: .add, iconTone: .mono) { newPreset() }   // leading items
}
```

For a custom field (dialog header dropdowns, the Shortcuts "All Fields" filter) keep the field
and attach only the list: `.mxrDropdownList(isPresented: $open, selectedRow: index) { items }`
(`fieldInset:` is the space between the field edge and its inner row, 2 pt in Figma).

Figma `Dropdown` 2372:8300 / `Setting Preset` 2372:8834: dark field with the value and a chevron;
the list opens over the field with the current option on the field's row and an orange check
(like a macOS pop-up button), so it opens upward when the current option is last. Options may
carry an icon (`EQ presets`) or `actions` (`⋯`). `width: nil` fills the proposed width.

### Adopted call sites

Library ⋯/+/sort/view and row menus (`View.mxrLibraryPopup`, `View.mxrLibraryContextMenu`, rows from
`LibraryMenus.popupItems`), queue sort and playlist chooser, sidebar `PanelDropdown`, Settings
`SettingsChoiceMenu` and the Add Subtitles / Open Media dropdowns (`DialogMenu`) all present through
this popup. New menus must use it, never `.popover` or `NSMenu`. `MXRMenuCard(…, activates: true)`
draws a live card in place (gallery, tests).

### Gallery

`MenusGallery` (`C.Menu/*`, `C.Dropdown/*`, `S68.ProfileSubmenu/movies`) and the player entries
`S07.AppMenu/default`, `S09.ContextMenu/default` draw the same cards with `MXRMenuCard`, which
takes a fixed `highlighted` / `expanded` row for hover and open-submenu states.

## Mac shortcuts (D026)

- App actions default to Command (`ShortcutAction.appActions`, mirrored in
  `module/MXRAppOptions.inc`): ⌘O open, ⇧⌘O folder, ⌘N network, ⌘D disc, ⌘R capture,
  ⌥⌘V open from clipboard, ⇧⌘S convert, ⌘, Settings, ⌘B bookmark, ⌘\ Hide UI, ⌘L library, Q queue.
  `ShortcutDefaultsTests` checks them against VLC's macOS engine defaults (`src/libvlc-module.c`),
  the standard menu keys and the module options.
- Show bindings with `KeyBinding.displayString` (`AppModel.shortcutText(for:)`), never as
  "Ctrl + O".
- The menu bar runs Command equivalents also while a dialog is open (Edit menu, ⌘Q); bare keys
  never act behind a dialog or inside a text field (`MenuKeyEquivalentPolicy`).
