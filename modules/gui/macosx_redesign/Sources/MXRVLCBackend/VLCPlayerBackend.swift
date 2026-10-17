import Foundation
import MXRBridgeAPI
import MXRCore

/// The player as published by the bridge in topics (MXRBridgeKeys.h). An engine callback
/// re-reads only its topic; commands are fire-and-forget and never re-read state themselves
/// (review findings ARC-02, BB-02). A failed command is a transient OSD message, never the
/// playback-error card: `errorMessage` comes only from the engine's input error (ARC-11).
@MainActor
final class VLCPlayerBackend: PlayerBackend {
    private typealias K = MXRPlayerKey
    private let transport: any VLCServiceTransport
    private let events = EventChannel<PlayerEvent>()
    private var values: [String: Any] = [:]
    /// Decoded once per effects topic update, not on every property read.
    private var decodedVideoEffects = VideoEffects.default
    /// The last ``setVideoEffects(_:)`` request (see there).
    private var lastRequestedVideoEffects: VideoEffects?
    private var decodedAudioEffects = AudioEffects.default
    private var decodedSubtitleStyle = SubtitleStyle.default
    private var decodedTrackDefaults = TrackDefaults()

    /// The keys each topic publishes; a key missing from a topic snapshot is cleared.
    private static let topicKeys: [MXRBridgeService: [MXRPlayerKey]] = [
        MXRBridgeService.playerState: [.state, .rate, .bufferingProgress, .canPause, .canSeek, .canChangeRate, .canRecord,
                                                .errorMessage, .isRecording, .abLoop, .restorePrompt, .isFullscreen, .isPictureInPicture],
        MXRBridgeService.playerMedia: [.media],
        MXRBridgeService.playerTracks: [.audioTracks, .videoTracks, .subtitleTracks],
        MXRBridgeService.playerTitles: [.titles, .chapters, .selectedTitleIndex, .selectedChapterIndex, .programs],
        MXRBridgeService.playerSync: [.audioDelay, .subtitleDelay, .subtitleFPS, .subtitleTextScale],
        MXRBridgeService.playerEffects: [.videoEffects, .audioEffects, .subtitleStyle, .trackDefaults, .audioVisualization, .subtitleDurationFactor],
        MXRBridgeService.playerVolume: [.volume, .isMuted],
        MXRBridgeService.playerDevices: [.audioDevices, .currentAudioDeviceID],
        MXRBridgeService.playerStatistics: [.statistics],
        MXRBridgeService.playerTeletext: [.teletext],
        MXRBridgeService.playerSnapshot: [.snapshotURL],
    ]
    private static let events: [(PlayerEvent, [MXRPlayerKey])] = [
        (.state, [.state]), (.capabilities, [.canSeek, .canPause, .canChangeRate, .canRecord]), (.rate, [.rate]),
        (.volume, [.volume, .isMuted]), (.buffering, [.bufferingProgress]), (.error, [.errorMessage]),
        (.tracks(.video), [.videoTracks]), (.tracks(.audio), [.audioTracks]), (.tracks(.subtitle), [.subtitleTracks]),
        (.audioDevices, [.audioDevices, .currentAudioDeviceID]),
        (.synchronization, [.audioDelay, .subtitleDelay, .subtitleFPS, .subtitleDurationFactor, .subtitleTextScale]),
        (.subtitleStyle, [.subtitleStyle]), (.trackDefaults, [.trackDefaults]),
        (.titles, [.titles, .chapters, .selectedTitleIndex, .selectedChapterIndex]), (.programs, [.programs]), (.abLoop, [.abLoop]),
        (.recording, [.isRecording]), (.fullscreen, [.isFullscreen]), (.videoEffects, [.videoEffects]), (.audioEffects, [.audioEffects]),
        (.audioVisualization, [.audioVisualization]), (.restorePrompt, [.restorePrompt]), (.statistics, [.statistics]),
        (.teletext, [.teletext]), (.pictureInPicture, [.isPictureInPicture]),
    ]

