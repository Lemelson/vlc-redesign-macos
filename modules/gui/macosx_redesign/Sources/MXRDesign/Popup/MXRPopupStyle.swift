import AppKit
import SwiftUI

extension Theme {
    /// Presentation constants shared by every design-system popup (D024, D025): the `⋯` menu and
    /// its submenus, the right-click menu, library menus and dropdown lists.
    ///
    /// Geometry comes from Figma; the motion is the decision in D024 (fade + 6 pt slide from the
    /// anchor, 0.15 s ease-out in, 0.1 s out, none under Reduce Motion).
    public enum Popup {
        /// Fade-and-slide in (D024).
        public static let appearDuration: TimeInterval = 0.15
        /// Fade out (D024).
        public static let disappearDuration: TimeInterval = 0.1
        /// Slide distance from the anchor (D024).
        public static let slideDistance: CGFloat = 6
        /// Hover time before a submenu opens or switches to another row; moving into the open
        /// submenu within this time keeps it (macOS menu behaviour, P6).
        public static let submenuHoverDelay: TimeInterval = 0.2
        /// Type-select forgets the typed prefix after this pause (NSMenu behaviour).
        public static let typeSelectTimeout: TimeInterval = 1
        /// Horizontal gap between a menu and its submenu: Figma `Profiles` 6648:20666 places the
        /// 265 pt submenu at x 386 next to the 375 pt menu.
        public static let submenuGap: CGFloat = 11
        /// Vertical gap between an anchor (the top bar, a button) and the menu dropping from it
        /// (video 13m08: the `⋯` menu hangs just under the top bar).
        public static let anchorGap: CGFloat = Theme.Spacing.gap6
        /// Closest a popup comes to the edge of the screen's visible area.
        public static let screenMargin: CGFloat = Theme.Spacing.gap4
        /// Disabled rows. Figma's only disabled state is the dialog primary button (1915:8663).
        public static let disabledOpacity: Double = Theme.Metric.Controls.dialogPrimaryButtonDisabledOpacity
        /// The sidebar preset picker's closed field (Figma `Setting Preset` field 2372:8835).
        public static let presetFieldHeight: CGFloat = 42
        /// The sidebar preset picker's options (Figma `Setting Preset` option 2372:8836).
        public static let presetOptionHeight: CGFloat = 38
    }
}

/// How a popup card looks: surface, padding and rows. Pick a Figma preset; widths are the
/// Figma frame widths and grow to fit longer titles up to ``maxWidth``.
public struct MXRPopupStyle: Hashable, Sendable {
    /// Card fill.
    public var fill: ThemeColor
    /// Figma "bg blur": a live backdrop blur behind the card.
    public var blursBackdrop: Bool
    /// Drop shadow outside the card (Figma `showShadowBehindNode = false`).
    public var shadow: Theme.Shadow?
    public var radius: CGFloat
    public var padding: Theme.Insets
    /// Space between rows (`itemSpacing`).
    public var rowSpacing: CGFloat
    /// Row geometry: height, corner radius, icon gap and insets.
    public var row: Theme.Box
    /// Menus keep a 24 pt icon slot on every row (Figma `option` 2107:5935); dropdown options
    /// start with the text unless the option has an icon (Figma `Setting Preset` 2372:8834).
    public var reservesIconSlot: Bool
    /// Default card width (Figma frame width).
    public var width: CGFloat
    /// Widest the card grows for long titles before truncating.
    public var maxWidth: CGFloat

    public init(fill: ThemeColor, blursBackdrop: Bool, shadow: Theme.Shadow?, radius: CGFloat,
                padding: Theme.Insets, rowSpacing: CGFloat, row: Theme.Box, reservesIconSlot: Bool,
                width: CGFloat, maxWidth: CGFloat) {
        self.fill = fill
        self.blursBackdrop = blursBackdrop
        self.shadow = shadow
        self.radius = radius
        self.padding = padding
        self.rowSpacing = rowSpacing
        self.row = row
        self.reservesIconSlot = reservesIconSlot
        self.width = width
        self.maxWidth = maxWidth
    }

