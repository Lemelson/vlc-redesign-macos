import XCTest
@testable import MXRCore
import MXRMockBackend

@MainActor
final class OpenAutoplayTests: XCTestCase {
    func testOpenPassesInitialPausePreferenceButLibraryPlayIsExplicit() throws {
        let mock = MockBackend(scenario: .idle)
        let queue = OpeningQueue()
        let original = mock.backends
        let backends = Backends(player: original.player, clock: original.clock, queue: queue, library: original.library, mediaSources: original.mediaSources, settings: original.settings, shortcuts: original.shortcuts, dialogs: original.dialogs, extensions: original.extensions, thumbnails: original.thumbnails, osd: original.osd, capabilities: original.capabilities)
        let app = AppModel(backends: backends, persistence: .inMemory, clockTicks: false)
        let url = URL(fileURLWithPath: "/tmp/autoplay-test.mp4")
        mock.settings.setValue(.bool(false), for: "playlist-autostart", apply: .nextMedia)
        app.open(urls: [url])
        XCTAssertEqual(queue.lastOptions, [])
        XCTAssertEqual(queue.lastStartPaused, true)
        try app.open(urls: [url], inputOptions: [":network-caching=500"])
        XCTAssertEqual(queue.lastOptions, [":network-caching=500"])
        XCTAssertEqual(queue.lastStartPaused, true)
        app.play(MediaItem(url: url))
        XCTAssertEqual(queue.lastOptions, [])
        XCTAssertEqual(queue.lastStartPaused, false)
        mock.settings.setValue(.bool(true), for: "playlist-autostart", apply: .nextMedia)
        app.open(urls: [url])
        XCTAssertEqual(queue.lastStartPaused, false)
    }
}
@MainActor
private final class OpeningQueue: PlayQueueBackend, QueueInputOptionsBackend {
    var lastOptions: [String] = []
    var lastStartPaused = false
    var items: [QueueItem] = []
    var currentIndex: Int? = nil
    var repeatMode: RepeatMode = .off
    var order: PlaybackOrder = .normal
    var mediaStoppedAction: MediaStoppedAction = .continue
    var hasNext = false
    var hasPrevious = false
    func playNow(_ media: [MediaItem], startAt index: Int, inputOptions: [String], startPaused: Bool) throws { lastOptions = inputOptions; lastStartPaused = startPaused }
    func play(at index: Int) {}
    func start() {}
    func next() {}
    func previous() {}
    func insert(_ media: [MediaItem], at index: Int?) {}
    func move(ids: [QueueItem.ID], to index: Int) {}
    func remove(ids: [QueueItem.ID]) {}
    func clear() {}
    func sort(_ sort: QueueSort) {}
    func setRepeatMode(_ mode: RepeatMode) {}
    func setOrder(_ order: PlaybackOrder) {}
    func setMediaStoppedAction(_ action: MediaStoppedAction) {}
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (QueueEvent) -> Void) {}
}
