// VLCBridgeSession.swift: the Swift side of the Objective-C bridge (ARCHITECTURE.md §2).
//
// Phase 0 (task A2): receives the player events on the main actor and fans them out to
// observers, and offers the clock interpolation the UI needs. The MXRCore protocol
// implementations (PlayerBackend, PlaybackClockSource, ...) are built on top of this.

import AppKit
import MXRBridgeAPI
import QuartzCore

/// Owns the connection to one running VLC interface.
@MainActor
public final class VLCBridgeSession: NSObject, MXRPlayerEventSink {
    /// What changed in the player. Payload-free: re-read `player` after an event.
    public enum PlayerChange: Sendable, Hashable {
        case state
        case media
        case length
        case time
        case clockPaused
        case fullscreen
    }

    public let bridge: MXRInterfaceBridge
    public var player: MXRPlayerBridge { bridge.player }

    private var observers: [(token: Int, handler: @MainActor (PlayerChange) -> Void)] = []
    private var nextToken = 0
    private var isInvalidated = false

    public init(bridge: MXRInterfaceBridge) {
        self.bridge = bridge
        super.init()
        bridge.player.sink = self
    }

    /// Stops forwarding events and releases the observers. Called from MXRSwiftStop.
    public func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        if bridge.player.sink === self {
            bridge.player.sink = nil
        }
        observers.removeAll()
    }

    // MARK: Observers

    /// Registers a handler for player changes; returns a token for `removeObserver`.
    @discardableResult
    public func observePlayer(_ handler: @escaping @MainActor (PlayerChange) -> Void) -> Int {
        nextToken += 1
        observers.append((nextToken, handler))
        return nextToken
    }

    public func removeObserver(_ token: Int) {
        observers.removeAll { $0.token == token }
    }

    private func emit(_ change: PlayerChange) {
        guard !isInvalidated else { return }
        for observer in observers {
            observer.handler(change)
        }
    }

    // MARK: Clock

    /// The media time in microseconds at `hostTime` (CACurrentMediaTime base), interpolated
    /// from the last timer point like `vlc_player_timer_point_Interpolate`; -1 when unknown.
    public func interpolatedTime(at hostTime: CFTimeInterval = CACurrentMediaTime()) -> Int64 {
        let point = player.timerPoint
        guard point.time >= 0 else { return -1 }
        guard point.hostTime > 0, player.state == .playing else { return point.time }
        var time = point.time + Int64((hostTime - point.hostTime) * point.rate * 1_000_000)
        time = max(time, 0)
        if point.length > 0 { time = min(time, point.length) }
        return time
    }

    // MARK: Logging

    /// Writes to VLC's log (visible with `-vv`).
    public func log(_ message: String, level: MXRLogLevel = .info) {
        bridge.log(message, level: level)
    }

    // MARK: MXRPlayerEventSink

    public func playerStateDidChange() { emit(.state) }
    public func playerCurrentMediaDidChange() { emit(.media) }
    public func playerLengthDidChange() { emit(.length) }
    public func playerTimeDidChange() { emit(.time) }
    public func playerClockDidPause() { emit(.clockPaused) }
    public func playerFullscreenDidChange() { emit(.fullscreen) }
}
