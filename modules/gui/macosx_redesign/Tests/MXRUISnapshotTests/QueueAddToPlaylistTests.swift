import MXRCore
import MXRDesign
import MXRMockBackend
@testable import MXRUI
import XCTest

/// The queue row's "Add to Playlist" submenu (critic P2): it lists the library's playlists once
/// opened and adds the row, or the whole selection in queue order, to the chosen one.
@MainActor
final class QueueAddToPlaylistTests: XCTestCase {
    private func playlistMedia(_ library: MockLibrary, _ id: String) async throws -> [String] {
        try await library.page(at: .playlist(id), query: LibraryQuery(sort: .oldestFirst)).entries.compactMap(\.media?.id)
    }

    func testQueueRowAddsTheSelectionInQueueOrder() async throws {
        let app = AppModel.mock(.playingEpisode)
        let library = try XCTUnwrap(app.backends.library as? MockLibrary)
        let items = app.queue.items
        XCTAssertGreaterThanOrEqual(items.count, 3)
        app.queue.selection = [items[2].id, items[0].id]

        let menu = PanelQueueInteraction.addToPlaylistMenu(app, for: items[2])
        XCTAssertEqual(menu.title, "Add to Playlist")
        menu.onOpen?()
        for _ in 0..<400 where app.library.playlists.isEmpty { await Task.yield() }
        let playlist = try XCTUnwrap(app.library.playlists.first)
        let before = try await playlistMedia(library, playlist.id)
        let children = try XCTUnwrap(menu.children)
        XCTAssertEqual(children.first?.title, "New Playlist…")
        let row = try XCTUnwrap(children.first { $0.title == playlist.name })
        guard case .action(let add) = row.kind else { return XCTFail("a playlist row is an action") }
        add()
        var after = before
        for _ in 0..<400 where after.count == before.count { await Task.yield(); after = try await playlistMedia(library, playlist.id) }
        XCTAssertEqual(Array(after.dropFirst(before.count)), [items[0].media.id, items[2].media.id],
                       "the selection is appended in queue order")

        // A row outside the selection adds just itself.
        let single = PanelQueueInteraction.addToPlaylistMenu(app, for: items[1])
        guard case .action(let addOne) = try XCTUnwrap(single.children?.first { $0.title == playlist.name }).kind else { return XCTFail() }
        addOne()
        var last = after
        for _ in 0..<400 where last.count == after.count { await Task.yield(); last = try await playlistMedia(library, playlist.id) }
        XCTAssertEqual(Array(last.dropFirst(after.count)), [items[1].media.id])
    }
}
