import AppKit
import MXRCore
import Observation

/// The macOS menu bar's copy of design-system menu rows (``MXRMenuItem``): Audio, Video, View ▸
/// Extensions and their submenus show the same rows, states and shortcuts as the in-window popups
/// (D025, D034), as native `NSMenu`s.
///
/// - Each menu is built when AppKit first asks for it and rebuilt only after a model its rows read
///   changed (Observation), not on every key-equivalent search.
/// - A change while the menu is open updates it in place, like the popups' rows, which are
///   re-evaluated while shown: same rows are patched (the highlight stays), new rows rebuild it.
/// - Rows set their own enabled state. AppKit's autoenabling would enable every row that opens a
///   submenu, so a disabled submenu (Speed at a fixed rate, Audio Device with no devices) would
///   look live. Behind a dialog every row waits (`isBlocked`, D040).
@MainActor
public final class MXRNativeMenuMirror: NSObject, NSMenuDelegate {
    private let isBlocked: @MainActor () -> Bool
    /// Runs before a mirrored menu updates (the owner refreshes its own command rows).
    public var willUpdate: (@MainActor () -> Void)?

    public init(isBlocked: @escaping @MainActor () -> Bool) {
        self.isBlocked = isBlocked
    }

    @MainActor private final class Source {
        var rows: @MainActor () -> [MXRMenuItem]
        let finish: (@MainActor (NSMenu) -> Void)?
        var onOpen: (@MainActor () -> Void)?
        weak var menu: NSMenu?
        var isDirty = true
        var isOpen = false
        /// Shape of the built rows; an update with the same shape patches the items in place.
        var shape: [String]?
        var children: [NSMenu] = []
        init(rows: @escaping @MainActor () -> [MXRMenuItem], finish: (@MainActor (NSMenu) -> Void)?,
             onOpen: (@MainActor () -> Void)?) {
            self.rows = rows; self.finish = finish; self.onOpen = onOpen
        }
    }

    /// Enabled state of a row that opens a submenu.
    private final class SubmenuState {
        let enabled: Bool
        init(enabled: Bool) { self.enabled = enabled }
    }

    private final class Action {
        let enabled: Bool
        let perform: @MainActor () -> Void
        init(enabled: Bool, perform: @escaping @MainActor () -> Void) { self.enabled = enabled; self.perform = perform }
    }

    private var sources: [ObjectIdentifier: Source] = [:]

    /// Fills `menu` from `rows`. `finish` appends the owner's own rows after a rebuild; `onOpen`
    /// runs each time the menu opens (the place to ask a backend for fresh contents).
    public func mirror(_ menu: NSMenu, @MXRMenuBuilder rows: @escaping @MainActor () -> [MXRMenuItem],
                       finish: (@MainActor (NSMenu) -> Void)? = nil, onOpen: (@MainActor () -> Void)? = nil) {
        menu.delegate = self
        menu.autoenablesItems = false
        let source = Source(rows: rows, finish: finish, onOpen: onOpen)
        source.menu = menu
        sources[ObjectIdentifier(menu)] = source
    }

    /// A mirrored submenu that `finish` added to `parent`; it is forgotten with the parent's rows.
    public func adopt(_ child: NSMenu, in parent: NSMenu) {
        sources[ObjectIdentifier(parent)]?.children.append(child)
    }

    // MARK: NSMenuDelegate

    public func menuNeedsUpdate(_ menu: NSMenu) {
        willUpdate?()
        guard let source = sources[ObjectIdentifier(menu)] else { return }
        if source.isDirty { update(menu, from: source) }
        refreshEnabledState(of: menu)
    }

    public func menuWillOpen(_ menu: NSMenu) {
        guard let source = sources[ObjectIdentifier(menu)] else { return }
        source.isOpen = true
        source.onOpen?()
    }

    public func menuDidClose(_ menu: NSMenu) {
        sources[ObjectIdentifier(menu)]?.isOpen = false
    }

    // MARK: Building

