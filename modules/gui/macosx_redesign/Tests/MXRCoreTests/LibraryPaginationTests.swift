import XCTest
@testable import MXRCore
@testable import MXRMockBackend

@MainActor
final class LibraryPaginationTests: XCTestCase {
    func testRepeatedPlaylistPositionsAdvanceOffsetsAndGuardConcurrentLoads() async {
        let backend = ControlledPagingLibrary(count: 5)
        let model = LibraryModel(backend: backend, initialLocation: .playlist("repeated"))
        model.pageSize = 2
        model.reload()
        await backend.waitForRequest()
        backend.finishPage()
        await waitUntilIdle(model)
        XCTAssertEqual(model.entries.count, 2)
        model.loadMoreIfNeeded(at: 1)
        model.loadMoreIfNeeded(at: 1)
        await backend.waitForRequest()
        XCTAssertEqual(backend.offsets, [0, 2], "Only one request may be in flight for an offset.")
        backend.finishPage()
        await waitUntilIdle(model)
        XCTAssertEqual(model.entries.count, 4)
        model.loadMoreIfNeeded(at: 3)
        await backend.waitForRequest()
        backend.finishPage()
        await waitUntilIdle(model)
        XCTAssertEqual(model.entries.count, 5)
        XCTAssertEqual(backend.offsets, [0, 2, 4])
        XCTAssertEqual(Set(model.entries.map(\.id)).count, 1, "Native media identifiers stay unchanged for repeated positions.")
        XCTAssertFalse(model.hasMore)
        model.loadMoreIfNeeded()
        await Task.yield()
        XCTAssertEqual(backend.offsets, [0, 2, 4])
    }

    func testRepeatedTailCanPrefetchBeyondThresholdAndEmptyPageTerminates() async {
        let backend = ControlledPagingLibrary(count: 25, declaredTotal: 30)
        let model = LibraryModel(backend: backend, initialLocation: .stream("repeated"))
        model.pageSize = 25
        model.reload()
        await backend.waitForRequest()
        backend.finishPage()
        await waitUntilIdle(model)
        model.loadMoreIfNeeded(at: 0)
        await Task.yield()
        XCTAssertEqual(backend.offsets, [0], "An early row does not prefetch before the threshold.")
        model.loadMoreIfNeeded(after: model.entries.last)
        await backend.waitForRequest()
        XCTAssertEqual(backend.offsets, [0, 25], "A repeated tail row must not resolve to the first occurrence.")
        backend.finishPage()
        await waitUntilIdle(model)
        XCTAssertEqual(model.entries.count, 25)
        XCTAssertFalse(model.hasMore, "An empty page ends pagination even if a stale total advertises more rows.")
        model.loadMoreIfNeeded(at: 24)
        await Task.yield()
        XCTAssertEqual(backend.offsets, [0, 25])
    }

    private func waitUntilIdle(_ model: LibraryModel) async {
        while model.isLoading || model.isLoadingMore { await Task.yield() }
    }
}

/// Delays only paging; unrelated methods forward to the existing deterministic mock.
@MainActor
private final class ControlledPagingLibrary: LibraryBackend {
    let wrapped = MockBackend(scenario: .idle).library
    let rows: [LibraryEntry]
    let declaredTotal: Int
    private(set) var offsets: [Int] = []
    private var pending: (LibraryLocation, LibraryQuery, CheckedContinuation<LibraryPage, Error>)?
    init(count: Int, declaredTotal: Int? = nil) {
        let item = MediaItem(id: "ml:42", mrl: "https://fixture.invalid/repeated.mp4", title: "Repeated", kind: .video)
        rows = Array(repeating: .media(item), count: count)
        self.declaredTotal = declaredTotal ?? count
    }
    func page(at location: LibraryLocation, query: LibraryQuery) async throws -> LibraryPage {
        offsets.append(query.offset)
        return try await withCheckedThrowingContinuation { pending = (location, query, $0) }
    }
    func waitForRequest() async {
        for _ in 0..<10_000 where pending == nil { await Task.yield() }
        XCTAssertNotNil(pending, "Expected the next page request.")
    }
    func finishPage() {
        guard let (location, query, continuation) = pending else { return }
        pending = nil
        let start = min(query.offset, rows.count)
        let end = min(start + query.limit, rows.count)
        continuation.resume(returning: LibraryPage(location: location, entries: Array(rows[start..<end]), totalCount: declaredTotal, offset: query.offset))
    }
    func breadcrumb(for location: LibraryLocation) async -> [LibraryCrumb] { [LibraryCrumb(title: "Repeated", location: location)] }
    func homeSections() async throws -> [LibraryHomeSection] { try await wrapped.homeSections() }
    func allMedia(at location: LibraryLocation, sort: LibrarySort) async throws -> [MediaItem] { try await wrapped.allMedia(at: location, sort: sort) }
    func media(id: String) async -> MediaItem? { await wrapped.media(id: id) }
    var mediaCount: Int { wrapped.mediaCount }
    var isIndexing: Bool { wrapped.isIndexing }
    func setFavorite(_ favorite: Bool, mediaIDs: [String]) { wrapped.setFavorite(favorite, mediaIDs: mediaIDs) }
    func setWatched(_ watched: Bool, mediaIDs: [String]) { wrapped.setWatched(watched, mediaIDs: mediaIDs) }
    func attachSubtitle(url: URL, toMedia mediaID: String) { wrapped.attachSubtitle(url: url, toMedia: mediaID) }
    func clearHistory() { wrapped.clearHistory() }
    func createPlaylist(name: String, mediaIDs: [String], artworkURL: URL?) async throws -> Playlist { try await wrapped.createPlaylist(name: name, mediaIDs: mediaIDs, artworkURL: artworkURL) }
    func appendToPlaylist(id: String, mediaIDs: [String]) async throws { try await wrapped.appendToPlaylist(id: id, mediaIDs: mediaIDs) }
    func removeFromPlaylist(id: String, occurrences: [PlaylistOccurrence]) async throws { try await wrapped.removeFromPlaylist(id: id, occurrences: occurrences) }
    func renamePlaylist(id: String, name: String) async throws { try await wrapped.renamePlaylist(id: id, name: name) }
    func deletePlaylist(id: String) async throws { try await wrapped.deletePlaylist(id: id) }
    func setPlaylistFavorite(_ favorite: Bool, id: String) { wrapped.setPlaylistFavorite(favorite, id: id) }
    func addNetworkStream(urls: [URL], name: String?) async throws -> NetworkStream { try await wrapped.addNetworkStream(urls: urls, name: name) }
    func removeNetworkStream(id: String) async throws { try await wrapped.removeNetworkStream(id: id) }
    func addFolder(url: URL) { wrapped.addFolder(url: url) }
    func removeFolder(id: String) { wrapped.removeFolder(id: id) }
    func rescan(folderID: String?) { wrapped.rescan(folderID: folderID) }
    func bookmarks(mediaID: String) async -> [Bookmark] { await wrapped.bookmarks(mediaID: mediaID) }
    func addBookmark(mediaID: String, time: MediaTime, name: String) async throws -> Bookmark { try await wrapped.addBookmark(mediaID: mediaID, time: time, name: name) }
    func renameBookmark(id: String, mediaID: String, name: String) async throws { try await wrapped.renameBookmark(id: id, mediaID: mediaID, name: name) }
    func removeBookmark(id: String, mediaID: String) async throws { try await wrapped.removeBookmark(id: id, mediaID: mediaID) }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (LibraryEvent) -> Void) { wrapped.addListener(owner, handler: handler) }
}
