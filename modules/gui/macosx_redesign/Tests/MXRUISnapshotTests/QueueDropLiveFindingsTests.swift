import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
import SwiftUI
@testable import MXRUI
import XCTest

/// Live run 2 (G-panels): a library row dropped onto the open queue replaced the queue and played
/// the row. The 12 pt gaps between rows and the space under the last row had no queue drop target,
/// so the drop reached the window's open-and-play handler. The list now has one drop target over
/// its whole area that inserts at the row boundary under the pointer.
@MainActor
final class QueueDropLiveFindingsTests: XCTestCase {
    private let row = Theme.Metric.SidePanels.listRow.height
    private let gap = PanelMetric.gap

    private func index(_ y: CGFloat, count: Int = 3, placeholder: Int? = nil) -> Int {
        PanelQueueInteraction.dropIndex(atY: y, count: count, rowHeight: row, gap: gap, placeholder: placeholder)
    }

    /// Every point of the list maps to an insertion index: the gaps between rows (where the drop
    /// used to fall through) and the empty space below the last row included.
    func testEveryPointOfTheListHasAnInsertionIndex() {
        let pitch = row + gap
        XCTAssertEqual(index(0), 0, "top half of row 1: before it")
        XCTAssertEqual(index(row * 0.75), 1, "bottom half of row 1: after it")
        XCTAssertEqual(index(row + gap / 2), 1, "the gap between rows 1 and 2")
        XCTAssertEqual(index(pitch + row + gap / 2), 2, "the gap between rows 2 and 3")
        XCTAssertEqual(index(3 * pitch + 2), 3, "just below the last row")
        XCTAssertEqual(index(10_000), 3, "far below the last row: appended")
        XCTAssertEqual(index(-20), 0)
        XCTAssertEqual(index(40, count: 0), 0, "an empty queue")
    }

    /// While the "•••" row is shown it takes a row slot; the pointer over it keeps its index, and
    /// rows below it are measured one slot lower (no flicker as the placeholder opens).
    func testPlaceholderSlotIsStable() {
        let pitch = row + gap
        XCTAssertEqual(index(pitch + row / 2, placeholder: 1), 1, "over the placeholder")
        XCTAssertEqual(index(pitch - gap / 2, placeholder: 1), 1, "its top gap")
        XCTAssertEqual(index(2 * pitch + row * 0.25, placeholder: 1), 1, "top half of the row pushed below it")
        XCTAssertEqual(index(2 * pitch + row * 0.75, placeholder: 1), 2, "bottom half of that row")
        XCTAssertEqual(index(row * 0.25, placeholder: 1), 0, "above the placeholder")
    }

    /// The drop inserts the library row at the index and leaves the current item playing.
    func testLibraryRowDropInsertsAtTheDropPointWithoutReplacingTheQueue() async throws {
        let app = AppModel.mock(.playingEpisode)
        let before = app.queue.items
        let playing = app.player.media?.id
        XCTAssertGreaterThan(before.count, 2)
        let url = URL(fileURLWithPath: "/tmp/Dropped Clip.mp4")
        let done = expectation(description: "inserted")
        let accepted = PanelQueueInteraction.acceptDrop([NSItemProvider(object: url as NSURL)], at: 1, queue: app.queue) { done.fulfill() }
        XCTAssertTrue(accepted)
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(app.queue.items.count, before.count + 1)
        XCTAssertEqual(app.queue.items[1].media.mrl, url.absoluteString)
        XCTAssertEqual(app.queue.items[0].id, before[0].id)
        XCTAssertEqual(app.queue.items.dropFirst(2).map(\.id), before.dropFirst().map(\.id))
        XCTAssertEqual(app.player.media?.id, playing, "playback is untouched")
    }

    /// Live run 2 polish: Move Up and Move Down are disabled where they cannot apply.
    func testMoveItemsAreDisabledAtTheEnds() {
        let app = AppModel.mock(.playingEpisode)
        let item = app.queue.items[0]
        let addToPlaylist = PanelQueueInteraction.addToPlaylistMenu(app, for: item)
        let only = PanelQueueInteraction.rowMenu(play: {}, addToPlaylist: addToPlaylist, moveUp: nil, moveDown: nil, remove: {})
        XCTAssertEqual(only.filter { $0.title.hasPrefix("Move") }.map(\.isEnabled), [false, false])
        let middle = PanelQueueInteraction.rowMenu(play: {}, addToPlaylist: addToPlaylist, moveUp: {}, moveDown: {}, remove: {})
        XCTAssertEqual(middle.filter { $0.title.hasPrefix("Move") }.map(\.isEnabled), [true, true])
    }
}

/// Live run 2 polish: the track popover lists the tracks of the media it opened for; a new file
/// closes it instead of leaving it open over a different file's tracks.
@MainActor
final class TrackPopoverMediaChangeTests: XCTestCase {
    private var windows: [NSWindow] = []
    override func tearDown() async throws { windows.forEach { $0.close() }; windows = [] }

    func testOpeningAnotherFileClosesTheTrackPopover() async throws {
        let app = AppModel.mock(.playingEpisode)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 460), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        app.interface.toggleTracks(.subtitles)
        XCTAssertTrue(app.interface.isTracksPanelOpen)
        window.contentView = NSHostingView(rootView: MXRTrackPopoverView(tab: .subtitles).appModel(app))
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(app.interface.isTracksPanelOpen, "nothing changed yet")
        let next = try XCTUnwrap(app.queue.items.first { !app.queue.isCurrent($0) })
        app.queue.play(next)
        for _ in 0..<20 where app.interface.isTracksPanelOpen {
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertNotEqual(app.player.media?.id, nil)
        XCTAssertFalse(app.interface.isTracksPanelOpen)
    }
}
