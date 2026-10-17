/// macOS/VLC pinch convention: accumulate deltas until the standard 0.3 threshold;
/// an outward gesture enters fullscreen, an inward gesture leaves it.
struct MXRFullscreenMagnification {
    private var accumulated = 0.0
    private var hasRequested = false

    mutating func begin() {
        accumulated = 0
        hasRequested = false
    }

    mutating func consume(_ delta: Double) -> Bool? {
        guard !hasRequested else { return nil }
        accumulated += delta
        guard abs(accumulated) > 0.3 else { return nil }
        hasRequested = true
        return accumulated > 0
    }
}
