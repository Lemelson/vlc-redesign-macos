import AppKit
import XCTest
@testable import MXRCore
import MXRMockBackend

/// R01: letter hotkeys on a Russian (or any non-Latin) layout match by the physical key, through
/// the current ASCII-capable layout, not by the Cyrillic character the key types.
@MainActor
final class NonLatinLayoutShortcutTests: XCTestCase {
    /// ABC layout for the keys the tests press: F (3), C (8), Q (12), M (46), "/" (44).
    private static let abc: [UInt16: String] = [3: "f", 8: "c", 12: "q", 46: "m", 44: "/"]
    private var saved: (@MainActor (UInt16) -> String?)!

    // The async overrides run on the class's main actor, where the layout hook lives.
    override func setUp() async throws {
        try await super.setUp()
        saved = KeyBinding.asciiLayoutCharacter
        KeyBinding.asciiLayoutCharacter = { Self.abc[$0] }
    }

    override func tearDown() async throws {
        KeyBinding.asciiLayoutCharacter = saved
        try await super.tearDown()
    }

    private func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    }

    func testCyrillicLetterMatchesLatinBinding() {
        XCTAssertEqual(KeyBinding(event: key(3, "а")), KeyBinding(key: "f"))
        XCTAssertEqual(KeyBinding(event: key(46, "ь", [.option])), KeyBinding(key: "m", modifiers: .option))
        let backend = MockBackend(scenario: .playingMovie)
        let app = backend.makeAppModel(clockTicks: false)
        XCTAssertTrue(app.shortcuts.handle(event: key(3, "а")))
        XCTAssertEqual(backend.shortcuts.triggered, ["audiodelay-down"])
    }

    func testShiftedCyrillicLetterMatchesShiftLatinBinding() {
        XCTAssertEqual(KeyBinding(event: key(3, "А", [.shift])), KeyBinding(key: "f", modifiers: .shift))
        XCTAssertEqual(KeyBinding(event: key(3, "А", [.capsLock])), KeyBinding(key: "f"), "Caps Lock alone stays a plain letter")
        XCTAssertEqual(KeyBinding(event: key(12, "й", [.command])), KeyBinding(key: "q", modifiers: .command))
    }

    func testMenuPolicyTreatsCyrillicCommandKeysAsLatin() {
        let copy = KeyBinding(event: key(8, "с", [.command]))!
        XCTAssertTrue(MenuKeyEquivalentPolicy.allows(copy, isRecording: false, hasModal: true, isEditing: false), "⌘С copies in a dialog")
        let quit = KeyBinding(event: key(12, "й", [.command]))!
        XCTAssertTrue(MenuKeyEquivalentPolicy.allows(quit, isRecording: true, hasModal: false, isEditing: false), "⌘Й quits while recording")
    }

    func testASCIIAndNamedKeysAreNotTranslated() {
        // On ЙЦУКЕН the "/" key types "." (ASCII): kept as typed, like before.
        XCTAssertEqual(KeyBinding(event: key(44, ".")), KeyBinding(key: "."))
        XCTAssertEqual(KeyBinding(event: key(3, "f")), KeyBinding(key: "f"))
        XCTAssertEqual(KeyBinding(event: key(0x31, " ")), KeyBinding(key: "Space"))
        XCTAssertEqual(KeyBinding(event: key(0x7B, "\u{F702}")), KeyBinding(key: "Left"))
    }

    func testNonLatinCharacterWithoutLatinKeyIsKept() {
        // A key the ASCII-capable layout does not give a Latin character for keeps its own character.
        KeyBinding.asciiLayoutCharacter = { _ in "ö" }
        XCTAssertEqual(KeyBinding(event: key(41, "ö")), KeyBinding(key: "ö"))
        KeyBinding.asciiLayoutCharacter = { _ in nil }
        XCTAssertEqual(KeyBinding(event: key(41, "ж")), KeyBinding(key: "ж"))
    }
}
