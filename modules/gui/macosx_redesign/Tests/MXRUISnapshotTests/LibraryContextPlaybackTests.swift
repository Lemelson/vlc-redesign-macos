import AppKit
import MXRCore
import MXRMockBackend
@testable import MXRUI
import SwiftUI
import XCTest

final class LibraryContextPlaybackTests: XCTestCase {
    @MainActor private static var retainedWindows: [NSWindow] = []

    @MainActor
    func testPopupPlayKeepsTheQueue() async throws {
        let app = AppModel.mock(.playingEpisode)
        let upcoming = app.queue.items.dropFirst().map(\.media.id)
        app.library.navigate(to: .folder("wand-s01"))
        let media = try XCTUnwrap(app.library.entries.first { $0.media?.episode?.episode == 12 }?.media)

        try await pressPlay(in: MXRLibraryPopupView(kind: .file(media)).appModel(app))
        for _ in 0..<50 where app.player.media?.id != media.id { await Task.yield() }

        XCTAssertEqual(app.player.media?.id, media.id)
        XCTAssertEqual(app.queue.items.map(\.media.id), [media.id] + upcoming, "Play replaces the current item only")
    }

    @MainActor
    func testPopupPlayOnPlaylistPlaysTheWholePlaylist() async throws {
        let app = AppModel.mock(.idle)
        app.library.select(.playlists)
        let playlist = try XCTUnwrap(app.library.entries.compactMap { if case .playlist(let p) = $0 { return p }; return nil }.first)

        try await pressPlay(in: MXRLibraryPopupView(kind: .playlist(playlist)).appModel(app))
        for _ in 0..<100 where app.queue.items.isEmpty { await Task.yield() }

        XCTAssertEqual(app.queue.items.count, playlist.itemCount)
        XCTAssertEqual(app.queue.currentIndex, 0)
    }

    @MainActor
    private func pressPlay<V: View>(in view: V) async throws {
        _ = NSApplication.shared
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 265, height: 584), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        Self.retainedWindows.append(window)
        let host = NSHostingView(rootView: view)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let play = try XCTUnwrap(elements(host).first {
            value($0, "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue
                && value($0, "accessibilityLabel") as? String == "Play"
        })
        let selector = NSSelectorFromString("accessibilityPerformPress")
        let implementation = try XCTUnwrap(play.responds(to: selector) ? play.method(for: selector) : nil)
        // SwiftUI.AccessibilityNode exposes the standard AX selectors without formally
        // conforming to NSAccessibilityProtocol. Call the SDK's BOOL press signature.
        typealias Press = @convention(c) (AnyObject, Selector) -> Bool
        let action = unsafeBitCast(implementation, to: Press.self)
        XCTAssertTrue(action(play, selector))
        await Task.yield()
    }

    @MainActor
    private func value(_ object: NSObject, _ method: String) -> Any? {
        let selector = NSSelectorFromString(method)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }

    @MainActor
    private func elements(_ object: Any) -> [NSObject] {
        guard let ax = object as? NSObject else { return [] }
        return [ax] + ((value(ax, "accessibilityChildren") as? [Any]) ?? []).flatMap { elements($0) }
    }
}