    private func update(_ menu: NSMenu, from source: Source) {
        let rows = withObservationTracking {
            source.rows()
        } onChange: { [weak self, weak source] in
            Task { @MainActor in
                guard let self, let source else { return }
                source.isDirty = true
                // An open menu follows its models at once; a closed one waits for its next update.
                if source.isOpen, let menu = source.menu {
                    self.update(menu, from: source)
                    self.refreshEnabledState(of: menu)
                }
            }
        }
        source.isDirty = false
        let shape = rows.map(Self.shape)
        if shape == source.shape, menu.items.count >= rows.count {
            for (item, row) in zip(menu.items, rows) { configure(item, with: row, source: source) }
            return
        }
        source.children.forEach(forget)
        source.children.removeAll()
        menu.removeAllItems()
        for row in rows {
            if row.isSeparator { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
            menu.addItem(item)
            configure(item, with: row, source: source)
        }
        source.shape = shape
        source.finish?(menu)
    }

    private static func shape(_ row: MXRMenuItem) -> String {
        switch row.kind {
        case .separator: "-"
        case .action: "a"
        case .submenu: "s:" + row.title
        }
    }

    private func configure(_ item: NSMenuItem, with row: MXRMenuItem, source: Source) {
        guard !row.isSeparator else { return }
        item.title = row.title
        item.state = row.isChecked ? .on : .off
        Self.apply(row.shortcut, to: item)
        switch row.kind {
        case .action(let action):
            item.target = self
            item.action = #selector(runAction(_:))
            item.representedObject = Action(enabled: row.isEnabled, perform: action)
        case .submenu(let children):
            item.representedObject = SubmenuState(enabled: row.isEnabled)
            if let submenu = item.submenu, let child = sources[ObjectIdentifier(submenu)] {
                // Same submenu row: its rows come from the new closure on its next update.
                child.rows = children
                child.onOpen = row.onOpen
                child.isDirty = true
                if child.isOpen { update(submenu, from: child); refreshEnabledState(of: submenu) }
            } else {
                let submenu = NSMenu(title: row.title)
                mirror(submenu, rows: children, onOpen: row.onOpen)
                source.children.append(submenu)
                item.submenu = submenu
            }
        case .separator: break
        }
    }

    private func forget(_ menu: NSMenu) {
        guard let source = sources.removeValue(forKey: ObjectIdentifier(menu)) else { return }
        source.children.forEach(forget)
    }

    /// Every row's enabled state: its own, and none behind a dialog. Rows the owner added in
    /// `finish` keep their target's validation.
    private func refreshEnabledState(of menu: NSMenu) {
        let blocked = isBlocked()
        for item in menu.items where !item.isSeparatorItem {
            if let state = item.representedObject as? SubmenuState {
                item.isEnabled = state.enabled && !blocked
            } else if let action = item.representedObject as? Action {
                item.isEnabled = action.enabled && !blocked
            } else if let validator = item.target as? NSMenuItemValidation, item.action != nil {
                item.isEnabled = validator.validateMenuItem(item)
            } else {
                item.isEnabled = !blocked
            }
        }
    }

    @objc private func runAction(_ item: NSMenuItem) {
        guard let action = item.representedObject as? Action, action.enabled, !isBlocked() else { return }
        action.perform()
    }

    // MARK: Key equivalents

    /// Sets `item`'s key equivalent from a binding (`nil` clears it), as the menu bar shows it.
    public static func apply(_ binding: KeyBinding?, to item: NSMenuItem) {
        item.keyEquivalent = binding.map { keyEquivalent($0.key) } ?? ""
        item.keyEquivalentModifierMask = binding.map { flags($0.modifiers) } ?? []
    }

    private static func flags(_ modifiers: KeyModifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.command) { flags.insert(.command) }
        return flags
    }

    private static func keyEquivalent(_ key: String) -> String {
        let named: [String: Int] = ["Left": NSLeftArrowFunctionKey, "Right": NSRightArrowFunctionKey,
                                    "Up": NSUpArrowFunctionKey, "Down": NSDownArrowFunctionKey,
                                    "Home": NSHomeFunctionKey, "End": NSEndFunctionKey,
                                    "Page Up": NSPageUpFunctionKey, "Page Down": NSPageDownFunctionKey]
        if let code = named[key], let scalar = UnicodeScalar(code) { return String(scalar) }
        if key.hasPrefix("F"), let number = Int(key.dropFirst()), (1...12).contains(number),
           let scalar = UnicodeScalar(NSF1FunctionKey + number - 1) { return String(scalar) }
        switch key {
        case "Space": return " "
        case "Esc": return "\u{1b}"
        case "Enter": return "\r"
        case "Tab": return "\t"
        case "Backspace": return "\u{8}"
        case "Delete": return "\u{7f}"
        default: return key.count == 1 ? key.lowercased() : ""
        }
    }
}
