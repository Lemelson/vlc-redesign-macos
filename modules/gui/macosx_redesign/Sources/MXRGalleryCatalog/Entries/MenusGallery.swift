import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
import MXRUI
import SwiftUI

/// The design-system popup (D025) in the states Figma draws. Every entry renders the same card the
/// product presents in its popup window; only the open/hover state is fixed.
final class MenusGallery: NSObject, GalleryProvider {
    @MainActor static func galleryEntries() -> [Any] {
        let dropdown = Theme.Metric.Controls.dropdown
        return [
            GalleryEntry(id: "C.Menu/context-hover", title: "Context menu — first row hovered",
                         size: Theme.Metric.Menus.contextMenu.size, figmaNode: "2107:5903", screens: ["S29", "S30", "S31"],
                         renderEngine: .hostingView) {
                MXRMenuCard(items: (0..<6).map { _ in MXRMenuItem("Option") {} }, style: .contextMenu, highlighted: 0)
            },
            GalleryEntry(id: "C.Menu/view-options", title: "Menu with icons — List View selected",
                         size: CGSize(width: Theme.Metric.Menus.contextMenu.width, height: 104), figmaNode: "858:3290",
                         screens: ["S29"], renderEngine: .hostingView) {
                MXRMenuCard(items: [
                    MXRMenuItem("Grid View", icon: .grid, iconTone: .mono) {},
                    MXRMenuItem("List View", icon: .list, iconTone: .mono, isChecked: true) {},
                ], style: .contextMenu)
            },
            GalleryEntry(id: "S68.ProfileSubmenu/movies", title: "⋯ menu with the Profile submenu open",
                         size: MenusFigmaFrame.profiles, figmaNode: "6648:20666", screens: ["S07", "S08", "S68"],
                         notes: "Shortcuts use Mac glyphs (D026) where Figma spells Windows keys.",
                         renderEngine: .hostingView) {
                AppSubmenuComposition { $0.profiles.menuTitle }.appModel(AppModel.mock(.pausedEpisode))
            },
            GalleryEntry(id: "S08.RecentSubmenu/default", title: "⋯ menu with Open Recent open",
                         size: MenusFigmaFrame.profiles, screens: ["S07", "S08"],
                         notes: "No Figma frame: Open Recent uses the Profile submenu's card (Figma Profiles 6648:20666) with the mock's global history, then Clear Menu.",
                         renderEngine: .hostingView) {
                AppSubmenuComposition { _ in "Open Recent" }.appModel(AppModel.mock(.pausedEpisode))
            },
            // Product-built player menus (D030: a playing mock, no fixture overrides).
            GalleryEntry(id: "S10.BarMenu/speed", title: "Control bar speed menu", size: MenusFigmaFrame.textMenu(rows: AppModel.rateSteps.count),
                         screens: ["S10", "S17"], notes: "Text menu style of Figma Sorting Options 856:2215.",
                         renderEngine: .hostingView) {
                BarMenuComposition { MXRPlayerMenus.speeds($0) }.appModel(AppModel.mock(.playingEpisode))
            },
            GalleryEntry(id: "S10.BarMenu/hdr", title: "Control bar HDR menu", size: MenusFigmaFrame.textMenu(rows: HDRMode.allCases.count + 1, separators: 1),
                         screens: ["S10", "S18"],
                         notes: "Bar text menu (Sorting Options style) with the choices and order of Figma HDR Options 2372:8733, a settings dropdown of a different size; manual modes disabled with the reason (D039).",
                         renderEngine: .hostingView) {
                BarMenuComposition { MXRPlayerMenus.hdrModes($0) }.appModel(AppModel.mock(.playingEpisode))
            },
            GalleryEntry(id: "S10.BarMenu/zoom", title: "Control bar zoom menu", size: MenusFigmaFrame.textMenu(rows: VideoZoom.allCases.count),
                         screens: ["S10", "S18"], renderEngine: .hostingView) {
                BarMenuComposition { MXRPlayerMenus.zooms($0) }.appModel(AppModel.mock(.playingEpisode))
            },
            GalleryEntry(id: "S10.Overflow/compact-bar", title: "Compact control bar ⋯ menu",
                         size: MenusFigmaFrame.card(.rightClickMenu, items: OverflowComposition.items(AppModel.mock(.playingEpisode))),
                         screens: ["S09", "S10"],
                         notes: "Controls that did not fit, with their bar icons, then the right-click rows not already listed.",
                         renderEngine: .hostingView) {
                OverflowComposition().appModel(AppModel.mock(.playingEpisode))
            },
        ] + ContextSubmenuComposition.rows.map { row in
            GalleryEntry(id: "S10.ContextSubmenu/\(row.lowercased())", title: "Right-click menu with \(row) open",
                         size: ContextSubmenuComposition.size(row: row, app: AppModel.mock(.playingEpisode)), screens: ["S09", "S10"],
                         notes: "S10 is not designed: the submenu uses the contextMenu card of Figma Profiles 6648:20666.",
                         renderEngine: .hostingView) {
                ContextSubmenuComposition(row: row).appModel(AppModel.mock(.playingEpisode))
            }
        } + [
            GalleryEntry(id: "C.Dropdown/default-open", title: "Dropdown — closed and open",
                         size: MenusFigmaFrame.dropdown, figmaNode: "2372:8300", screens: ["S17", "S63"],
                         renderEngine: .hostingView) {
                DropdownComposition(style: .standard, fieldGap: MenusFigmaFrame.dropdownListTop - dropdown.height)
            },
            GalleryEntry(id: "C.Dropdown/preset-open", title: "Preset dropdown — open upward",
                         size: MenusFigmaFrame.preset, figmaNode: "2372:8834", screens: ["S17"],
                         notes: "Component-only: the product's sidebar preset list is MXRSidebarPresetList (S17); MXRDropdown(.preset) is for wave-2 adoption.",
                         renderEngine: .hostingView) {
                DropdownComposition(style: .preset, fieldGap: 0)
            },
        ]
    }
}

