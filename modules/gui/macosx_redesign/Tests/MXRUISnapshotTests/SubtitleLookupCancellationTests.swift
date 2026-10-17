import Foundation
import MXRCore
import MXRMockBackend
@testable import MXRUI
import XCTest

final class SubtitleLookupCancellationTests: XCTestCase {
    @MainActor
    func testCancelledFolderLoadPublishesNothing() async {
        let video = URL(fileURLWithPath: "/tmp/Show.mp4")
        let barrier = SubtitleLookupBarrier()
        let draft = SubtitleImportDraft(scope: .file, source: .computer, media: [MediaItem(url: video)],
                                        listVideos: { _ in barrier.resolve([video]) })
        draft.scope = .folder
        let app = AppModel.mock(.idle)
        let load = Task { await draft.loadTargets(from: app) }
        var started = barrier.started.makeAsyncIterator()
        await started.next()
        load.cancel()
        barrier.release.signal()
        await load.value
        XCTAssertTrue(draft.media.isEmpty)
        XCTAssertTrue(draft.assignments.isEmpty)
        XCTAssertNil(draft.error)
    }

    @MainActor
    func testCancelledRememberedLookupNeverAttaches() async {
        let video = URL(fileURLWithPath: "/tmp/Show.mp4")
        let subtitle = URL(string: "https://example.com/Show.srt")!
        let barrier = SubtitleLookupBarrier()
        let app = AppModel.mock(.idle)
        let store = SubtitleFolderRulesStore(rules: SubtitleFolderRules())
        let load = Task {
            await store.apply(to: MediaItem(url: video), tracks: app.tracks,
                              resolve: { _, _ in barrier.resolve([subtitle]) })
        }
        var started = barrier.started.makeAsyncIterator()
        await started.next()
        load.cancel()
        barrier.release.signal()
        await load.value
        XCTAssertTrue(app.tracks.externalTracks(of: .subtitle).isEmpty)
    }
}

extension SubtitleLookupCancellationTests {
    /// Lookups run one at a time; one cancelled while it waits behind another never touches the disk.
    @MainActor
    func testLookupCancelledWhileQueuedSkipsItsFilesystemWork() async {
        let video = URL(fileURLWithPath: "/tmp/Show.mp4")
        let barrier = SubtitleLookupBarrier()
        let app = AppModel.mock(.idle)
        let store = SubtitleFolderRulesStore(rules: SubtitleFolderRules())
        let first = Task { await store.apply(to: MediaItem(url: video), tracks: app.tracks, resolve: { _, _ in barrier.resolve([]) }) }
        var started = barrier.started.makeAsyncIterator()
        await started.next()
        let queuedRan = LockedFlag()
        let second = Task { await store.apply(to: MediaItem(url: video), tracks: app.tracks, resolve: { _, _ in queuedRan.set(); return [] }) }
        await Task.yield()
        second.cancel()
        barrier.release.signal()
        await first.value
        await second.value
        XCTAssertFalse(queuedRan.value)
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}

private final class SubtitleLookupBarrier: @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    let started: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    init() { (started, continuation) = AsyncStream.makeStream() }
    func resolve(_ urls: [URL]) -> [URL] {
        continuation.yield(())
        release.wait()
        return urls
    }
}
