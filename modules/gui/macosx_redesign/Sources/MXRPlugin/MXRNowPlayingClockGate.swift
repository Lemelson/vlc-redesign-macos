/// MediaPlayer extrapolates its elapsed-time anchor until the next publication.
/// Preserve that anchor during linear playback, but correct freezes and rebases.
struct MXRNowPlayingClockGate {
    struct Sample {
        let mediaTime: Double?
        let hostTime: Double
        /// Effective native clock rate: zero while the clock is frozen/invalid.
        let rate: Double
    }

    // Two native timer intervals (250 ms each): ignore small anchor jitter while
    // correcting accumulated errors larger than half a displayed second.
    private static let correctionThreshold = 0.5
    private var published: Sample?

    mutating func shouldPublish(_ sample: Sample, force: Bool = false) -> Bool {
        var changed = force
        if let previous = published {
            changed = changed || previous.rate != sample.rate
                || (previous.mediaTime == nil) != (sample.mediaTime == nil)
            if let currentTime = sample.mediaTime, let previousTime = previous.mediaTime {
                let expected = previousTime + max(0, sample.hostTime - previous.hostTime) * previous.rate
                changed = changed || abs(currentTime - expected) > Self.correctionThreshold
            }
        } else {
            changed = true
        }
        guard changed else { return false }
        published = sample
        return true
    }
}
