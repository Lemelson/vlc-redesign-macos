import Foundation
import MXRCore

/// Scripted play queue driving ``MockPlayer`` like `vlc_playlist` drives `vlc_player`.
@MainActor
public final class MockQueue: PlayQueueBackend {
    public private(set) var items: [QueueItem] = []
    public private(set) var currentIndex: Int?
    public private(set) var repeatMode: RepeatMode = .off
    public private(set) var order: PlaybackOrder = .normal
    public private(set) var mediaStoppedAction: MediaStoppedAction = .continue

    private let player: MockPlayer
    private let events = EventChannel<QueueEvent>()
    private var nextItemID: UInt64 = 1
    private var random = SeededGenerator(seed: 42)

    init(player: MockPlayer) {
        self.player = player
        player.onEndReached = { [weak self] in self?.itemEnded() }
    }

    /// Replaces the queue without starting playback (scenarios, gallery states).
    public func setItems(_ media: [MediaItem], current: Int?) {
        items = media.map(makeItem)
        currentIndex = current
        events.send(.items)
        events.send(.current)
    }

    public var hasNext: Bool {
        guard let currentIndex else { return !items.isEmpty }
        return currentIndex + 1 < items.count || repeatMode == .all || (order == .random && items.count > 1)
    }

    public var hasPrevious: Bool {
        guard let currentIndex else { return false }
        return currentIndex > 0 || repeatMode == .all
    }

    public func play(at index: Int) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
        events.send(.current)
        player.load(items[index].media)
    }

    public func start() {
        if player.currentMedia != nil {
            player.play()
        } else if let index = currentIndex ?? (items.isEmpty ? nil : 0) {
            play(at: index)
        }
    }

    public func next() {
        guard let index = nextIndex(manual: true) else { return }
        play(at: index)
    }

    public func previous() {
        guard let currentIndex else { return }
        if currentIndex > 0 {
            play(at: currentIndex - 1)
        } else if repeatMode == .all, !items.isEmpty {
            play(at: items.count - 1)
        }
    }

    public func insert(_ media: [MediaItem], at index: Int?) {
        guard !media.isEmpty else { return }
        let newItems = media.map(makeItem)
        let position = min(max(index ?? items.count, 0), items.count)
        items.insert(contentsOf: newItems, at: position)
        if let current = currentIndex, position <= current { currentIndex = current + newItems.count }
        events.send(.items)
    }

    public func move(ids: [QueueItem.ID], to index: Int) {
        let moving = items.filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return }
        let currentID = currentIndex.map { items[$0].id }
        let before = items[..<min(max(index, 0), items.count)].filter { ids.contains($0.id) }.count
        var remaining = items.filter { !ids.contains($0.id) }
        let target = min(max(index - before, 0), remaining.count)
        remaining.insert(contentsOf: moving, at: target)
        items = remaining
        currentIndex = currentID.flatMap { id in items.firstIndex { $0.id == id } }
        events.send(.items)
    }

    public func remove(ids: [QueueItem.ID]) {
        let currentID = currentIndex.map { items[$0].id }
        items.removeAll { ids.contains($0.id) }
        if let currentID, ids.contains(currentID) {
            currentIndex = nil
            player.load(nil)
        } else {
            currentIndex = currentID.flatMap { id in items.firstIndex { $0.id == id } }
        }
        events.send(.items)
    }

    public func clear() {
        items = []
        currentIndex = nil
        player.load(nil)
        events.send(.items)
    }

    public func sort(_ sort: QueueSort) {
        let currentID = currentIndex.map { items[$0].id }
        items.sort { a, b in
            let lhs = Self.key(a.media, sort.key)
            let rhs = Self.key(b.media, sort.key)
            return sort.ascending ? lhs < rhs : lhs > rhs
        }
        currentIndex = currentID.flatMap { id in items.firstIndex { $0.id == id } }
        events.send(.items)
    }

    public func setRepeatMode(_ mode: RepeatMode) {
        repeatMode = mode
        events.send(.playbackMode)
    }

    public func setOrder(_ order: PlaybackOrder) {
        self.order = order
        events.send(.playbackMode)
    }

    public func setMediaStoppedAction(_ action: MediaStoppedAction) {
        mediaStoppedAction = action
        events.send(.playbackMode)
    }

    public func addListener(_ owner: AnyObject, handler: @escaping @MainActor (QueueEvent) -> Void) {
        events.add(owner, handler: handler)
    }

    // MARK: Private

    private func makeItem(_ media: MediaItem) -> QueueItem {
        defer { nextItemID += 1 }
        return QueueItem(id: nextItemID, media: media)
    }

    private func nextIndex(manual: Bool) -> Int? {
        guard !items.isEmpty else { return nil }
        if !manual, repeatMode == .one, let currentIndex { return currentIndex }
        if order == .random {
            guard items.count > 1 else { return repeatMode == .all ? 0 : nil }
            var candidate = Int(random.next() % UInt64(items.count))
            if candidate == currentIndex { candidate = (candidate + 1) % items.count }
            return candidate
        }
        guard let currentIndex else { return 0 }
        if currentIndex + 1 < items.count { return currentIndex + 1 }
        return repeatMode == .all ? 0 : nil
    }

    private func itemEnded() {
        if let index = currentIndex, items.indices.contains(index) {
            let id = items[index].media.id
            // Count the play: E04 becomes watched etc. (the library listens through the database).
            onMediaFinished?(id)
        }
        switch mediaStoppedAction {
        case .pause:
            player.pause()
            return
        case .stop:
            player.load(nil)
            return
        case .exit:
            player.load(nil)
            return
        case .continue:
            break
        }
        if let index = nextIndex(manual: false) {
            play(at: index)
        } else {
            player.load(nil)
        }
    }

    /// Set by ``MockBackend`` to mark media watched in the library when they end.
    var onMediaFinished: (@MainActor (String) -> Void)?

    private static func key(_ media: MediaItem, _ key: QueueSortKey) -> String {
        switch key {
        case .title: media.listTitle.lowercased()
        case .duration: String(format: "%020lld", media.duration?.microseconds ?? 0)
        case .artist: (media.artist ?? "").lowercased()
        case .album: (media.album ?? "").lowercased()
        case .albumArtist: (media.albumArtist ?? "").lowercased()
        case .genre: (media.genre ?? "").lowercased()
        case .date: String(media.year ?? 0)
        case .trackNumber: String(format: "%06d", media.trackNumber ?? 0)
        case .discNumber: String(format: "%06d", media.discNumber ?? 0)
        case .url: media.mrl
        case .rating: "0"
        }
    }
}
