import MediaPlayer
import QuartzCore
import MXRCore
import MXRVLCBackend
import Observation

/// Media keys, headphones and Control Center use the system remote-command
/// center, as the stock interface's VLCRemoteControlService does.
@MainActor
final class MXRRemoteControl {
    private let model: AppModel
    private let session: VLCBridgeSession
    private var targets: [(command: MPRemoteCommand, token: Any)] = []
    private var lastUpdate: Update?
    private var clockGate = MXRNowPlayingClockGate()
    private var isRunning = false

    private struct Update: Equatable {
        let media: MediaItem?
        let seekGeneration: UInt64
        let length: Int64
        let state: PlayerState
        let rate: Double
    }
    private enum Action: Sendable, Equatable {
        case play, pause
        case command(AppCommand)
        case seek(Double)
        case skip(Double)
    }

    init(model: AppModel, session: VLCBridgeSession) {
        self.model = model
        self.session = session
    }

    func start() {
        isRunning = true
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand, action: .play)
        register(center.pauseCommand, action: .pause)
        register(center.stopCommand, action: .command(.stop))
        register(center.togglePlayPauseCommand, action: .command(.playPause))
        register(center.nextTrackCommand, action: .command(.next))
        register(center.previousTrackCommand, action: .command(.previous))
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        register(center.skipForwardCommand, action: .skip(10))
        register(center.skipBackwardCommand, action: .skip(-10))
        register(center.changePlaybackPositionCommand, action: .seek(0))
        observeState()
    }

    private func register(_ command: MPRemoteCommand, action: Action) {
        let token = command.addTarget { [weak self] event in
            // Apple's handler can arrive off main. Extract scalar payloads before
            // hopping to the actor; the non-Sendable event never crosses threads.
            let requested: Action
            if case .seek = action {
                guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
                requested = .seek(event.positionTime)
            } else if case .skip(let direction) = action, let event = event as? MPSkipIntervalCommandEvent {
                requested = .skip(direction < 0 ? -event.interval : event.interval)
            } else { requested = action }
            // MPRemoteCommandCenter calls on the main thread in practice; answer synchronously
            // there so a refused command reports .commandFailed instead of a silent success.
            guard Thread.isMainThread else {
                Task { @MainActor in _ = self?.run(requested) }
                return .success
            }
            return MainActor.assumeIsolated { self?.run(requested) ?? false } ? .success : .commandFailed
        }
        targets.append((command, token))
    }

    /// Runs a remote action as system transport: it works behind a dialog (D026) but never does
    /// something the window's own controls could not (``AppModel/canPerform(_:from:)``).
    private func run(_ action: Action) -> Bool {
        guard isRunning else { return false }
        let player = model.player
        switch action {
        case .play, .pause:
            guard model.canPerform(.playPause, from: .system) else { return false }
            let wantsPlay = action == .play
            if wantsPlay == player.isPlaying { return true }
            if wantsPlay, player.media != nil { player.play() }
            else if !wantsPlay { guard player.canPause else { return false }; player.pause() }
            else { model.perform(.playPause, from: .system) }
        case .command(let command):
            guard model.canPerform(command, from: .system) else { return false }
            model.perform(command, from: .system)
        case .seek(let seconds):
            guard player.canSeek else { return false }
            player.seek(to: .seconds(seconds))
        case .skip(let seconds):
            guard player.canSeek else { return false }
            player.jump(by: .seconds(seconds))
        }
        return true
    }

    func refresh() {
        guard isRunning else { return }
        let player = model.player
        let commands = MPRemoteCommandCenter.shared()
        let hasMedia = player.media != nil
        commands.playCommand.isEnabled = hasMedia || !model.queue.items.isEmpty
        commands.pauseCommand.isEnabled = hasMedia && player.canPause
        commands.stopCommand.isEnabled = hasMedia
        commands.togglePlayPauseCommand.isEnabled = commands.playCommand.isEnabled
        commands.nextTrackCommand.isEnabled = model.queue.hasNext
        commands.previousTrackCommand.isEnabled = model.queue.hasPrevious
        commands.skipForwardCommand.isEnabled = player.canSeek
        commands.skipBackwardCommand.isEnabled = player.canSeek
        commands.changePlaybackPositionCommand.isEnabled = player.canSeek

        let hostTime = CACurrentMediaTime()
        let time = session.interpolatedTime(at: hostTime)
        let point = session.player.timerPoint
        let effectiveRate = player.state == .playing && point.hostTime > 0 && time >= 0 ? point.rate : 0
        let update = Update(media: player.media, seekGeneration: session.player.seekGeneration,
                            length: session.player.length, state: player.state, rate: player.rate)
        let clockSample = MXRNowPlayingClockGate.Sample(mediaTime: time >= 0 ? Double(time) / 1_000_000 : nil,
                                                       hostTime: hostTime, rate: effectiveRate)
        guard clockGate.shouldPublish(clockSample, force: lastUpdate != update) else { return }
        lastUpdate = update
        let nowPlaying = MPNowPlayingInfoCenter.default()
        guard let media = player.media else {
            nowPlaying.nowPlayingInfo = nil
            nowPlaying.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: media.displayTitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(max(time, 0)) / 1_000_000,
            MPNowPlayingInfoPropertyPlaybackRate: effectiveRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: player.rate,
            MPNowPlayingInfoPropertyExternalContentIdentifier: media.mrl,
            MPNowPlayingInfoPropertyIsLiveStream: session.player.length <= 0,
            MPNowPlayingInfoPropertyMediaType: player.isAudioOnly
                ? MPNowPlayingInfoMediaType.audio.rawValue : MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let artist = media.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = media.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if session.player.length > 0 { info[MPMediaItemPropertyPlaybackDuration] = Double(session.player.length) / 1_000_000 }
        nowPlaying.nowPlayingInfo = info
        nowPlaying.playbackState = switch player.state {
        case .playing: .playing
        case .paused: .paused
        case .stopped, .stopping: .stopped
        case .started: .unknown
        }
    }

    private func observeState() {
        guard isRunning else { return }
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeState() }
        }
    }

    func stop() {
        isRunning = false
        for target in targets { target.command.removeTarget(target.token) }
        targets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        lastUpdate = nil
        clockGate = MXRNowPlayingClockGate()
    }
}
