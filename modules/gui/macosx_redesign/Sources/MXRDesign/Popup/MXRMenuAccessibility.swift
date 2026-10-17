import AppKit
import MXRCore

/// One row of a presented design-system menu as VoiceOver sees it (PLAYER-07, D025): an
/// `AXMenuItem` with the same attributes `NSMenu` publishes, i.e. the title, the ✓ mark of the
/// current choice, the command key and its modifiers, the enabled state, a press action and,
/// while open, its submenu.
///
/// The row is drawn by SwiftUI (``MXRMenuCardContent``); its accessibility comes from AppKit so
/// the roles and the mark/shortcut attributes match a native menu exactly.
///
/// The element takes its isolation from `NSAccessibilityElement` rather than declaring
/// `@MainActor`: depending on the SDK annotations the build sees (SwiftPM's native and swiftbuild
/// systems differ), AppKit's overrides are main-actor or nonisolated. Its own row state is plain
/// stored data; the level it reads is main-actor state and is reached through
/// `MainActor.assumeIsolated`, which holds because AppKit queries accessibility on the main thread.
final class MXRMenuAccessibilityItem: NSAccessibilityElement {
    private weak var level: MXRPopupLevel?
    let row: Int
    private(set) var item: MXRMenuItem

    init(level: MXRPopupLevel, row: Int, item: MXRMenuItem) {
        self.level = level
        self.row = row
        self.item = item
        super.init()
    }

    /// Refreshes the row and its links: the level's `AXMenu` as parent and, while it is open,
    /// the submenu's `AXMenu` as the only child (as NSMenu does).
    func update(_ item: MXRMenuItem, parent: NSView?, submenu: NSView?) {
        self.item = item
        setAccessibilityParent(parent)
        setAccessibilityChildren(submenu.map { [$0] } ?? [])
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .menuItem }
    override func accessibilityTitle() -> String? { item.accessibilityLabel ?? item.title }
    override func accessibilityLabel() -> String? { item.accessibilityLabel ?? item.title }
    override func isAccessibilityEnabled() -> Bool { item.isEnabled }
    override func isAccessibilitySelected() -> Bool { isHighlighted }
    override func isAccessibilityFocused() -> Bool { isHighlighted }
    override func accessibilityFrame() -> NSRect {
        let level = level, row = row
        return MainActor.assumeIsolated { level?.rowFrame(row) ?? .zero }
    }

    override func accessibilityPerformPress() -> Bool {
        guard item.isEnabled, let level else { return false }
        let row = row
        MainActor.assumeIsolated { level.activate(row) }
        return true
    }

    private var isHighlighted: Bool {
        let level = level, row = row
        return MainActor.assumeIsolated { level?.tracking.highlighted == row }
    }

    // AXMenuItemMarkChar / AXMenuItemCmdChar / AXMenuItemCmdModifiers have no NSAccessibility
    // property; NSMenu publishes them through the attribute API, so this element does too.

    private static let markChar = NSAccessibility.Attribute(rawValue: "AXMenuItemMarkChar")
    private static let cmdChar = NSAccessibility.Attribute(rawValue: "AXMenuItemCmdChar")
    private static let cmdGlyph = NSAccessibility.Attribute(rawValue: "AXMenuItemCmdGlyph")
    private static let cmdModifiers = NSAccessibility.Attribute(rawValue: "AXMenuItemCmdModifiers")

    @available(macOS, deprecated: 10.10)
    override func accessibilityAttributeNames() -> [NSAccessibility.Attribute] {
        var names = super.accessibilityAttributeNames()
        for name in [Self.markChar, Self.cmdChar, Self.cmdGlyph, Self.cmdModifiers] where !names.contains(name) {
            names.append(name)
        }
        return names
    }

    @available(macOS, deprecated: 10.10)
    override func accessibilityAttributeValue(_ attribute: NSAccessibility.Attribute) -> Any? {
        switch attribute {
        case Self.markChar: return item.isChecked ? "✓" : nil
        case Self.cmdChar: return item.shortcut.flatMap { MXRMenuKeyAttributes(binding: $0).character }
        case Self.cmdGlyph: return item.shortcut.flatMap { MXRMenuKeyAttributes(binding: $0).glyph }
        case Self.cmdModifiers: return item.shortcut.map { MXRMenuKeyAttributes(binding: $0).modifiers }
        default: return super.accessibilityAttributeValue(attribute)
        }
    }
}

/// The Carbon menu-key attributes of a binding, as `NSMenu` reports them to accessibility.
struct MXRMenuKeyAttributes: Equatable {
    /// AXMenuItemCmdChar: the key as typed (letters upper-case), nil for a glyph key.
    let character: String?
    /// AXMenuItemCmdGlyph: Carbon `kMenu…Glyph` for keys without a character (arrows, F-keys).
    let glyph: Int?
    /// AXMenuItemCmdModifiers: `kAXMenuItemModifier…` bits (Shift 1, Option 2, Control 4,
    /// No Command 8).
    let modifiers: Int

    init(binding: KeyBinding) {
        var bits = 0
        if binding.modifiers.contains(.shift) { bits |= 1 }
        if binding.modifiers.contains(.option) { bits |= 2 }
        if binding.modifiers.contains(.control) { bits |= 4 }
        if !binding.modifiers.contains(.command) { bits |= 8 }
        modifiers = bits
        let glyphs: [String: Int] = [
            "Left": 0x64, "Right": 0x65, "Up": 0x68, "Down": 0x6A, "Home": 0x66, "End": 0x69,
            "Page Up": 0x62, "Page Down": 0x6B, "Esc": 0x1B, "Enter": 0x0B, "Tab": 0x02,
            "Backspace": 0x17, "Delete": 0x0A, "Space": 0x09,
        ]
        if let glyph = glyphs[binding.key] {
            self.glyph = glyph
            character = nil
        } else if binding.key.count > 1, binding.key.hasPrefix("F"), let number = Int(binding.key.dropFirst()),
                  (1...12).contains(number) {
            // kMenuF1Glyph (0x6F) … kMenuF12Glyph (0x7A).
            glyph = 0x6F + number - 1
            character = nil
        } else {
            glyph = nil
            character = binding.key.count == 1 ? binding.key.uppercased() : nil
        }
    }
}
