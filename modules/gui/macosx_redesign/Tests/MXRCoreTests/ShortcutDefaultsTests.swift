import Foundation
import XCTest
@testable import MXRCore

/// D026: app shortcuts follow Mac conventions and never collide with VLC's macOS engine hotkeys,
/// the standard menu keys or each other (M1, SD-08, CMP-14, WT-12).
final class ShortcutDefaultsTests: XCTestCase {
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() // macosx_redesign
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() // repository root

    private var appDefaults: [(id: String, binding: KeyBinding)] {
        ShortcutAction.appActions.flatMap { action in action.hotkeys.map { (action.id, $0) } }
    }

    /// VLC's `#if defined(__APPLE__)` hotkey defaults in `src/libvlc-module.c`.
    private func engineAppleDefaults() throws -> [String: KeyBinding] {
        let source = try String(contentsOf: Self.repositoryRoot.appendingPathComponent("src/libvlc-module.c"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "#if defined(__APPLE__)\n/* Don't use the following combo's */"))
        let end = try XCTUnwrap(source.range(of: "#else /* Non Mac OS X */", range: start.upperBound..<source.endIndex))
        let block = source[start.upperBound..<end.lowerBound]
        let pattern = try NSRegularExpression(pattern: #"#\s*define\s+(KEY_\w+)\s+"([^"]*)""#)
        var result: [String: KeyBinding] = [:]
        let text = String(block)
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let name = String(text[Range(match.range(at: 1), in: text)!])
            for value in text[Range(match.range(at: 2), in: text)!].split(separator: "\t") {
                if let binding = KeyBinding(vlcString: String(value)) { result[name + ":" + value] = binding }
            }
        }
        XCTAssertGreaterThan(result.count, 80, "the Apple hotkey block was not found")
        return result
    }

    func testAppDefaultsDoNotReuseVLCMacEngineHotkeys() throws {
        let engine = try engineAppleDefaults()
        for (id, binding) in appDefaults {
            let clashes = engine.filter { $0.value == binding }.map(\.key)
            XCTAssertTrue(clashes.isEmpty, "\(id) \(binding.displayString) clashes with VLC's \(clashes)")
        }
        // The keys the review found double-bound: Ctrl+P/N/D (title/chapter) and L (audio track).
        for key in ["Ctrl+p", "Ctrl+n", "Ctrl+d", "l"] {
            let binding = try XCTUnwrap(KeyBinding(vlcString: key))
            XCTAssertFalse(appDefaults.contains { $0.binding == binding }, key)
        }
    }

    func testAppDefaultsAreUniqueAndAvoidStandardMenuKeys() {
        let bindings = appDefaults.map(\.binding)
        XCTAssertEqual(Set(bindings).count, bindings.count, "duplicate app default")
        let standard = ["c", "v", "x", "a", "z", "w", "m", "h", "q"].map { KeyBinding(key: $0, modifiers: .command) }
        for (id, binding) in appDefaults {
            XCTAssertFalse(standard.contains(binding), "\(id) takes the standard \(binding.displayString)")
            XCTAssertFalse(binding.modifiers.contains(.control), "\(id) uses Control instead of Command")
        }
    }

    func testMacDefaultsAndGlyphs() {
        func display(_ id: String) -> String? {
            ShortcutAction.appActions.first { $0.id == id }?.hotkeys.first?.displayString
        }
        XCTAssertEqual(display("app-open-files"), "⌘O")
        XCTAssertEqual(display("app-open-folder"), "⇧⌘O")
        XCTAssertEqual(display("app-open-network"), "⌘N")
        XCTAssertEqual(display("app-settings"), "⌘,")
        XCTAssertEqual(display("app-hide-ui"), "⌘\\")
        XCTAssertEqual(display("app-add-bookmark"), "⌘B")
        XCTAssertEqual(display("app-toggle-library"), "⌘L")
        XCTAssertNil(display("app-about"), "About has no shortcut on the Mac")
    }

