import XCTest
@testable import MXRCore
@testable import MXRMockBackend

@MainActor
private final class LiveProfileSettings {
    var values: [String: SettingValue]
    init(_ values: [String: SettingValue]) { self.values = values }
}

@MainActor
final class ProfileAuditRegressionTests: XCTestCase {
    func testStartupPreservesEngineChangesAndMigratesSnapshotsWithoutChangingLayout() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let location = PersistenceLocation.directory(dir)
        struct LegacySnapshot: Encodable { var profiles: [Profile]; var currentID: String }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stale = ["auhal-volume": SettingValue.integer(294), "macosx-redesign-key-app-open-files": .string("Ctrl+o"),
                     AppearanceModel.accentOption: .string("red")]
        let legacy = LegacySnapshot(profiles: [Profile(id: "movies", name: "Movies", settings: stale),
                                               Profile(id: "music", name: "Music", settings: stale)], currentID: "movies")
        try JSONEncoder().encode(legacy).write(to: dir.appendingPathComponent("profiles.json"))
        let layouts = LayoutStore(location: location)
        layouts.beginEditing(profileID: "movies", kind: .video)
        layouts.updateDraft { $0 = .twoRowExample }
        layouts.commit()
        var engine: [String: SettingValue] = ["auhal-volume": .integer(267),
            "macosx-redesign-key-app-open-files": .string("Command+o"), AppearanceModel.accentOption: .string("blue")]
        let reopened = ProfileStore(location: location)
        var applications = 0
        reopened.connect(snapshot: { engine }, apply: { applications += 1; engine.merge($0) { _, new in new } })
        XCTAssertEqual(applications, 0)
        XCTAssertEqual(engine["auhal-volume"], .integer(267))
        XCTAssertEqual(engine["macosx-redesign-key-app-open-files"], .string("Command+o"))
        XCTAssertEqual(reopened.current.settings[AppearanceModel.accentOption], .string("blue"))
        XCTAssertNil(reopened.current.settings["auhal-volume"])
        XCTAssertNil(reopened.current.settings["macosx-redesign-key-app-open-files"])
        let migrated = ProfileStore(location: location)
        XCTAssertEqual(migrated.current.id, "movies")
        XCTAssertEqual(migrated.profiles.map(\.name), ["Movies", "Music"])
        XCTAssertTrue(migrated.profiles.allSatisfy { $0.settings["auhal-volume"] == nil && $0.settings["macosx-redesign-key-app-open-files"] == nil })
        XCTAssertEqual(migrated.profiles.last?.settings[AppearanceModel.accentOption], .string("red"))
        XCTAssertEqual(LayoutStore(location: location).layout(profileID: "movies", kind: .video), .twoRowExample)
    }

    func testSnapshotsAndLiveEventsOnlyRetainCatalogOptionsAndSwitchExplicitly() {
        let store = ProfileStore(location: .inMemory)
        let live = LiveProfileSettings([AppearanceModel.accentOption: .string("red"), "auhal-volume": .integer(123)])
        var applied: [[String: SettingValue]] = []
        store.connect(snapshot: { live.values }, apply: { applied.append($0) })
        let other = store.create(name: "Other")
        live.values[AppearanceModel.accentOption] = .string("blue")
        store.recordSetting(.integer(456), name: "auhal-volume")
        store.select(other)
        XCTAssertEqual(applied, [[AppearanceModel.accentOption: .string("red")]])
        XCTAssertTrue(store.profiles.allSatisfy { $0.settings["auhal-volume"] == nil })
        XCTAssertEqual(store.profiles.first?.settings[AppearanceModel.accentOption], .string("blue"))
    }

    func testCapturedAutomaticRestoresBothTracksAfterPersistence() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let app = AppModel.mock(.playingEpisode)
        app.tracks.setTrackDefaults(TrackDefaults())
        let store = PresetStore(location: .directory(dir))
        let captured = store.capture(name: "Automatic", tracks: app.tracks, audio: app.audioEffects, video: app.videoEffects)
        app.tracks.updateTrackDefaults { $0.subtitleTrack = 3; $0.subtitleLanguage = "French"; $0.audioTrack = 2; $0.audioLanguage = "Japanese" }
        let restored = try XCTUnwrap(PresetStore(location: .directory(dir)).preset(id: captured.id))
        store.apply(restored, tracks: app.tracks, audio: app.audioEffects, video: app.videoEffects)
        XCTAssertEqual(app.tracks.trackDefaults, TrackDefaults())
    }

    func testSubtitleOnlyAutomaticDoesNotResetUncapturedAudio() {
        let app = AppModel.mock(.playingEpisode)
        app.tracks.setTrackDefaults(TrackDefaults())
        let store = PresetStore(location: .inMemory)
        let captured = store.capture(name: "Subtitles", sections: .subtitles, tracks: app.tracks, audio: app.audioEffects, video: app.videoEffects)
        app.tracks.updateTrackDefaults { $0.subtitleTrack = 3; $0.subtitleLanguage = "French"; $0.audioTrack = 2; $0.audioLanguage = "Japanese" }
        store.apply(captured, tracks: app.tracks, audio: app.audioEffects, video: app.videoEffects)
        XCTAssertNil(app.tracks.trackDefaults.subtitleTrack)
        XCTAssertNil(app.tracks.trackDefaults.subtitleLanguage)
        XCTAssertEqual(app.tracks.trackDefaults.audioTrack, 2)
        XCTAssertEqual(app.tracks.trackDefaults.audioLanguage, "Japanese")
    }
    func testLegacyCapturedAutomaticMigratesButSparsePresetLeavesOtherChoicesAlone() throws {
        let app = AppModel.mock(.playingEpisode)
        app.tracks.setTrackDefaults(TrackDefaults())
        let store = PresetStore(location: .inMemory)
        let captured = store.capture(name: "Old capture", tracks: app.tracks, audio: app.audioEffects, video: app.videoEffects)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(captured)) as? [String: Any])
        json.removeValue(forKey: "subtitleTrackDefaults")
        json.removeValue(forKey: "audioTrackDefaults")
        let legacy = try JSONDecoder().decode(PlaybackPreset.self, from: JSONSerialization.data(withJSONObject: json))
        app.tracks.updateTrackDefaults { $0.subtitleTrack = 3; $0.audioLanguage = "French" }
        store.apply(legacy, tracks: app.tracks, audio: app.audioEffects, video: app.videoEffects)
        XCTAssertEqual(app.tracks.trackDefaults, TrackDefaults())
        app.tracks.updateTrackDefaults { $0.subtitleTrack = 3; $0.audioTrack = 2 }
        store.apply(PlaybackPreset(name: "Language only", audioLanguage: "Japanese"), tracks: app.tracks, audio: app.audioEffects, video: app.videoEffects)
        XCTAssertEqual(app.tracks.trackDefaults.subtitleTrack, 3)
        XCTAssertEqual(app.tracks.trackDefaults.audioTrack, 2)
        XCTAssertEqual(app.tracks.trackDefaults.audioLanguage, "Japanese")
    }

}
