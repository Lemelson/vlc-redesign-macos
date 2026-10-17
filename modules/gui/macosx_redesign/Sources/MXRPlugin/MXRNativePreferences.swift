import Foundation

/// Pure native preference policy. Names and defaults match the registered app
/// options; an invalid stored value follows the same default as a fresh launch.
struct MXRNativePreferences {
    enum Value { case bool(Bool), number(Double), text(String) }
    enum Autoresize: String { case never, first, always }
    enum RaiseOnPlay: String {
        case never, video, always
        func shouldRaise(hasVideo: Bool) -> Bool { self == .always || (self == .video && hasVideo) }
    }
    enum TrackNotification: String {
        case never, minimized, always
        func shouldShow(isMinimized: Bool) -> Bool { self == .always || (self == .minimized && isMinimized) }
    }
    enum SingleClick: String { case playPause = "play-pause", controls, none }
    enum ScrollMode: Int { case none = -1, volume = 0, seek = 2 }

    let autoresize: Autoresize
    let remembersWindow: Bool
    let startsMinimized: Bool
    let pausesMinimizedVideo: Bool
    let raiseOnPlay: RaiseOnPlay
    let windowAlpha: Double
    let showsMenubarIcon: Bool
    let trackNotification: TrackNotification
    let notificationDuration: Double
    let singleClick: SingleClick
    let doubleClickFullscreen: Bool
    let reverseScroll: Bool
    let verticalScroll: ScrollMode
    let horizontalScroll: ScrollMode

    init(value: (String) -> Value?) {
        func text(_ name: String) -> String? { if case .text(let v) = value(name) { v } else { nil } }
        func bool(_ name: String, _ fallback: Bool) -> Bool { if case .bool(let v) = value(name) { v } else { fallback } }
        func number(_ name: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            guard case .number(let v) = value(name), v.isFinite else { return fallback }
            return min(max(v, range.lowerBound), range.upperBound)
        }
        func scroll(_ name: String, _ fallback: ScrollMode) -> ScrollMode {
            guard case .number(let v) = value(name), v == -1 || v == 0 || v == 2 else { return fallback }
            return ScrollMode(rawValue: Int(v)) ?? fallback
        }
        autoresize = Autoresize(rawValue: text("autoresize") ?? "") ?? .never
        remembersWindow = bool("remember-window", true)
        startsMinimized = bool("start-minimized", false)
        pausesMinimizedVideo = bool("pause-minimized", false)
        raiseOnPlay = RaiseOnPlay(rawValue: text("raise-on-play") ?? "") ?? .video
        windowAlpha = number("window-opacity", 100, 10...100) / 100
        showsMenubarIcon = bool("menubar-icon", true)
        trackNotification = TrackNotification(rawValue: text("track-notification") ?? "") ?? .minimized
        notificationDuration = number("notification-duration", 5, 0...10)
        singleClick = SingleClick(rawValue: text("click-action") ?? "") ?? .playPause
        doubleClickFullscreen = text("double-click-action") != "none"
        reverseScroll = bool("reverse-scroll", false)
        verticalScroll = scroll("hotkeys-y-wheel-mode", .volume)
        horizontalScroll = scroll("hotkeys-x-wheel-mode", .seek)
    }
}

struct MXRAutoresizePolicy {
    private var hasResized = false
    mutating func consume(mode: MXRNativePreferences.Autoresize, isFullscreen: Bool,
                          hasPlayerLayout: Bool, validSize: Bool) -> Bool {
        guard mode != .never, !isFullscreen, hasPlayerLayout, validSize,
              mode == .always || !hasResized else { return false }
        hasResized = true
        return true
    }
}

/// Accumulates trackpad fractions without an idle timer. Horizontal rightward
/// motion seeks forward; natural scrolling and the explicit reverse option each
/// invert the physical gesture once, matching the stock macOS host behavior.
struct MXRVideoScrollAccumulator {
    struct Action: Equatable { let mode: MXRNativePreferences.ScrollMode; let steps: Int }
    private var horizontal = false
    private var remainder = 0.0
    private var lastTimestamp: TimeInterval?

    mutating func consume(x: Double, y: Double, timestamp: TimeInterval, natural: Bool,
                          preferences: MXRNativePreferences) -> Action? {
        guard x.isFinite, y.isFinite, timestamp.isFinite, x != 0 || y != 0 else { return nil }
        let nextHorizontal = abs(x) > abs(y)
        if nextHorizontal != horizontal || lastTimestamp.map({ timestamp - $0 > 0.4 }) == true { remainder = 0 }
        horizontal = nextHorizontal
        lastTimestamp = timestamp
        let mode = horizontal ? preferences.horizontalScroll : preferences.verticalScroll
        guard mode != .none else { remainder = 0; return nil }
        let direction = (natural ? -1.0 : 1.0) * (preferences.reverseScroll ? -1.0 : 1.0)
        remainder += min(max((horizontal ? -x : y) * direction, -20), 20)
        let steps = Int(remainder.rounded(.towardZero))
        guard steps != 0 else { return nil }
        remainder -= Double(steps)
        return Action(mode: mode, steps: steps)
    }
}
