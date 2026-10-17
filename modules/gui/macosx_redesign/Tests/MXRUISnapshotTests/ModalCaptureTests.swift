import AppKit
import XCTest
import MXRCore
@testable import MXRUI

/// NSApplication.sendEvent offers every key-down to the key window's `performKeyEquivalent`
/// before `keyDown`, so the recorder must interpret Esc and Delete on that path too.
@MainActor
final class ModalCaptureTests: XCTestCase {
    private func recordingWindow() -> (NSWindow, SettingsKeyCaptureResponder) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let responder = SettingsKeyCaptureResponder(); window.contentView = responder
        XCTAssertTrue(window.makeFirstResponder(responder))
        return (window, responder)
    }

    private func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = [], repeated: Bool = false, in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars.lowercased(), isARepeat: repeated, keyCode: code)!
    }

    func testEscapeKeyEquivalentCancelsInsteadOfRecording() {
        let (window, responder) = recordingWindow()
        var cancelled = false; var captured: [KeyBinding?] = []
        responder.cancel = { cancelled = true }; responder.capture = { captured.append($0) }
        XCTAssertTrue(window.performKeyEquivalent(with: key(53, "\u{1b}", in: window)))
        XCTAssertTrue(cancelled); XCTAssertTrue(captured.isEmpty)
        window.close()
    }

    func testDeleteKeyEquivalentClearsTheBinding() {
        for code: UInt16 in [51, 117] {
            let (window, responder) = recordingWindow()
            var captured: [KeyBinding?] = []
            responder.capture = { captured.append($0) }
            XCTAssertTrue(window.performKeyEquivalent(with: key(code, "\u{7f}", in: window)))
            XCTAssertEqual(captured, [nil], "Delete clears the binding")
            window.close()
        }
    }

    func testRepeatKeyEquivalentIsIgnoredAndCommandQIsLeftToTheApp() {
        let (window, responder) = recordingWindow()
        var captured: [KeyBinding?] = []
        responder.capture = { captured.append($0) }
        XCTAssertTrue(window.performKeyEquivalent(with: key(35, "P", [.command, .shift], repeated: true, in: window)))
        XCTAssertTrue(captured.isEmpty, "Key repeats are swallowed, not recorded")
        XCTAssertFalse(window.performKeyEquivalent(with: key(12, "q", [.command], in: window)))
        XCTAssertTrue(captured.isEmpty, "⌘Q is never recorded (D026)")
        XCTAssertTrue(window.performKeyEquivalent(with: key(35, "P", [.command, .shift], in: window)))
        XCTAssertEqual(captured, [KeyBinding(key: "p", modifiers: [.command, .shift])])
        window.close()
    }
}
