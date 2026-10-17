import MXRCore
import MXRMockBackend
@testable import MXRUI
import XCTest

final class LibraryInteractionTests: XCTestCase {
    /// L05: playing a row replaces the current item and keeps what the user queued (key frames
    /// 11m45.8s/11m57.0s), instead of replacing the queue with the whole loaded page.
    @MainActor
    func testPlayingARowReplacesOnlyTheCurrentItem() throws {
        let app = AppModel.mock(.playingEpisode)
        let upcoming = app.queue.items.dropFirst().map(\.media.id)
        app.library.navigate(to: .folder("wand-s01"))
        let e10 = try XCTUnwrap(app.library.entries.first { $0.media?.episode?.episode == 10 })
        MXRLibraryActions.open(e10, app: app)
        XCTAssertEqual(app.player.media?.id, e10.media?.id)
        XCTAssertEqual(app.queue.items.map(\.media.id), [e10.media!.id] + upcoming)
        XCTAssertTrue(MXRLibraryActions.isCurrentMedia(e10.media!, app: app))
        // An item that is already queued is jumped to, not duplicated.
        let e06 = try XCTUnwrap(app.library.entries.first { $0.media?.episode?.episode == 6 })
        MXRLibraryActions.open(e06, app: app)
        XCTAssertEqual(app.player.media?.id, e06.media?.id)
        XCTAssertEqual(app.queue.items.count, 1 + upcoming.count)
    }

    @MainActor
    func testClickSelectsAndModifiersExtendTheSelection() throws {
        let app = AppModel.mock(.idle)
        let library = app.library
        library.navigate(to: .folder("wand-s01"))
        library.select(library.entries[0])
        XCTAssertEqual(library.selection, [library.entries[0].id])
        library.select(library.entries[3], extending: true)
        XCTAssertEqual(library.selection.count, 4)
        library.select(library.entries[1], toggling: true)
        XCTAssertEqual(library.selection.count, 3)
        library.moveSelection(by: 1)
        XCTAssertEqual(library.selection.count, 1)
        XCTAssertNil(app.player.media, "selecting never starts playback")
        library.navigate(to: .videos)
        XCTAssertTrue(library.selection.isEmpty)
    }

    @MainActor
    func testAudioAttachmentRecognizesCurrentURLAcrossLibraryAndPlayerIDs() throws {
        let app = AppModel.mock(.playingEpisode)
        let current = try XCTUnwrap(app.player.media)
        var libraryItem = current
        libraryItem.id = "ml:equivalent-library-item"
        XCTAssertTrue(MXRLibraryActions.isCurrentMedia(libraryItem, app: app))
        var other = libraryItem
        other.id = "ml:other-item"
        other.mrl = URL(fileURLWithPath: "/Users/Shared/Media/other.mp4").absoluteString
        XCTAssertFalse(MXRLibraryActions.isCurrentMedia(other, app: app))
        let idle = AppModel.mock(.idle)
        XCTAssertFalse(MXRLibraryActions.isCurrentMedia(libraryItem, app: idle))
    }

    @MainActor
    func testOpeningFolderNavigatesWithoutReplacingPlayback() throws {
        let app = AppModel.mock(.playingEpisode)
        let current = app.player.media?.id
        app.library.select(.videos)
        let folder = try XCTUnwrap(app.library.entries.first)
        MXRLibraryActions.open(folder, app: app)
        XCTAssertEqual(app.library.location, folder.destination)
        XCTAssertEqual(app.player.media?.id, current)
    }

    @MainActor
    func testOpeningMediaWithAnEmptyQueuePlaysThatItem() throws {
        let app = AppModel.mock(.idle)
        app.library.navigate(to: .folder("wand-s01"))
        let entry = try XCTUnwrap(app.library.entries.first(where: { $0.media != nil }))
        MXRLibraryActions.open(entry, app: app)
        XCTAssertEqual(app.player.media?.id, entry.media?.id)
        XCTAssertEqual(app.queue.items.map(\.media.id), [entry.media!.id])
    }

    @MainActor
    func testAddRowsRequestAppropriateNativeFlow() {
        let app = AppModel.mock(.idle)
        MXRLibraryActions.add(.add, app: app)
        XCTAssertEqual(app.interface.fileRequest, .addLibraryFolder)
        app.complete(.addLibraryFolder, urls: [])
        MXRLibraryActions.add(.addNetworkStream, app: app)
        XCTAssertEqual(app.interface.sheet, .openNetworkStream)
        app.interface.dismissSheet()
        MXRLibraryActions.add(.createPlaylist, app: app)
        XCTAssertEqual(app.interface.sheet, .newPlaylist)
    }

    @MainActor
    func testEnqueueContainerIncludesEntireFolder() async throws {
        let app = AppModel.mock(.idle)
        let entry = LibraryEntry.folder(LibraryFolder(id: "wand-s01", name: "S01"))
        await MXRLibraryActions.enqueue(entry, app: app, next: false)
        XCTAssertEqual(app.queue.items.count, 15)
    }

