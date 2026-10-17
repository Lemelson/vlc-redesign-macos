import Foundation

@main
struct NowPlayingClockTests {
    static func main() {
        var gate = MXRNowPlayingClockGate()
        func sample(_ mediaTime: Double?, _ hostTime: Double, rate: Double = 1) -> MXRNowPlayingClockGate.Sample {
            .init(mediaTime: mediaTime, hostTime: hostTime, rate: rate)
        }
        precondition(gate.shouldPublish(sample(10, 100)))
        for tick in 1...400 {
            let delta = Double(tick) / 4
            precondition(!gate.shouldPublish(sample(10 + delta, 100 + delta)), "Linear 4 Hz timer points must not rewrite Now Playing")
        }
        precondition(gate.shouldPublish(sample(110, 200, rate: 0)), "A rebuffer clock freeze must stop system extrapolation")
        precondition(!gate.shouldPublish(sample(110, 210, rate: 0)), "A frozen clock remains deduplicated")
        precondition(gate.shouldPublish(sample(110, 210)), "Resume must publish a new running anchor")
        precondition(!gate.shouldPublish(sample(110.25, 210.25)))
        precondition(!gate.shouldPublish(sample(110.6, 210.5)), "Small timer correction does not cause repeated writes")
        precondition(gate.shouldPublish(sample(150, 211)), "A clock discontinuity needs correction without a seek generation")
        precondition(gate.shouldPublish(sample(nil, 212, rate: 0)), "Invalidation must freeze the published clock")
        precondition(!gate.shouldPublish(sample(nil, 220, rate: 0)))
        precondition(gate.shouldPublish(sample(151, 220)), "A valid resumed clock needs a fresh anchor")
        precondition(gate.shouldPublish(sample(151, 220), force: true), "Metadata or explicit seeks still force a publication")
        print("PASS: Now Playing linear dedup, rebuffer freeze/resume, drift, validity, forced updates")
    }
}
