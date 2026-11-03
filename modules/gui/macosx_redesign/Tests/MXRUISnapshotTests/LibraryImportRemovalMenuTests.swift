import MXRCore
import MXRMockBackend
@testable import MXRUI
import XCTest

/// R04: a file added with Add File offers "Remove from Library…" in its right-click menu, for the
/// whole selection, after the same confirmation sheet a root folder's removal uses.
@MainActor
final class LibraryImportRemovalMenuTests: XCTestCase {
    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<400 where !condition() { await Task.yield() }
    }
    private func removal(for media: MediaItem, app: AppModel, sheets: LibrarySheetCenter) -> LibraryMenuItem? {
        LibraryMenus.sections(for: .file(media), app: app, sheets: sheets, rowIndex: nil, dismiss: {}).extras.first { $0.icon == .remove }
    }

    func testImportedFilesOfferRemoveFromLibraryForTheSelection() async throws {
        let app = AppModel.mock(.idle)
        let sheets = LibrarySheetCenter()
        try await app.library.importFiles(urls: [URL(fileURLWithPath: "/tmp/R04/One.mp4"), URL(fileURLWithPath: "/tmp/R04/Two.mp4")])
        await settle { app.library.mediaEntries.filter(\.isImported).count == 2 }
        let imported = app.library.mediaEntries.filter(\.isImported)
        XCTAssertEqual(imported.count, 2)

        app.library.selection = []
        let single = try XCTUnwrap(removal(for: imported[0], app: app, sheets: sheets))
        XCTAssertEqual(single.title, "Remove from Library…")

        app.library.selection = Set(imported.map { LibraryEntry.media($0).id })
        let both = try XCTUnwrap(removal(for: imported[0], app: app, sheets: sheets))
        XCTAssertEqual(both.title, "Remove 2 Files from Library…")
        guard case .perform(let action) = both.kind else { return XCTFail("the row performs") }
        action()
        guard case .removeImports(let targets)? = sheets.sheet else { return XCTFail("removal asks first, like a root folder") }
        XCTAssertEqual(Set(targets.map(\.id)), Set(imported.map(\.id)))
        XCTAssertEqual(Set(app.library.mediaEntries.filter(\.isImported).map(\.id)).count, 2, "nothing leaves before the confirmation")
    }

    func testInsideAPlaylistOnlyRemoveFromPlaylistIsOffered() async throws {
        let app = AppModel.mock(.idle)
        app.library.select(.playlists)
        await settle { !app.library.entries.isEmpty }
        let playlist = try XCTUnwrap(app.library.entries.compactMap { if case .playlist(let p) = $0 { return p }; return nil }.first)
        app.library.navigate(to: .playlist(playlist.id))
        await settle { app.library.contentLocation == .playlist(playlist.id) }
        try await app.library.importFiles(urls: [URL(fileURLWithPath: "/tmp/R04/InPlaylist.mp4")])
        await settle { app.library.mediaEntries.contains(where: \.isImported) }
        let row = try XCTUnwrap(app.library.mediaEntries.first(where: \.isImported), "Add File in a playlist adds the file to it")
        let sections = LibraryMenus.sections(for: .file(row), app: app, sheets: LibrarySheetCenter(), rowIndex: nil, dismiss: {})
        XCTAssertFalse(sections.extras.contains { $0.title.hasSuffix("from Library…") }, "the playlist row would stay: Remove from Library is not offered")
        XCTAssertTrue(sections.figma.contains { $0.title == "Remove from Playlist" })
    }

    func testScannedFilesOfferNoRemoveFromLibrary() async {
        let app = AppModel.mock(.idle)
        let episodes = await app.library.allMedia(at: .folder(MockMediaID.theWandS01Folder))
        guard let episode = episodes.first else { return XCTFail("the mock folder has episodes") }
        XCTAssertNil(removal(for: episode, app: app, sheets: LibrarySheetCenter()), "folder media leave with their folder")
    }
}
