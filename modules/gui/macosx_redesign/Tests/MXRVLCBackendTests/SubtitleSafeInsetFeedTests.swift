// Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later.
import AppKit
import XCTest
@testable import MXRVLCBackend

/// Areas C-bridge open minor / critic P2: the subtitle safe inset was sent only when the
/// covered points or the video size changed, so a resize or a move to a screen with another
/// backing scale kept stale pixels. The window below is never ordered in.
@MainActor
final class SubtitleSafeInsetFeedTests: XCTestCase {
    private func makeWindow(_ size: CGSize) -> (NSWindow, NSView) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        return (window, view)
    }

    func testResizingTheVideoViewResendsTheInsetWithoutTheNewLetterbox() {
        let (window, view) = makeWindow(CGSize(width: 800, height: 500))
        var sent: [Double] = []
        let feed = SubtitleSafeInsetFeed(view: view, backingScale: { _ in 2 }) { points, _ in sent.append(points) }
        defer { feed.invalidate() }
        feed.update(covered: 80, videoSize: CGSize(width: 1600, height: 1000))
        XCTAssertEqual(sent, [80], "the picture fills the view: the bar covers 80 pt of it")
        // Taller window, same bar: the 16:10 picture now has 50 pt of letterbox below it.
        window.setContentSize(CGSize(width: 800, height: 600))
        XCTAssertEqual(view.bounds.height, 600)
        XCTAssertEqual(sent, [80, 30], "the resize re-sends with the letterbox subtracted")
        window.setContentSize(CGSize(width: 800, height: 600))
        XCTAssertEqual(sent, [80, 30], "no change, no send")
    }

    func testABackingScaleChangeResendsTheSameInsetAtTheNewScale() {
        let (window, view) = makeWindow(CGSize(width: 800, height: 450))
        var scale = 2.0
        var sent: [(Double, Double)] = []
        let feed = SubtitleSafeInsetFeed(view: view, backingScale: { _ in scale }) { points, backing in sent.append((points, backing)) }
        defer { feed.invalidate() }
        feed.update(covered: 60, videoSize: CGSize(width: 1920, height: 1080))
        scale = 1
        NotificationCenter.default.post(name: NSWindow.didChangeBackingPropertiesNotification, object: window)
        XCTAssertEqual(sent.map(\.0), [60, 60])
        XCTAssertEqual(sent.map(\.1), [2, 1], "a move to a 1x screen sends 1x pixels")
        scale = 2
        let other = makeWindow(CGSize(width: 100, height: 100)).0
        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: other)
        XCTAssertEqual(sent.count, 2, "another window's screen change is not the video view's")
        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
        XCTAssertEqual(sent.map(\.1), [2, 1, 2])
    }

    func testNothingCoveringSendsZeroAndInvalidateStopsWatching() {
        let (window, view) = makeWindow(CGSize(width: 800, height: 450))
        var sent: [Double] = []
        let feed = SubtitleSafeInsetFeed(view: view, backingScale: { _ in 2 }) { points, _ in sent.append(points) }
        feed.update(covered: 0, videoSize: nil)
        XCTAssertEqual(sent, [0])
        feed.update(covered: 40, videoSize: nil)
        feed.invalidate()
        window.setContentSize(CGSize(width: 900, height: 450))
        XCTAssertEqual(sent, [0, 40])
    }
}
