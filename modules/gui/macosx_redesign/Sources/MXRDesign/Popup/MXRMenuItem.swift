import MXRCore
import SwiftUI

/// One row of a design-system popup menu (D025): an action, a submenu, or a separator.
///
/// Build menus with ``MXRMenuBuilder`` or plain arrays:
///
/// ```swift
/// .mxrPopupMenu(isPresented: $open, style: .appMenu) {
///     MXRMenuItem("Open File(s)", icon: .file, shortcut: app.keyBinding(for: .openFiles)) { app.perform(.openFiles) }
///     MXRMenuItem.separator
///     MXRMenuItem.submenu("Open Recent", icon: .recent) { recentItems() }
/// }
/// ```
///
/// Submenu contents are evaluated when the submenu opens and re-evaluated while it is shown, so
/// they always reflect the models (like `NSMenuDelegate.menuNeedsUpdate`).
public struct MXRMenuItem {
    public enum Kind {
        case action(@MainActor () -> Void)
        case submenu(@MainActor () -> [MXRMenuItem])
        case separator
    }

    public var kind: Kind
    public var title: String
    /// Two-tone menu icon in the leading 24 pt slot.
    public var icon: MXRIcon.Name?
    public var iconTone: MXRIcon.Tone
    public var iconState: MXRIcon.State
    /// Shown right-aligned in Mac glyphs (`⇧⌘O`, D026).
    public var shortcut: KeyBinding?
    /// Current choice: Figma `option` "selected" (BG/A2 fill and an orange check). The check
    /// takes the icon slot when the row has no icon (Figma `Profiles`), else the trailing slot.
    public var isChecked: Bool
    public var isEnabled: Bool
    /// A quieter FG/A3 title for a create row in a list of choices (Figma `Setting Preset`
    /// "+ New Preset").
    public var isSecondary = false
    /// Extra actions for this row behind a leading `⋯` (Figma `Setting Preset`: custom presets).
    public var actions: (@MainActor () -> [MXRMenuItem])?
    public var accessibilityLabel: String?
    /// Runs when this submenu opens, before its rows are built: the place to start loading what
    /// the rows show (like `NSMenuDelegate.menuWillOpen`), never inside the row provider.
    public var onOpen: (@MainActor () -> Void)?

    public init(_ title: String, icon: MXRIcon.Name? = nil, iconTone: MXRIcon.Tone = .twoTone,
                iconState: MXRIcon.State = .default, shortcut: KeyBinding? = nil, isChecked: Bool = false,
                isEnabled: Bool = true, accessibilityLabel: String? = nil,
                actions: (@MainActor () -> [MXRMenuItem])? = nil,
                action: @escaping @MainActor () -> Void) {
        self.kind = .action(action)
        self.title = title
        self.icon = icon
        self.iconTone = iconTone
        self.iconState = iconState
        self.shortcut = shortcut
        self.isChecked = isChecked
        self.isEnabled = isEnabled
        self.actions = actions
        self.accessibilityLabel = accessibilityLabel
    }

    /// A row that opens `items` on hover, click, → or Return.
    public static func submenu(_ title: String, icon: MXRIcon.Name? = nil, iconState: MXRIcon.State = .default,
                               isEnabled: Bool = true, onOpen: (@MainActor () -> Void)? = nil,
                               @MXRMenuBuilder items: @escaping @MainActor () -> [MXRMenuItem]) -> MXRMenuItem {
        var item = MXRMenuItem(title, icon: icon, iconState: iconState, isEnabled: isEnabled) {}
        item.kind = .submenu(items)
        item.onOpen = onOpen
        return item
    }

    /// A 1 pt `Divider/Dim` line between groups.
    public static var separator: MXRMenuItem {
        var item = MXRMenuItem("") {}
        item.kind = .separator
        item.isEnabled = false
        return item
    }

    public var isSeparator: Bool { if case .separator = kind { true } else { false } }
    public var isSubmenu: Bool { if case .submenu = kind { true } else { false } }
    /// Rows the keyboard and the pointer can highlight.
    public var isSelectable: Bool { !isSeparator && isEnabled }
    /// Submenu contents, if this row is a submenu.
    @MainActor public var children: [MXRMenuItem]? {
        if case .submenu(let items) = kind { items() } else { nil }
    }
}

/// Builds `[MXRMenuItem]` with `if`, `for` and nested arrays.
@resultBuilder
public enum MXRMenuBuilder {
    public static func buildExpression(_ item: MXRMenuItem) -> [MXRMenuItem] { [item] }
    public static func buildExpression(_ items: [MXRMenuItem]) -> [MXRMenuItem] { items }
    public static func buildBlock(_ parts: [MXRMenuItem]...) -> [MXRMenuItem] { parts.flatMap { $0 } }
    public static func buildOptional(_ part: [MXRMenuItem]?) -> [MXRMenuItem] { part ?? [] }
    public static func buildEither(first part: [MXRMenuItem]) -> [MXRMenuItem] { part }
    public static func buildEither(second part: [MXRMenuItem]) -> [MXRMenuItem] { part }
    public static func buildArray(_ parts: [[MXRMenuItem]]) -> [MXRMenuItem] { parts.flatMap { $0 } }
    public static func buildLimitedAvailability(_ part: [MXRMenuItem]) -> [MXRMenuItem] { part }
}

extension Array where Element == MXRMenuItem {
    /// Drops leading, trailing and doubled separators (for menus assembled from optional groups).
    public var tidiedSeparators: [MXRMenuItem] {
        var result: [MXRMenuItem] = []
        for item in self {
            if item.isSeparator, result.last?.isSeparator ?? true { continue }
            result.append(item)
        }
        if result.last?.isSeparator == true { result.removeLast() }
        return result
    }
}
