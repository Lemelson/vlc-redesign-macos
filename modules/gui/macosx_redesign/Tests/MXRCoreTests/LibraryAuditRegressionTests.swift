import XCTest
@testable import MXRCore
@testable import MXRMockBackend

@MainActor
final class LibraryAuditRegressionTests: XCTestCase {
    func testAudioFolderUsesResolvedMusicSorts() async {
        let library = LibraryModel(backend: MockBackend(scenario: .idle).library,
                                   initialLocation: .folder(MockMediaID.mySongsFolder))
        while library.isLoading { await Task.yield() }
        XCTAssertEqual(library.category, .music)
        XCTAssertTrue(library.availableSorts.contains(.artistAscending))
        XCTAssertTrue(library.availableSorts.contains(.albumAscending))
        XCTAssertFalse(library.availableSorts.contains(.watchedFirst))
    }
}

@MainActor
extension LibraryAuditRegressionTests {
    private func makePlaylist(_ backend: MockLibrary) async throws -> Playlist {
        try await backend.createPlaylist(name: "Occurrence regression", mediaIDs: ["https://fixture.invalid/Alpha.mp4", "https://fixture.invalid/Bravo.mp4", "https://fixture.invalid/Charlie.mp4", "https://fixture.invalid/Alpha.mp4"], artworkURL: nil)
    }
    func testDuplicateSelectionAndPagedIdentityPreserveNativeMediaID() async throws {
        let backend = MockBackend(scenario: .idle).library
        let playlist = try await makePlaylist(backend)
        let first = try await backend.page(at: .playlist(playlist.id), query: LibraryQuery(sort: .titleAscending, limit: 2))
        XCTAssertEqual(first.entries.map(\.media?.id), ["https://fixture.invalid/Alpha.mp4", "https://fixture.invalid/Alpha.mp4"])
        XCTAssertEqual(Set(first.entries.map(\.id)).count, 2)
        XCTAssertEqual(first.entries.compactMap(\.media?.playlistOccurrence?.position), [0, 3])
        let model = LibraryModel(backend: backend, initialLocation: .playlist(playlist.id))
        while model.isLoading { await Task.yield() }
        model.setSort(.titleAscending)
        while model.isLoading { await Task.yield() }
        model.select(model.entries[0])
        XCTAssertEqual(model.selection.count, 1)
        XCTAssertFalse(model.selection.contains(model.entries[1].id))
        XCTAssertEqual(model.moveSelection(by: 1)?.id, model.entries[1].id)
    }
    func testFilteredRemovalUsesCapturedStoragePositionAndRejectsStaleRevision() async throws {
        let backend = MockBackend(scenario: .idle).library
        let playlist = try await makePlaylist(backend)
        let location = LibraryLocation.playlist(playlist.id)
        let filtered = try await backend.page(at: location, query: LibraryQuery(searchText: "Charlie", offset: 0, limit: 1))
        let occurrence = try XCTUnwrap(filtered.entries.first?.media?.playlistOccurrence)
        XCTAssertEqual(occurrence.position, 2)
        try await backend.removeFromPlaylist(id: playlist.id, occurrences: [occurrence])
        let remaining = try await backend.page(at: location, query: LibraryQuery(sort: .titleAscending))
        XCTAssertEqual(remaining.entries.map(\.title), ["Alpha.mp4", "Alpha.mp4", "Bravo.mp4"])
        do {
            try await backend.removeFromPlaylist(id: playlist.id, occurrences: [occurrence])
            XCTFail("A stale occurrence must fail closed")
        } catch { }
        let unchanged = try await backend.page(at: location, query: LibraryQuery())
        XCTAssertEqual(unchanged.totalCount, 3)
    }
    func testHomeShowAllRetainsSectionMembershipAndRanking() async throws {
        let backend = MockBackend(scenario: .idle).library
        for section in try await backend.homeSections() {
            let destination = try XCTUnwrap(section.destination)
            XCTAssertEqual(destination, .homeSection(section.kind))
            let page = try await backend.page(at: destination, query: LibraryQuery(sort: .titleDescending))
            XCTAssertEqual(page.entries, section.entries)
            let model = LibraryModel(backend: backend, initialLocation: destination)
            while model.isLoading { await Task.yield() }
            XCTAssertTrue(model.availableSorts.isEmpty, "Ranked section pages must not offer ignored sorts")
            let crumbs = await backend.breadcrumb(for: destination)
            XCTAssertEqual(crumbs.first?.location, .home)
            XCTAssertEqual(crumbs.last?.title, section.title)
        }
    }
}

@MainActor
extension LibraryAuditRegressionTests {
    func testRepeatedPlaylistRowsHaveSeparateSelectionIdentity() async throws {
        let backend = MockBackend(scenario: .idle).library
        let playlist = try await backend.createPlaylist(name: "Duplicates", mediaIDs: ["https://fixture.invalid/Alpha.mp4", "https://fixture.invalid/Alpha.mp4"], artworkURL: nil)
        let page = try await backend.page(at: .playlist(playlist.id), query: LibraryQuery())
        XCTAssertEqual(Set(page.entries.map(\.id)).count, 2)
    }
    func testShowAllDestinationPreservesHomeMembership() async throws {
        let backend = MockBackend(scenario: .idle).library
        let sections = try await backend.homeSections()
        for section in sections {
            let destination = try XCTUnwrap(section.destination)
            let page = try await backend.page(at: destination, query: LibraryQuery(sort: .newestFirst))
            // Home shows the first `homeLimit` entries of the section's page, in the same order.
            XCTAssertLessThanOrEqual(section.entries.count, section.kind.homeLimit, section.title)
            XCTAssertEqual(page.entries.prefix(section.entries.count).map(\.id), section.entries.map(\.id), section.title)
        }
    }
}

@MainActor
extension LibraryAuditRegressionTests {
    func testExplicitImportIsBrowseableBeforePlayback() async throws {
        let backend = MockBackend(scenario: .idle).library
        let url = URL(fileURLWithPath: "/tmp/LibraryAuditImport.mp4")
        try await backend.importFiles(urls: [url, url])
        let page = try await backend.page(at: .videos, query: LibraryQuery())
        XCTAssertEqual(page.entries.compactMap(\.media).filter { $0.mrl == url.absoluteString }.count, 1)
        let imported = await backend.media(id: url.absoluteString)
        XCTAssertNil(imported?.lastPlayedDate)
    }
}
