import XCTest
@testable import MXRCore
@testable import MXRMockBackend

/// Live run 2 (G-panels blocker): a fast Brightness drag on the Essential card sent one
/// `setVideoEffects` per pointer event, toggled VLC's `adjust` filter every time the value passed
/// neutral and crashed the vout. Slider drags now reach the engine coalesced, with `adjust` kept in
/// the chain until the drag settles.
@MainActor
final class VideoEffectsDragCoalescingTests: XCTestCase {
    private func writes(of app: AppModel) -> () -> [VideoEffects] {
        var log: [VideoEffects] = []
        let backend = app.videoEffects.backend
        backend.addListener(self) { event in if event == .videoEffects { log.append(backend.videoEffects) } }
        return { log }
    }

    func testFastDragIsCoalescedAndKeepsAdjustInTheChain() async throws {
        let app = AppModel.mock(.playingEpisode)
        let log = writes(of: app)
        let start = ContinuousClock.now
        // Out and back through neutral ten times at pointer-event rate (about 2 ms apart).
        var changes = 0
        for sweep in 0..<10 {
            for step in 0...40 {
                let brightness = 1 + (sweep.isMultiple(of: 2) ? 1 : -1) * Double(step < 20 ? step : 40 - step) / 40
                app.videoEffects.updateEssential { $0.brightness = brightness }
                changes += 1
                XCTAssertEqual(app.videoEffects.effects.essential.brightness, brightness, "the thumb follows at once")
                try await Task.sleep(for: .milliseconds(2))
            }
        }
        let elapsed = ContinuousClock.now - start
        let intervals = Int((elapsed / VideoEffectsModel.writeInterval).rounded(.up))
        XCTAssertGreaterThan(log().count, 1, "the picture follows the drag")
        XCTAssertLessThanOrEqual(log().count, intervals + 1, "\(changes) changes become at most one write per interval")
        XCTAssertTrue(log().allSatisfy(\.essential.isEnabled), "adjust is never removed while the drag lasts")

        // The drag ended at neutral: once it settles, adjust leaves the chain.
        try await Task.sleep(for: VideoEffectsModel.settleInterval + .milliseconds(200))
        XCTAssertEqual(app.videoEffects.backend.videoEffects.essential.brightness, 1)
        XCTAssertFalse(app.videoEffects.backend.videoEffects.essential.isEnabled)
        XCTAssertFalse(app.videoEffects.effects.essential.isEnabled)
        XCTAssertEqual(log().filter { !$0.essential.isEnabled }.count, 1, "adjust is removed exactly once, at the end")
    }

    func testDragEndingAwayFromNeutralKeepsTheValue() async throws {
        let app = AppModel.mock(.playingEpisode)
        for value in stride(from: 1.0, through: 1.5, by: 0.01) { app.videoEffects.updateEssential { $0.brightness = value } }
        try await Task.sleep(for: VideoEffectsModel.settleInterval + .milliseconds(200))
        XCTAssertEqual(app.videoEffects.backend.videoEffects.essential.brightness, 1.5, accuracy: 0.0001)
        XCTAssertTrue(app.videoEffects.backend.videoEffects.essential.isEnabled)
    }

    func testAToggleDuringADragAppliesBothAtOnce() {
        let app = AppModel.mock(.playingEpisode)
        app.videoEffects.updateEssential { $0.contrast = 1.4 }
        app.videoEffects.update { $0.flip = .horizontal }
        XCTAssertEqual(app.videoEffects.backend.videoEffects.flip, .horizontal)
        XCTAssertEqual(app.videoEffects.backend.videoEffects.essential.contrast, 1.4, accuracy: 0.0001, "the drag's value is not lost")
    }
}