/// Frames of the Figma component renders these entries are compared with.
private enum MenusFigmaFrame {
    /// A text menu card of `rows` 48 pt rows (Figma `Sorting Options` geometry).
    static func textMenu(rows: Int, separators: Int = 0) -> CGSize {
        card(.textMenu, rows: rows, separators: separators)
    }
    /// A card of `style` holding `items` (rows at the style's row height, separators one hairline).
    @MainActor static func card(_ style: MXRPopupStyle, items: [MXRMenuItem]) -> CGSize {
        let separators = items.filter(\.isSeparator).count
        return card(style, rows: items.count - separators, separators: separators)
    }
    static func card(_ style: MXRPopupStyle, rows: Int, separators: Int) -> CGSize {
        let rowHeights = CGFloat(rows) * style.row.height + CGFloat(separators) * Theme.Stroke.hairline
        let gaps = CGFloat(max(0, rows + separators - 1)) * style.rowSpacing
        return CGSize(width: style.width, height: rowHeights + gaps + style.padding.vertical)
    }
    /// `Profiles` 6648:20666.
    static let profiles = CGSize(width: 651, height: 633)
    /// `Dropdown` component set 2372:8300.
    static let dropdown = CGSize(width: 406, height: 369)
    /// `Setting Preset` component set 2372:8834.
    static let preset = CGSize(width: 406, height: 412)
    /// Top of the open `Options` list below the closed field's top in 2372:8300.
    static let dropdownListTop: CGFloat = 68
    /// Top of the open preset list in the 2372:8834 frame.
    static let presetListTop: CGFloat = 98
}

/// Figma `Profiles` 6648:20666: the ⋯ menu with one submenu row ("Profile (…)", Open Recent)
/// expanded and its submenu beside it, top aligned with the row.
private struct AppSubmenuComposition: View {
    @Environment(AppModel.self) private var app
    let rowTitle: @MainActor (AppModel) -> String

