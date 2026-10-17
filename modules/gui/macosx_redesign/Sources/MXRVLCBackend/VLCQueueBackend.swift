import Foundation
import MXRBridgeAPI
import MXRCore

@MainActor
final class VLCQueueBackend: PlayQueueBackend, QueueInputOptionsBackend {
    private let transport: any VLCServiceTransport
    private let events = EventChannel<QueueEvent>()
    private var values: [String: Any]
    var startOptionsProvider: (@MainActor (MediaItem) -> MediaStartOptions?)?
    init(transport: any VLCServiceTransport) {
        self.transport = transport
        values = transport.snapshot(for: MXRBridgeService.queue)
        transport.addListener(self) { [weak self] service in self?.reload(service) }
    }
    var items: [QueueItem] { values.dictionaries("items").compactMap { item in
        guard let id = item.string("id").flatMap(UInt64.init) ?? (item["id"] as? NSNumber)?.uint64Value,
              let media = VLCWire.media(item.dictionary("media")) else { return nil }
        return QueueItem(id: id, media: media)
    } }
    var currentIndex: Int? { let index = values.integer("currentIndex", default: -1); return index >= 0 ? index : nil }
    var repeatMode: RepeatMode { switch values.integer("repeatMode") { case 1: .one; case 2: .all; default: .off } }
    var order: PlaybackOrder { values.integer("order") == 1 ? .random : .normal }
    var mediaStoppedAction: MediaStoppedAction { if values.bool("pauseAtEnd") { return .pause }; switch values.integer("mediaStoppedAction") { case 1: return .stop; case 2: return .exit; default: return .continue } }
    var hasNext: Bool { values.bool("hasNext") }
    var hasPrevious: Bool { values.bool("hasPrevious") }
    func play(at index: Int) { send(.play, ["index": index]) }
    func start() { send(.start) }
    func next() { send(.next) }
    func previous() { send(.previous) }
    func insert(_ media: [MediaItem], at index: Int?) { send(.insert, ["items": media.map { wireItem($0) }, "index": index ?? -1]) }
    func playNow(_ media: [MediaItem], startAt index: Int, inputOptions: [String], startPaused: Bool) throws {
        guard !media.isEmpty else { throw BackendOperationError.invalidInput("Select a source to open.") }
        try transport.perform(.playNow, service: .queue, arguments: ["items": media.map { wireItem($0, inputOptions: inputOptions) }, "index": min(max(0, index), media.count - 1), "startPaused": startPaused])
    }
    func move(ids: [QueueItem.ID], to index: Int) { send(.move, ["ids": ids.map(String.init), "index": index]) }
    func remove(ids: [QueueItem.ID]) { send(.remove, ["ids": ids.map(String.init)]) }
    func clear() { send(.clear) }
    func sort(_ sort: QueueSort) { send(.sort, ["key": sort.key.rawValue, "descending": !sort.ascending]) }
    func setRepeatMode(_ mode: RepeatMode) { send(.setRepeatMode, ["value": mode == .one ? 1 : mode == .all ? 2 : 0]) }
    func setOrder(_ order: PlaybackOrder) { send(.setOrder, ["value": order == .random ? 1 : 0]) }
    func setMediaStoppedAction(_ action: MediaStoppedAction) {
        send(.setPauseAtEnd, ["value": action == .pause])
        send(.setMediaStoppedAction, ["value": action == .stop ? 1 : action == .exit ? 2 : 0])
    }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (QueueEvent) -> Void) { events.add(owner, handler: handler) }
    private func wireItem(_ media: MediaItem, inputOptions: [String] = []) -> [String: Any] {
        var options = inputOptions
        if let defaults = startOptionsProvider?(media)?.trackPreferences {
            if let value = defaults.audioTrack { options.append(":audio-track=\(value - 1)") }
            if let value = defaults.subtitleTrack { options.append(":sub-track=\(value - 1)") }
            if let value = defaults.audioLanguage { options.append(":audio-language=\(value)") }
            if let value = defaults.subtitleLanguage { options.append(":sub-language=\(value)") }
        }
        return ["url": media.mrl, "title": media.title, "options": options]
    }
    /// Fire-and-forget: the playlist callbacks report the change (one coalesced "queue" event).
    private func send(_ name: MXRBridgeCommand, _ args: [String: Any] = [:]) { transport.command(name, service: .queue, arguments: args) }
    /// `queue` re-reads the items and the state; `queue.state` (index, modes, neighbours)
    /// re-reads no item (BB-02).
    private func reload(_ service: MXRBridgeService) {
        let old = values
        switch service {
        case MXRBridgeService.queue: values = transport.snapshot(for: service)
        case MXRBridgeService.queueState: values.merge(transport.snapshot(for: service)) { _, new in new }
        default: return
        }
        func changed(_ key: String) -> Bool { !NSDictionary(dictionary: ["v": old[key] ?? NSNull()]).isEqual(to: ["v": values[key] ?? NSNull()]) }
        if changed("items") { events.send(.items) }
        if ["currentIndex","hasNext","hasPrevious"].contains(where: changed) { events.send(.current) }
        if ["repeatMode","order","mediaStoppedAction","pauseAtEnd"].contains(where: changed) { events.send(.playbackMode) }
    }
}
