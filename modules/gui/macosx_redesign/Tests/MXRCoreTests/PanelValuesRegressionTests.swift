import Foundation
@testable import MXRCore
import MXRMockBackend
import XCTest

/// G-panels: subtitle style, video effects and panel list keys.
final class PanelValuesRegressionTests: XCTestCase {
    /// G-11: a legacy payload whose stored flag disagrees with its opacity decodes consistently,
    /// and encoding still writes the flag the bridge reads.
    func testLegacyBackgroundFlagFollowsOpacity() throws {
        var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SubtitleStyle.default)) as! [String: Any]
        payload["background"] = false
        payload["backgroundOpacity"] = 0.5
        let style = try JSONDecoder().decode(SubtitleStyle.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(style.backgroundOpacity, 0.5)
        XCTAssertTrue(style.background)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(style)) as! [String: Any]
        XCTAssertEqual(encoded["background"] as? Bool, true)
        var cleared = style
        cleared.setBackgroundOpacity(0)
        XCTAssertFalse(cleared.background)
    }

    /// G-06: the Pixels-mode outline field maps a typed thickness to the nearest VLC preset.
    func testOutlinePixelsMapToNearestPreset() {
        XCTAssertEqual(SubtitleOutline.nearest(pixels: 0), SubtitleOutline.none)
        XCTAssertEqual(SubtitleOutline.nearest(pixels: 2), .thin)
        XCTAssertEqual(SubtitleOutline.nearest(pixels: 5), .normal)
        XCTAssertEqual(SubtitleOutline.nearest(pixels: 40), .thick)
        XCTAssertEqual(SubtitleRelativeSize.automatic.title, "Auto")
    }

    /// G-15: a legacy preset with values the engine rejects still applies its other video effects.
    @MainActor
    func testLegacyVideoPresetKeepsSupportedEffects() throws {
        let app = AppModel.mock(.pausedEpisode)
        var legacy = VideoEffects(flip: .horizontal, rotation: 90, zoom: .half, hdr: .hdr10, resolution: "2160p", crop: "16:9")
        legacy.essential.isEnabled = true
        let preset = PlaybackPreset(name: "Legacy", videoEffects: legacy)
        app.presets.apply(preset, tracks: app.tracks, audio: app.audioEffects, video: app.videoEffects)
        let applied = app.videoEffects.backend.videoEffects
        XCTAssertEqual(applied.flip, .horizontal)
        XCTAssertEqual(applied.rotation, 90)
        XCTAssertEqual(applied.zoom, .half)
        XCTAssertEqual(applied.crop, "16:9")
        XCTAssertTrue(applied.essential.isEnabled)
        XCTAssertNil(applied.resolution)
        XCTAssertEqual(applied.hdr, .auto)
        XCTAssertEqual(VideoEffects(resolution: "720p").sanitized.resolution, "720p")
    }

    /// G-03: list keys that a focused queue or bookmark row keeps; Space stays play/pause.
    func testFocusedListKeys() {
        for key in ["Enter", "Up", "Down", "Left", "Right", "Backspace", "Delete"] {
            XCTAssertTrue(FocusedListKeys.contains(KeyBinding(key: key)), key)
        }
        XCTAssertTrue(FocusedListKeys.contains(KeyBinding(key: "Up", modifiers: .option)))
        XCTAssertTrue(FocusedListKeys.contains(KeyBinding(key: "Down", modifiers: .option)))
        XCTAssertFalse(FocusedListKeys.contains(KeyBinding(key: "Space")))
        XCTAssertFalse(FocusedListKeys.contains(KeyBinding(key: "Right", modifiers: .command)))
        XCTAssertFalse(FocusedListKeys.contains(KeyBinding(key: "Left", modifiers: .option)))
        XCTAssertFalse(FocusedListKeys.contains(KeyBinding(key: "f")))
    }
}