    private static func menu(_ card: Theme.Box, row: Theme.Box) -> MXRPopupStyle {
        MXRPopupStyle(fill: Theme.Color.bgA3Transparent, blursBackdrop: true, shadow: Theme.Effect.menuShadow,
                      radius: card.radius ?? Theme.Radius.xl, padding: card.padding, rowSpacing: card.gap,
                      row: row, reservesIconSlot: true, width: card.width,
                      maxWidth: Theme.Metric.Menus.appMenu.width)
    }

    /// The `⋯` app menu (Figma `menu` 6062:13354, 375 pt).
    public static let appMenu = menu(Theme.Metric.Menus.appMenu, row: Theme.Metric.Menus.appMenuRow)
    /// Context menus and submenus (Figma `context menu` 2107:5903 / 2139:8935 / 6648:20514, 265 pt).
    public static let contextMenu = menu(Theme.Metric.Menus.contextMenu, row: Theme.Metric.Menus.contextMenuRow)
    /// A menu of text-only choices (Figma sort menu 856:2215): no icon slot, the current choice
    /// carries the orange check at the trailing edge.
    public static let textMenu: MXRPopupStyle = {
        var style = contextMenu
        style.reservesIconSlot = false
        return style
    }()
    /// The right-click menu on the video (Figma `right-click menu` 6065:13616, 292 pt). Figma draws
    /// it without the blur/shadow effect of the other menus; it floats over video like them, so
    /// it shares their surface (D025: one menu look).
    public static let rightClickMenu = menu(Theme.Metric.Menus.rightClickMenu, row: Theme.Metric.Menus.rightClickRow)

    /// A dropdown's open list (Figma `Dropdown` 2372:8300: `Options` 2372:8307, rows 2372:8360).
    public static let dropdown: MXRPopupStyle = {
        let list = Theme.Metric.Controls.dropdownOpenList
        return MXRPopupStyle(fill: Theme.Color.bgA4, blursBackdrop: false, shadow: Theme.Effect.dropdownListShadow,
                             radius: list.radius ?? Theme.Radius.md, padding: list.padding, rowSpacing: list.gap,
                             row: Theme.Metric.Controls.dropdownOption, reservesIconSlot: false,
                             width: list.width, maxWidth: list.width)
    }()

    /// The sidebar preset list (Figma `Setting Preset` 2372:8834: 38 pt options, `presetListShadow`).
    public static let preset: MXRPopupStyle = {
        var style = dropdown
        style.shadow = Theme.Effect.presetListShadow
        style.row.height = MXRDropdownStyle.preset.optionHeight
        return style
    }()

    /// Distance from the card top to the top of row `index` of `items`: the top padding, then each
    /// earlier row at the row height and each earlier separator at one hairline, `rowSpacing` apart.
    /// The single source for where a row sits, used by the presenter and the gallery.
    public func rowTop(_ index: Int, in items: [MXRMenuItem]) -> CGFloat {
        items.prefix(max(0, index)).reduce(padding.top) { top, item in
            top + (item.isSeparator ? Theme.Stroke.hairline : row.height) + rowSpacing
        }
    }

    /// Top of a `submenu` card (relative to this card's top) whose first row lines up with row
    /// `index`, as ``MXRPopupPlacement/beside(row:parentCard:topInset:)`` places it.
    public func submenuTop(_ index: Int, in items: [MXRMenuItem], submenu: MXRPopupStyle = .contextMenu) -> CGFloat {
        rowTop(index, in: items) - submenu.padding.top
    }

    /// Space around the card inside its window for the shadow (and the slide-in).
    var outerMargin: CGFloat {
        guard let shadow else { return Theme.Popup.slideDistance }
        return max(Theme.Popup.slideDistance, shadow.blur + max(abs(shadow.x), abs(shadow.y)) + shadow.spread)
    }
}