    init(transport: any VLCServiceTransport) {
        self.transport = transport
        apply(transport.snapshot(for: MXRBridgeService.player), replacing: nil, notify: false)
        transport.addListener(self) { [weak self] service in self?.reload(service) }
    }
    var state: PlayerState { switch values.integer(K.state) { case 1: .started; case 2: .playing; case 3: .paused; case 4: .stopping; default: .stopped } }
    var currentMedia: MediaItem? { VLCWire.media(values.dictionary(K.media)) }
    var capabilities: PlaybackCapabilities {
        var result: PlaybackCapabilities = []
        if values.bool(K.canSeek) { result.insert(.seek) }
        if values.bool(K.canPause) { result.insert(.pause) }
        if values.bool(K.canChangeRate) { result.insert(.changeRate) }
        if values.bool(K.canRecord) { result.insert(.record) }
        return result
    }
    var rate: Double { values.double(K.rate, default: 1) }
    var volume: Double { values.double(K.volume, default: 1) }
    var isMuted: Bool { values.bool(K.isMuted) }
    var bufferingProgress: Double { values.double(K.bufferingProgress, default: 1) }
    var errorMessage: String? { values.string(K.errorMessage) }
    func tracks(of kind: TrackKind) -> [Track] {
        let key: MXRPlayerKey = switch kind { case .audio: .audioTracks; case .video: .videoTracks; case .subtitle: .subtitleTracks }
        return values.dictionaries(key).compactMap { item -> Track? in
            guard let id = item.string(K.ID) else { return nil }
            let width = item.double(K.width), height = item.double(K.height)
            return Track(id: id, kind: kind, name: item.string(K.name) ?? id, language: item.string(K.language), codec: item.string(K.codec),
                isSelected: item.bool(K.selected), isExternal: item.bool(K.external), sourceURL: item.url(K.URL),
                videoSize: width > 0 && height > 0 ? CGSize(width: width, height: height) : nil)
        }
    }
    var audioDevices: [AudioDevice] { values.dictionaries(K.audioDevices).compactMap { item in item.string(K.ID).map { AudioDevice(id: $0, name: item.string(K.name) ?? $0) } } }
    var currentAudioDeviceID: String? { values.string(K.currentAudioDeviceID) }
    var audioDelay: MediaTime { MediaTime(microseconds: values.int64(K.audioDelay)) }
    var subtitleDelay: MediaTime { MediaTime(microseconds: values.int64(K.subtitleDelay)) }
    var subtitleFPS: Double { values.double(K.subtitleFPS) }
    var subtitleDurationFactor: Double { values.double(K.subtitleDurationFactor, default: 1) }
    var subtitleTextScale: Int { values.integer(K.subtitleTextScale, default: 100) }
    var subtitleStyle: SubtitleStyle { decodedSubtitleStyle }
    var trackDefaults: TrackDefaults { decodedTrackDefaults }
    var titles: [MediaTitle] { values.dictionaries(K.titles).map { item in MediaTitle(index: item.integer(K.index), name: item.string(K.name) ?? "Title", length: MediaTime(microseconds: item.int64(K.length)), isMenu: item.bool(K.isMenu), chapters: parseChapters(item.dictionaries(K.chapters))) } }
    var selectedTitleIndex: Int? { values.integer(K.selectedTitleIndex, default: -1) >= 0 ? values.integer(K.selectedTitleIndex) : nil }
    var chapters: [Chapter] { parseChapters(values.dictionaries(K.chapters)) }
    var selectedChapterIndex: Int? { values.integer(K.selectedChapterIndex, default: -1) >= 0 ? values.integer(K.selectedChapterIndex) : nil }
    var programs: [MediaProgram] { values.dictionaries(K.programs).map { MediaProgram(id: $0.integer(K.ID), name: $0.string(K.name) ?? "Program", isSelected: $0.bool(K.selected), isScrambled: $0.bool(K.scrambled)) } }
    var abLoop: ABLoop {
        let loop = values.dictionary(K.abLoop)
        switch loop.integer("state") { case 1: return .pointA(MediaTime(microseconds: loop.int64("a"))); case 2: return .looping(a: MediaTime(microseconds: loop.int64("a")), b: MediaTime(microseconds: loop.int64("b"))); default: return .off }
    }
    var isRecording: Bool { values.bool(K.isRecording) }
    var isFullscreen: Bool { values.bool(K.isFullscreen) }
    var videoEffects: VideoEffects { decodedVideoEffects }
    var audioEffects: AudioEffects { decodedAudioEffects }
    var audioVisualization: AudioVisualization { AudioVisualization(rawValue: values.string(K.audioVisualization) ?? "disabled") ?? .disabled }
    var restorePrompt: RestorePrompt? {
        // The bridge publishes time -1 until the media library answers: no prompt until a real time is known (BB-10; the video prompts at 00:00:02, 14m09.8).
        guard let media = currentMedia, let time = values.dictionary(K.restorePrompt)["time"] as? NSNumber, time.int64Value >= 1_000_000 else { return nil }
        return RestorePrompt(mediaID: media.id, time: MediaTime(microseconds: time.int64Value))
    }
    var statistics: MediaStatistics? {
        let x = values.dictionary(K.statistics)
        guard !x.isEmpty else { return nil }
        return MediaStatistics(inputBitrate: x.double("inputBitrate"), demuxBitrate: x.double("demuxBitrate"), decodedVideoBlocks: x.integer("decodedVideoBlocks"), displayedPictures: x.integer("displayedPictures"), lostPictures: x.integer("lostPictures"), decodedAudioBlocks: x.integer("decodedAudioBlocks"), playedAudioBuffers: x.integer("playedAudioBuffers"), lostAudioBuffers: x.integer("lostAudioBuffers"))
    }
    var teletext: TeletextState { let x = values.dictionary(K.teletext); return TeletextState(isAvailable: x.bool("available"), isEnabled: x.bool("enabled"), page: x.integer("page"), isTransparent: x.bool("transparent")) }
    var isPictureInPicture: Bool { values.bool(K.isPictureInPicture) }
    func play() { send(.play) }
    func pause() { send(.pause) }
    func togglePause() { send(.togglePause) }
    func stop() { send(.stop) }
    func seek(to time: MediaTime, precision: SeekPrecision) { send(.seek, ["time": time.microseconds, "precise": precision == .precise]) }
    func seek(toPosition position: Double, precision: SeekPrecision) { send(.seekPosition, ["position": position, "precise": precision == .precise]) }
    func jump(by offset: MediaTime) { send(.jump, ["value": offset.microseconds]) }
    func nextFrame() { send(.nextFrame) }
    func setRate(_ rate: Double) { send(.setRate, ["value": rate]) }
    func setVolume(_ volume: Double) { send(.setVolume, ["value": volume]) }
    func setMuted(_ muted: Bool) { send(.setMuted, ["value": muted]) }
    func selectTrack(id: String, exclusive: Bool) { send(.selectTrack, ["id": id, "exclusive": exclusive]) }
    func unselectTrack(id: String) { send(.unselectTrack, ["id": id]) }
    func unselectTracks(of kind: TrackKind) { send(.unselectTracks, ["kind": kind.rawValue]) }
    func addExternalTrack(url: URL, kind: TrackKind, select: Bool) { send(.addExternalTrack, ["url": url.absoluteString, "kind": kind.rawValue, "select": select]) }
    func selectAudioDevice(id: String) { send(.selectAudioDevice, ["id": id]) }
    func refreshAudioDevices() { send(.refreshAudioDevices) }
    func setAudioDelay(_ delay: MediaTime) { send(.setAudioDelay, ["value": delay.microseconds]) }
    func setSubtitleDelay(_ delay: MediaTime) { send(.setSubtitleDelay, ["value": delay.microseconds]) }
    func setSubtitleFPS(_ fps: Double) { send(.setSubtitleFPS, ["value": fps]) }
    func setSubtitleDurationFactor(_ factor: Double) { send(.setSubtitleDurationFactor, ["value": factor]) }
    func setSubtitleTextScale(_ percent: Int) { send(.setSubtitleTextScale, ["value": percent]) }
    func setSubtitleStyle(_ style: SubtitleStyle) { send(.setSubtitleStyle, VLCWire.dictionary(style)) }
    func setTrackDefaults(_ defaults: TrackDefaults) { send(.setTrackDefaults, VLCWire.dictionary(defaults)) }
    func setSubtitleSafeInset(points: Double, backingScale: Double) {
        send(.setSubtitleSafeInset, ["points": max(0, points), "scale": backingScale > 0 ? backingScale : 1.0])
    }
    func subtitleCues(trackID: String) async -> [SubtitleCue] {
        do {
            let result = try await transport.request(.subtitleCues, service: MXRBridgeService.player, arguments: ["id": trackID])
            return result.dictionaries("cues").map { SubtitleCue(start: MediaTime(microseconds: $0.int64("start")), end: MediaTime(microseconds: $0.int64("end")), text: $0.string("text") ?? "") }
        } catch { transport.log(error); return [] }
    }
    func selectTitle(index: Int) { send(.selectTitle, ["index": index]) }
    func selectChapter(index: Int) { send(.selectChapter, ["index": index]) }
    func selectProgram(id: Int) { send(.selectProgram, ["id": id]) }
    func toggleABLoop() { send(.toggleABLoop) }
    func setRecording(_ enabled: Bool) { send(.setRecording, ["value": enabled]) }
    func takeSnapshot() { send(.takeSnapshot) }
    func setFullscreen(_ fullscreen: Bool) { send(.setFullscreen, ["value": fullscreen]) }
    /// The preferred stream resolution is a saved preference (`preferred-resolution`, read by the
    /// adaptive demuxer at the next input), not a filter: it goes through the settings path and
    /// never rewrites the filter chain or restarts the vout (C-10).
    /// A side is skipped only when the request equals both the snapshot and the previous
    /// request: the snapshot lags behind requests in flight (a value changed and changed back
    /// before the coalesced topic arrives), and the previous request misses changes made
    /// elsewhere (a crop hotkey). Equal to both, the engine already has or is getting it.
    func setVideoEffects(_ effects: VideoEffects) {
        let baselines = [decodedVideoEffects, lastRequestedVideoEffects ?? decodedVideoEffects]
        lastRequestedVideoEffects = effects
        if baselines.contains(where: { $0.resolution != effects.resolution }) {
            let height = effects.resolution.flatMap { Int($0.dropLast()) } ?? -1
            transport.command(.set, service: .settings, arguments: ["name": "preferred-resolution", "value": height])
            transport.command(.save, service: .settings)
        }
        if baselines.contains(where: { var filters = effects; filters.resolution = $0.resolution; return filters != $0 }) {
            var wire = VLCWire.dictionary(effects); wire.removeValue(forKey: "resolution")
            send(.setVideoEffects, wire)
        }
    }
    func setAudioEffects(_ effects: AudioEffects) { send(.setAudioEffects, VLCWire.dictionary(effects)) }
    func testStereoOutput() async throws {
        var arguments: [String: Any] = ["mode": audioEffects.stereoMode.rawValue]
        if let deviceID = currentAudioDeviceID { arguments["deviceID"] = deviceID }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            _ = try await transport.request(.start, service: .audioTest, arguments: arguments)
            try Task.checkCancellation()
        } onCancel: {
            Task { @MainActor [self] in
                do { _ = try await self.transport.request(.cancel, service: .audioTest, arguments: [:]) }
                catch { self.transport.log(error) }
            }
        }
    }
    func setAudioVisualization(_ visualization: AudioVisualization) { send(.setAudioVisualization, ["value": visualization.rawValue]) }
    func answerRestorePrompt(resume: Bool) { send(.answerRestorePrompt, ["resume": resume]) }
    func setTeletextEnabled(_ enabled: Bool) { send(.setTeletextEnabled, ["value": enabled]) }
    func selectTeletextPage(_ page: Int) { send(.selectTeletextPage, ["value": page]) }
    func setTeletextTransparent(_ transparent: Bool) { send(.setTeletextTransparent, ["value": transparent]) }
    func setPictureInPicture(_ active: Bool) { send(.setPictureInPicture, ["value": active]) }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (PlayerEvent) -> Void) { events.add(owner, handler: handler) }
    private func parseChapters(_ list: [[String: Any]]) -> [Chapter] { list.map { Chapter(index: $0.integer(K.index), name: $0.string(K.name) ?? "Chapter", time: MediaTime(microseconds: $0.int64(K.time))) } }

    /// Fire-and-forget: the engine reports the result through a topic.
    private func send(_ command: MXRBridgeCommand, _ arguments: [String: Any] = [:]) {
        do { try transport.perform(command, service: MXRBridgeService.player, arguments: arguments) }
        catch { transport.notify(error.localizedDescription) }
    }
    private func reload(_ service: MXRBridgeService) {
        if service == MXRBridgeService.player {
            apply(transport.snapshot(for: service), replacing: nil, notify: true)
        } else if let keys = Self.topicKeys[service] {
            apply(transport.snapshot(for: service), replacing: keys.map(\.rawValue), notify: true)
        }
    }
    /// Merges a topic (`replacing` its keys) or a full snapshot (`nil`) and sends the events
    /// of the keys that changed.
    private func apply(_ snapshot: [String: Any], replacing keys: [String]?, notify: Bool) {
        let old = values
        let touched: Set<String>
        if let keys {
            for key in keys { values[key] = snapshot[key] }
            touched = Set(keys)
        } else {
            values = snapshot
            touched = Set(old.keys).union(snapshot.keys)
        }
        let changed = Set(touched.filter { !NSDictionary(dictionary: ["v": old[$0] ?? NSNull()]).isEqual(to: ["v": values[$0] ?? NSNull()]) })
        if changed.isEmpty && notify { return }
        decodeEffects(changed: notify ? changed : touched)
        guard notify else { return }
        if changed.contains(K.media.rawValue) {
            if VLCWire.media(old.dictionary(K.media))?.id != currentMedia?.id { events.send(.media) } else { events.send(.metadata) }
        }
        for (event, eventKeys) in Self.events where eventKeys.contains(where: { changed.contains($0.rawValue) }) { events.send(event) }
        if changed.contains(K.snapshotURL.rawValue), let url = values.url(K.snapshotURL) { events.send(.snapshotTaken(url)) }
    }
    private func decodeEffects(changed: Set<String>) {
        if changed.contains(K.videoEffects.rawValue) { decodedVideoEffects = VLCWire.decode(VideoEffects.self, from: values.dictionary(K.videoEffects)) ?? .default }
        if changed.contains(K.audioEffects.rawValue) { decodedAudioEffects = VLCWire.decode(AudioEffects.self, from: values.dictionary(K.audioEffects)) ?? .default }
        if changed.contains(K.subtitleStyle.rawValue) { decodedSubtitleStyle = VLCWire.decode(SubtitleStyle.self, from: values.dictionary(K.subtitleStyle)) ?? .default }
        if changed.contains(K.trackDefaults.rawValue) { decodedTrackDefaults = VLCWire.decode(TrackDefaults.self, from: values.dictionary(K.trackDefaults)) ?? TrackDefaults() }
    }
}