    var body: some View {
        let menu = MXRPlayerMenus.appMenu(app)
        let row = menu.firstIndex { $0.title == rowTitle(app) } ?? 0
        ZStack(alignment: .topLeading) {
            MXRAppMenuView(expandedRow: row)
            // At its own width, as the presenter shows it (not stretched to the frame).
            MXRMenuCard(items: menu[row].children ?? [], style: .contextMenu).fixedSize()
                .offset(x: Theme.Metric.Menus.appMenu.width + Theme.Popup.submenuGap,
                        y: MXRPopupStyle.appMenu.submenuTop(row, in: menu))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A control-bar choice menu (speed, HDR, zoom) as it drops from the bar.
private struct BarMenuComposition: View {
    @Environment(AppModel.self) private var app
    let items: @MainActor (AppModel) -> [MXRMenuItem]

    var body: some View {
        MXRMenuCard(items: items(app), style: .textMenu).fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The compact bar's ⋯ with typical overflowed controls.
private struct OverflowComposition: View {
    @Environment(AppModel.self) private var app

    static func items(_ app: AppModel) -> [MXRMenuItem] {
        MXRPlayerMenus.overflowMenu([.playbackSpeed, .stop, .record, .zoom], app: app)
    }

    var body: some View {
        MXRMenuCard(items: Self.items(app), style: .rightClickMenu)
            .fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The right-click menu with one media submenu open beside its row (S10), placed as the popup
/// presenter places it (``MXRPopupPlacement/beside``).
private struct ContextSubmenuComposition: View {
    static let rows = ["Playback", "Video", "Audio", "Subtitle", "Playlist"]
    @Environment(AppModel.self) private var app
    let row: String

    /// The right-click card and the submenu beside it (no Figma frame: S10 is not designed).
    @MainActor static func size(row: String, app: AppModel) -> CGSize {
        let menu = MXRPlayerMenus.videoContextMenu(app)
        let index = menu.firstIndex { $0.title == row } ?? 0
        let main = MenusFigmaFrame.card(.rightClickMenu, items: menu)
        let submenu = MenusFigmaFrame.card(.contextMenu, items: menu[index].children ?? [])
        return CGSize(width: main.width + Theme.Popup.submenuGap + submenu.width,
                      height: max(main.height, submenuTop(menu, index: index) + submenu.height))
    }

    /// Top of the submenu card: its first row level with the parent row (``MXRPopupPlacement/beside``).
    static func submenuTop(_ menu: [MXRMenuItem], index: Int) -> CGFloat {
        MXRPopupStyle.rightClickMenu.submenuTop(index, in: menu)
    }

    var body: some View {
        let menu = MXRPlayerMenus.videoContextMenu(app)
        let index = menu.firstIndex { $0.title == row } ?? 0
        ZStack(alignment: .topLeading) {
            MXRMenuCard(items: menu, style: .rightClickMenu, expanded: index).fixedSize()
            MXRMenuCard(items: menu[index].children ?? [], style: .contextMenu).fixedSize()
                .offset(x: Theme.Metric.Menus.rightClickMenu.width + Theme.Popup.submenuGap,
                        y: Self.submenuTop(menu, index: index))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Figma `Dropdown` / `Setting Preset` component sets: the closed field, and the open list over
/// the field with the current option on the field's row.
private struct DropdownComposition: View {
    let style: MXRDropdownStyle
    let fieldGap: CGFloat
    @State private var value = 0

    var body: some View {
        let inset = Theme.Spacing.gap20 + Theme.Stroke.hairline
        VStack(alignment: .leading, spacing: 0) {
            MXRDropdown(selection: $value, options: options, style: style, accessibilityLabel: "Dropdown")
            if style == .standard {
                MXRMenuCard(items: items, style: .dropdown).padding(.top, fieldGap)
            }
        }
        .overlay(alignment: .topLeading) {
            if style == .preset {
                MXRMenuCard(items: presetItems, style: .preset).offset(y: MenusFigmaFrame.presetListTop - inset)
            }
        }
        .padding(inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var options: [MXRDropdownOption<Int>] {
        style == .preset ? [MXRDropdownOption(0, title: "Default Preset")]
            : (0..<5).map { MXRDropdownOption($0, title: "Dropdown") }
    }

    private var items: [MXRMenuItem] {
        (0..<5).map { MXRMenuItem("Dropdown", isChecked: $0 == 0) {} }
    }

    private var presetItems: [MXRMenuItem] {
        let custom = ["Custom Preset 01", "Custom Preset 02", "Anime", "Loud and then Quiet Movies"]
        var create = MXRMenuItem("New Custom Preset", icon: .add, iconTone: .mono) {}
        create.isSecondary = true
        return [create]
            + custom.map { MXRMenuItem($0, actions: { [] }) {} }
            + [MXRMenuItem("Default Preset", isChecked: true) {}]
    }
}