    /// The VLC module declares the same defaults as options (`macosx-redesign-key-<id>`).
    func testModuleOptionDefaultsMatchAppActions() throws {
        let url = Self.repositoryRoot.appendingPathComponent("modules/gui/macosx_redesign/module/MXRAppOptions.inc")
        let text = try String(contentsOf: url, encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #"add_string\("macosx-redesign-key-(app-[a-z-]+)", "((?:[^"\\]|\\.)*)""#)
        var options: [String: String] = [:]
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let id = String(text[Range(match.range(at: 1), in: text)!])
            options[id] = String(text[Range(match.range(at: 2), in: text)!]).replacingOccurrences(of: "\\\\", with: "\\")
        }
        XCTAssertEqual(Set(options.keys), Set(ShortcutAction.appActions.map(\.id)))
        for action in ShortcutAction.appActions {
            XCTAssertEqual(options[action.id].flatMap(KeyBinding.init(vlcString:)), action.hotkeys.first, action.id)
        }
    }

    /// SD-09: dialogs never block ⌘C/⌘V/⌘A/⌘Z/⌘Q; bare playback keys stay out of dialogs and fields.
    func testMenuKeyEquivalentPolicy() throws {
        let paste = KeyBinding(key: "v", modifiers: .command)
        let quit = KeyBinding(key: "q", modifiers: .command)
        let space = KeyBinding(key: "Space")
        XCTAssertTrue(MenuKeyEquivalentPolicy.allows(paste, isRecording: false, hasModal: true, isEditing: true))
        XCTAssertTrue(MenuKeyEquivalentPolicy.allows(quit, isRecording: false, hasModal: true, isEditing: false))
        XCTAssertTrue(MenuKeyEquivalentPolicy.allows(space, isRecording: false, hasModal: false, isEditing: false))
        XCTAssertFalse(MenuKeyEquivalentPolicy.allows(space, isRecording: false, hasModal: true, isEditing: false))
        XCTAssertFalse(MenuKeyEquivalentPolicy.allows(space, isRecording: false, hasModal: false, isEditing: true))
        XCTAssertFalse(MenuKeyEquivalentPolicy.allows(paste, isRecording: true, hasModal: true, isEditing: false))
        XCTAssertTrue(MenuKeyEquivalentPolicy.allows(quit, isRecording: true, hasModal: true, isEditing: false))
    }

    /// M2: a stored old Control default is recognised; a deliberate custom binding is not.
    func testLegacyControlDefaultsAreRecognisedForMigration() {
        XCTAssertTrue(ShortcutAction.isLegacyAppDefault("Ctrl+p", forID: "app-settings"))
        XCTAssertTrue(ShortcutAction.isLegacyAppDefault("Ctrl+\\", forID: "app-hide-ui"))
        XCTAssertFalse(ShortcutAction.isLegacyAppDefault("Command+,", forID: "app-settings"))
        XCTAssertFalse(ShortcutAction.isLegacyAppDefault("Ctrl+o", forID: "app-settings"))
        XCTAssertFalse(ShortcutAction.isLegacyAppDefault("Ctrl+p", forID: "app-keyboard-shortcuts"))
    }

    /// M1: when an engine action and an app action share a key, the app (menu) action wins.
    @MainActor func testAppActionWinsOverEngineActionOnTheSameKey() throws {
        final class Stub: ShortcutsBackend {
            var actions: [ShortcutAction]
            init(_ actions: [ShortcutAction]) { self.actions = actions }
            func trigger(actionID: String) {}
            func setBindings(_ hotkeys: [KeyBinding], global: [KeyBinding], forAction id: String) {}
            func resetAllBindings() {}
            func save() {}
            func addListener(_ owner: AnyObject, handler: @escaping @MainActor () -> Void) {}
        }
        let ctrlP = try XCTUnwrap(KeyBinding(vlcString: "Ctrl+p"))
        let engine = ShortcutAction(id: "title-prev", title: "Previous title", group: .navigation, hotkeys: [ctrlP])
        let app = ShortcutAction(id: "app-settings", title: "Settings", group: .interface, hotkeys: [ctrlP])
        let model = ShortcutsModel(backend: Stub([engine, app]))
        XCTAssertEqual(model.action(for: ctrlP)?.id, "app-settings")
    }
}