    @MainActor
    func testSourceBrowserTraversesContainersAndReturnsToChooser() async throws {
        let model = LibrarySourceBrowserModel(backend: AppModel.mock(.idle).backends.mediaSources)
        let source = try XCTUnwrap(model.sources.first)
        await model.browse(source)
        let share = try XCTUnwrap(model.nodes.first)
        XCTAssertTrue(share.isContainer)
        await model.open(share)
        XCTAssertEqual(model.path, [share])
        XCTAssertFalse(try XCTUnwrap(model.nodes.first).isContainer)
        await model.goBack()
        XCTAssertTrue(model.path.isEmpty)
        await model.goBack()
        XCTAssertNil(model.source)
        XCTAssertFalse(model.sources.isEmpty)
    }

    @MainActor
    func testFolderDialogActionsCarrySelectedMediaWithoutStartingPlayback() async {
        let app = AppModel.mock(.idle)
        let folder = LibraryEntry.folder(LibraryFolder(id: "wand-s01", name: "S01"))
        await MXRLibraryActions.newPlaylist(for: folder, app: app)
        XCTAssertEqual(app.interface.pendingPlaylistMedia.count, 15)
        XCTAssertNil(app.player.media)
        app.interface.dismissSheet()
        await MXRLibraryActions.addSubtitles(for: folder, scope: .folder, app: app)
        XCTAssertEqual(app.interface.subtitleTargetMedia.count, 15)
        XCTAssertEqual(app.interface.sheet, .addSubtitles(scope: .folder, source: .computer))
        XCTAssertNil(app.player.media)
    }

    @MainActor
    func testChangingSourceCategoryDiscardsOlderChildRequest() async {
        let backend = DelayedSourceBackend()
        let model = LibrarySourceBrowserModel(backend: backend)
        let request = Task { await model.browse(backend.source) }
        while backend.pending == nil { await Task.yield() }
        model.select(.internet)
        backend.pending?.resume(returning: [MediaSourceNode(id: "old", title: "Old share", mrl: "smb://old/", isContainer: true)])
        await request.value
        XCTAssertEqual(model.category, .internet)
        XCTAssertNil(model.source)
        XCTAssertTrue(model.nodes.isEmpty)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testMiniQueueDropImportsURLAndReordersKnownQueueItem() throws {
        let app = AppModel.mock(.idle)
        XCTAssertTrue(LibraryQueueDrop.apply("file:///tmp/first.mp4", at: 0, app: app))
        XCTAssertTrue(LibraryQueueDrop.apply("https://example.test/second.mp4", at: 1, app: app))
        let second = try XCTUnwrap(app.queue.items.last)
        XCTAssertTrue(LibraryQueueDrop.apply("mxr-queue:\(second.id)", at: 0, app: app))
        XCTAssertEqual(app.queue.items.first?.id, second.id)
        XCTAssertFalse(LibraryQueueDrop.apply("mxr-queue:999999", at: 0, app: app))
        XCTAssertFalse(LibraryQueueDrop.apply("plain words", at: 0, app: app))
        XCTAssertEqual(app.queue.items.count, 2)
        XCTAssertTrue(LibraryQueueDrop.apply("file:///tmp/a.mp4\nfile:///tmp/b.mp4", at: 2, app: app), "a multi-row library drag")
        XCTAssertEqual(app.queue.items.count, 4)
    }

    @MainActor
    func testExplicitShuffleKeepsExistingRandomOrderEnabled() async {
        let app = AppModel.mock(.idle)
        let folder = LibraryEntry.folder(LibraryFolder(id: "wand-s01", name: "S01"))
        await MXRLibraryActions.shuffleContainer(folder, app: app)
        XCTAssertTrue(app.queue.isShuffled)
        await MXRLibraryActions.shuffleContainer(folder, app: app)
        XCTAssertTrue(app.queue.isShuffled)
        XCTAssertEqual(app.queue.items.count, 15)
    }

    @MainActor
    func testRemovedSourceAncestorReturnsToExistingRoot() async {
        let backend = MutableSourceBackend()
        let model = LibrarySourceBrowserModel(backend: backend)
        await model.browse(backend.source)
        await model.open(backend.share)
        XCTAssertEqual(model.nodes.count, 1)
        backend.hasShare = false
        await model.refreshAfterChange(parentID: nil)
        XCTAssertTrue(model.path.isEmpty)
        XCTAssertTrue(model.nodes.isEmpty)
        XCTAssertEqual(model.source, backend.source)
        XCTAssertNil(model.error)
    }
}

@MainActor private final class DelayedSourceBackend: MediaSourceBackend {
    let source = MediaSourceInfo(id: "smb", title: "SMB", category: .localNetwork)
    var pending: CheckedContinuation<[MediaSourceNode], Error>?
    func sources(in category: MediaSourceCategory) -> [MediaSourceInfo] { category == .localNetwork ? [source] : [] }
    func children(of node: MediaSourceNode?, in source: MediaSourceInfo) async throws -> [MediaSourceNode] {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
}

@MainActor private final class MutableSourceBackend: MediaSourceBackend {
    let source = MediaSourceInfo(id: "smb", title: "SMB", category: .localNetwork)
    let share = MediaSourceNode(id: "share", title: "NAS", mrl: "smb://nas/", isContainer: true)
    var hasShare = true
    func sources(in category: MediaSourceCategory) -> [MediaSourceInfo] { [source] }
    func children(of node: MediaSourceNode?, in source: MediaSourceInfo) async throws -> [MediaSourceNode] {
        if node == nil { return hasShare ? [share] : [] }
        return [MediaSourceNode(id: "movie", title: "Movie", mrl: "smb://nas/movie.mp4", isContainer: false)]
    }
}
