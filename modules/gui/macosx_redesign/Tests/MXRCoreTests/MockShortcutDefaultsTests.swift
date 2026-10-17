// Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later.
import Foundation
import XCTest
@testable import MXRCore
@testable import MXRMockBackend

/// The mock reported VLC's non-Apple hotkeys (stop S, next N, fullscreen F…), so the context
/// menu (S09), onboarding (S71) and Keyboard Shortcuts (S64) galleries showed keys the app never
/// shows. The real engine reports its `#if defined(__APPLE__)` defaults (D026, D030).
@MainActor
final class MockShortcutDefaultsTests: XCTestCase {
    private static let libvlcModule = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() // macosx_redesign
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() // repository root
        .appendingPathComponent("src/libvlc-module.c")

    /// `key-<id>` → its macOS default bindings, read from VLC's source.
    private func engineMacDefaults() throws -> [String: [KeyBinding]] {
        let source = try String(contentsOf: Self.libvlcModule, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "#if defined(__APPLE__)\n/* Don't use the following combo's */"))
        let end = try XCTUnwrap(source.range(of: "#else /* Non Mac OS X */", range: start.upperBound..<source.endIndex))
        let block = String(source[start.upperBound..<end.lowerBound])
        var macros: [String: [KeyBinding]] = [:]
        let define = try NSRegularExpression(pattern: #"#\s*define\s+(KEY_\w+)\s+(NULL|"([^"]*)")"#)
        for match in define.matches(in: block, range: NSRange(block.startIndex..., in: block)) {
            let name = String(block[Range(match.range(at: 1), in: block)!])
            let value = Range(match.range(at: 3), in: block).map { String(block[$0]) } ?? ""
            macros[name] = value.split(separator: "\t").compactMap { KeyBinding(vlcString: String($0)) }
        }
        var result: [String: [KeyBinding]] = [:]
        let addKey = try NSRegularExpression(pattern: #"add_key\(\s*"key-([^"]+)",\s*(KEY_\w+)"#)
        for match in addKey.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            let id = String(source[Range(match.range(at: 1), in: source)!])
            if let bindings = macros[String(source[Range(match.range(at: 2), in: source)!])] { result[id] = bindings }
        }
        XCTAssertGreaterThan(result.count, 80, "the Apple hotkey block or the add_key list was not found")
        return result
    }

    func testMockEngineHotkeysAreVLCsMacDefaults() throws {
        let engine = try engineMacDefaults()
        let engineActions = MockShortcuts.defaultActions.filter { !$0.id.hasPrefix("app-") }
        XCTAssertGreaterThan(engineActions.count, 25)
        for action in engineActions {
            let expected = try XCTUnwrap(engine[action.id], "\(action.id) is not a VLC hotkey")
            XCTAssertEqual(action.hotkeys.map(\.vlcString), expected.map(\.vlcString), action.id)
        }
    }

    func testContextMenuKeysAreTheMacOnes() {
        let app = AppModel.mock(.playingEpisode)
        func shown(_ id: String) -> String? { app.shortcuts.primaryBinding(for: id)?.displayString }
        XCTAssertEqual(shown("stop"), "⌘.")
        XCTAssertEqual(shown("prev"), "⌘←")
        XCTAssertEqual(shown("next"), "⌘→")
        XCTAssertEqual(shown("record"), "⇧⌘R")
        XCTAssertEqual(shown("toggle-fullscreen"), "⌘F")
    }
}
