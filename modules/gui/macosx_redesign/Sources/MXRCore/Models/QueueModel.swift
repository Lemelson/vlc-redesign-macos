import Foundation
import Observation

/// The play queue (right panel Queue tab S22, mini player S46) and prev/next for the control bar.
@MainActor
@Observable
public final class QueueModel {
    public private(set) var items: [QueueItem] = []
    public private(set) var currentIndex: Int?
    public private(set) var repeatMode: RepeatMode = .off
    public private(set) var order: PlaybackOrder = .normal
    public private(set) var mediaStoppedAction: MediaStoppedAction = .continue
    public private(set) var hasNext = false
    public private(set) var hasPrevious = false
    /// Rows selected in the Queue tab (the "−" button removes them). UI-owned, kept here so all views agree.
    public var selection: Set<QueueItem.ID> = []

    public private(set) var errorMessage: String?
    @ObservationIgnored public var errorHandler: (@MainActor (Error) -> Void)?

    @ObservationIgnored public let backend: any PlayQueueBackend

    public init(backend: any PlayQueueBackend) {
        self.backend = backend
        backend.addListener(self) { [weak self] event in
            self?.handle(event)
        }
        reloadItems()
        reloadCurrent()
        reloadMode()
    }

    // MARK: Derived

    public var currentItem: QueueItem? {
        guard let currentIndex, items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }
    public var isEmpty: Bool { items.isEmpty }
    public var isShuffled: Bool { order == .random }
    /// Sum of known durations.
    public var totalDuration: MediaTime {
        items.reduce(.zero) { $0 + ($1.media.duration ?? .zero) }
    }
    /// Header text: "4 items - 2h 3m", "1 item - 23m".
    public var summary: String {
        let count = items.count == 1 ? "1 item" : "\(items.count) items"
        guard totalDuration > .zero else { return count }
        return count + " - " + totalDuration.formatted(.summary)
    }
    /// True when `item` is the current one (orange row with ▶).
    public func isCurrent(_ item: QueueItem) -> Bool { currentItem?.id == item.id }

    // MARK: Transport

    public func next() { backend.next() }
    public func previous() { backend.previous() }
    public func play(_ item: QueueItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        backend.play(at: index)
    }

    // MARK: Editing

    /// Replaces the queue with `media` and plays the item at `startIndex` (library "Play").
    public func playNow(_ media: [MediaItem], startAt startIndex: Int = 0) {
        guard !media.isEmpty else { return }
        if let atomic = backend as? any QueueInputOptionsBackend {
            do { try atomic.playNow(media, startAt: startIndex, inputOptions: []); errorMessage = nil }
            catch { errorMessage = error.localizedDescription; errorHandler?(error) }
        } else {
            backend.clear()
            backend.insert(media, at: nil)
            backend.play(at: min(max(startIndex, 0), media.count - 1))
            errorMessage = nil
        }
    }
    /// Appends to the end ("Add to Queue", drop at the end of the panel).
    public func enqueue(_ media: [MediaItem]) { backend.insert(media, at: nil) }
    /// Inserts after the current item.
    public func playNext(_ media: [MediaItem]) {
        backend.insert(media, at: currentIndex.map { $0 + 1 })
    }
    /// Inserts at a drop position.
    public func insert(_ media: [MediaItem], at index: Int) { backend.insert(media, at: index) }
    /// Moves items (drag to reorder).
    public func move(_ ids: [QueueItem.ID], to index: Int) { backend.move(ids: ids, to: index) }
    public func remove(_ ids: [QueueItem.ID]) {
        backend.remove(ids: ids)
        selection.subtract(ids)
    }
    /// The "−" button.
    public func removeSelection() { remove(Array(selection)) }
    public func clear() {
        backend.clear()
        selection = []
    }
    public func sort(by key: QueueSortKey, ascending: Bool = true) { backend.sort(QueueSort(key: key, ascending: ascending)) }

    // MARK: Modes

    /// The repeat button: off → all → one → off.
    public func cycleRepeatMode() { backend.setRepeatMode(repeatMode.next) }
    public func setRepeatMode(_ mode: RepeatMode) { backend.setRepeatMode(mode) }
    /// The shuffle button.
    public func toggleShuffle() { backend.setOrder(order == .random ? .normal : .random) }
    public func setMediaStoppedAction(_ action: MediaStoppedAction) { backend.setMediaStoppedAction(action) }

    // MARK: Events

    private func handle(_ event: QueueEvent) {
        switch event {
        case .items:
            reloadItems()
            reloadCurrent()
        case .current:
            reloadCurrent()
        case .playbackMode:
            reloadMode()
            reloadCurrent()
        }
    }

    private func reloadItems() {
        items = backend.items
        let ids = Set(items.map(\.id))
        if !selection.isSubset(of: ids) { selection.formIntersection(ids) }
    }

    private func reloadCurrent() {
        currentIndex = backend.currentIndex
        hasNext = backend.hasNext
        hasPrevious = backend.hasPrevious
    }

    private func reloadMode() {
        repeatMode = backend.repeatMode
        order = backend.order
        mediaStoppedAction = backend.mediaStoppedAction
    }
}
