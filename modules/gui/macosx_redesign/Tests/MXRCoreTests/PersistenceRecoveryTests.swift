import XCTest
@testable import MXRCore

/// JSON stores keep what they can read and never overwrite a file they could not (LB-12, R05).
@MainActor
final class PersistenceRecoveryTests: XCTestCase {
    private var directory: URL!
    private var location: PersistenceLocation { .directory(directory) }

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ text: String, to name: String) throws {
        try Data(text.utf8).write(to: directory.appendingPathComponent(name))
    }

    private func setAside(_ name: String) throws -> [URL] {
        let stem = (name as NSString).deletingPathExtension + ".unreadable-"
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(stem) }
    }

    private func object(_ name: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent(name)))
    }

    func testCurrentVersionFilesRoundTripUnchanged() throws {
        let media = MediaItem(id: "ml:7", mrl: "file:///a.mp4", title: "A", fileName: "a.mp4", kind: .video,
                              duration: .zero, progress: 0.5, playCount: 2, isFavorite: true, artist: "X",
                              episode: EpisodeInfo(showName: "S", season: 1, episode: 2), videoSize: CGSize(width: 1920, height: 1080))
        let pins = PinStore(location: location)
        pins.pin(.media(media), title: "A")
        pins.pin(.location(.recent), title: "Recents")
        let recents = RecentStore(location: location)
        recents.record(media, at: Date(timeIntervalSinceReferenceDate: 1000))
        let layouts = LayoutStore(location: location)
        layouts.beginEditing(profileID: "default", kind: .video)
        layouts.updateDraft { $0 = .twoRowExample }
        layouts.commit()
        let presets = PresetStore(location: location)
        presets.save(PlaybackPreset(id: "p", name: "Anime", subtitleDelay: .zero))
        presets.assign("p", to: media)
        let profiles = ProfileStore(location: location)
        profiles.create(name: "Movies")
        let before = try ["pins.json", "recents.json", "layouts.json", "presets.json", "profiles.json"].map { try Data(contentsOf: directory.appendingPathComponent($0)) }

        XCTAssertEqual(PinStore(location: location).pins, pins.pins)
        XCTAssertEqual(RecentStore(location: location).entries, recents.entries)
        XCTAssertEqual(LayoutStore(location: location).layout(profileID: "default", kind: .video), .twoRowExample)
        XCTAssertEqual(PresetStore(location: location).presets, presets.presets)
        XCTAssertEqual(ProfileStore(location: location).profiles.map(\.name), ["Default", "Movies"])
        // Plain JSON arrays and objects, as before: reopening (ProfileStore re-saves) changes no byte.
        let after = try ["pins.json", "recents.json", "layouts.json", "presets.json", "profiles.json"].map { try Data(contentsOf: directory.appendingPathComponent($0)) }
        XCTAssertEqual(before, after)
        XCTAssertTrue(try object("pins.json") is [Any])
        XCTAssertTrue(try object("layouts.json") is [String: Any])
        XCTAssertTrue(try setAside("pins.json").isEmpty)
    }

    func testFileWithOneBadElementKeepsTheOthers() throws {
        try write("""
        [
          {"id": "1", "title": "Good", "target": {"location": {"_0": {"recent": {}}}}},
          {"id": "2", "title": "Bad", "target": {"somethingNew": {}}},
          {"id": "3", "title": "Media", "target": {"media": {"_0": {"id": "ml:3", "mrl": "file:///b.mp3", "title": "B", "kind": "audio", "playCount": 0, "isFavorite": false}}}}
        ]
        """, to: "pins.json")
        let pins = PinStore(location: location)
        XCTAssertEqual(pins.pins.map(\.id), ["1", "3"])
        // The original, with the entry this version cannot read, is kept next to the file.
        XCTAssertEqual(try setAside("pins.json").count, 1)
    }

    func testRepeatedLoadsOfTheSameLossyFileKeepOneCopy() throws {
        try write("""
        [{"id": "1", "title": "Good", "target": {"location": {"_0": {"recent": {}}}}}, {"id": "2", "title": "Bad", "target": {"somethingNew": {}}}]
        """, to: "pins.json")
        _ = PinStore(location: location)
        _ = PinStore(location: location)
        XCTAssertEqual(try setAside("pins.json").count, 1)
    }

    func testCorruptFileIsPreservedAsideAndNotOverwritten() throws {
        let corrupt = "{ not json"
        try write(corrupt, to: "recents.json")
        let recents = RecentStore(location: location)
        XCTAssertTrue(recents.entries.isEmpty)
        recents.record(MediaItem(url: URL(fileURLWithPath: "/tmp/a.mp4")))
        let aside = try setAside("recents.json")
        XCTAssertEqual(aside.count, 1)
        XCTAssertEqual(aside.first?.pathExtension, "json")
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(aside.first), encoding: .utf8), corrupt)
        XCTAssertEqual(RecentStore(location: location).entries.count, 1)
    }

    func testLayoutWithUnknownControlKeepsTheRest() throws {
        try write("""
        {
          "default/video": {
            "top": [{"id": "t-0", "control": "logo"}, {"id": "t-1", "control": "hologram"}, {"id": "t-2", "control": "title"}],
            "bottom": [[{"id": "b-0", "control": "playPause"}], [{"id": "b-1", "control": "teleport"}]]
          },
          "default/music": {"top": 3}
        }
        """, to: "layouts.json")
        let layout = LayoutStore(location: location).layout(profileID: "default", kind: .video)
        XCTAssertEqual(layout.top.map(\.control), [.logo, .title])
        XCTAssertEqual(layout.bottom.map { $0.map(\.control) }, [[.playPause]])
        XCTAssertEqual(LayoutStore(location: location).layout(profileID: "default", kind: .music), .music)
    }

    func testMediaItemFromOlderVersionDecodesWithDefaults() throws {
        try write("""
        [{"media": {"id": "ml:1", "mrl": "https://radio.example/stream", "title": "Radio", "kind": "hologram"}, "date": 0}]
        """, to: "recents.json")
        let entry = try XCTUnwrap(RecentStore(location: location).entries.first)
        XCTAssertEqual(entry.media.kind, .stream)
        XCTAssertEqual(entry.media.playCount, 0)
        XCTAssertFalse(entry.media.isFavorite)
    }

    func testPresetFileWithOneBadPresetKeepsTheOthers() throws {
        try write("""
        {"presets": [{"id": "a", "name": "Anime"}, {"id": "b"}], "assignments": {"show": "a"}}
        """, to: "presets.json")
        let presets = PresetStore(location: location)
        XCTAssertEqual(presets.customPresets.map(\.id), ["a"])
        XCTAssertEqual(presets.assignments, ["show": "a"])
    }

    func testProfileStoreLaunchWithUnreadableFilePreservesIt() throws {
        let unreadable = #"{"profiles": "oops", "currentID": "movies"}"#
        try write(unreadable, to: "profiles.json")
        let store = ProfileStore(location: location)
        XCTAssertEqual(store.profiles.map(\.id), ["default"])
        let aside = try setAside("profiles.json")
        XCTAssertEqual(aside.count, 1)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(aside.first), encoding: .utf8), unreadable)
        // A second launch reads the fresh file and leaves the preserved one alone.
        _ = ProfileStore(location: location)
        XCTAssertEqual(try setAside("profiles.json").count, 1)
    }

    func testProfileFileWithOneBadProfileKeepsTheOthers() throws {
        try write("""
        {"profiles": [{"id": "movies", "name": "Movies"}, {"name": "No id"}], "currentID": "movies"}
        """, to: "profiles.json")
        let store = ProfileStore(location: location)
        XCTAssertEqual(store.profiles.map(\.id), ["movies"])
        XCTAssertEqual(store.currentID, "movies")
        XCTAssertEqual(try setAside("profiles.json").count, 1)
    }

    private func json(_ text: String) throws -> NSObject {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSObject)
    }

    func testUnreadableEntriesSurviveTheNextSave() throws {
        let unknownPin = #"{"id": "2", "title": "Bad", "target": {"somethingNew": {"_0": {"n": 1.5, "big": 9007199254740993, "flag": true, "none": null}}}}"#
        try write("[" + #"{"id": "1", "title": "Good", "target": {"location": {"_0": {"recent": {}}}}}"# + ", " + unknownPin + "]", to: "pins.json")
        let pins = PinStore(location: location)
        pins.pin(.location(.music), title: "Music")
        let saved = try XCTUnwrap(object("pins.json") as? [NSObject])
        XCTAssertEqual(saved.count, 3)
        XCTAssertEqual(saved[1], try json(unknownPin), "kept in place, unchanged")
        XCTAssertEqual(PinStore(location: location).pins.map(\.title), ["Good", "Music"])

        let unknownPreset = #"{"id": "b"}"#
        try write(#"{"presets": [{"id": "a", "name": "Anime"}, "# + unknownPreset + #"], "assignments": {}}"#, to: "presets.json")
        PresetStore(location: location).rename(id: "a", to: "Anime 2")
        let presets = try XCTUnwrap((object("presets.json") as? [String: Any])?["presets"] as? [NSObject])
        XCTAssertEqual(presets.last, try json(unknownPreset))

        let unknownProfile = #"{"name": "No id"}"#
        try write(#"{"profiles": [{"id": "movies", "name": "Movies"}, "# + unknownProfile + #"], "currentID": "movies"}"#, to: "profiles.json")
        ProfileStore(location: location).create(name: "Work")
        let profiles = try XCTUnwrap((object("profiles.json") as? [String: Any])?["profiles"] as? [NSObject])
        XCTAssertEqual(profiles[1], try json(unknownProfile))
        XCTAssertEqual(profiles.count, 3)
    }

    func testUnreadableLayoutsAndControlsSurviveTheNextSave() throws {
        let unknownLayout = #"{"top": 3}"#
        let unknownItem = #"{"id": "t-1", "control": "hologram"}"#
        try write("""
        {
          "default/video": {"top": [{"id": "t-0", "control": "logo"}, \(unknownItem)], "bottom": [[{"id": "b-0", "control": "playPause"}]]},
          "default/music": \(unknownLayout)
        }
        """, to: "layouts.json")
        let store = LayoutStore(location: location)
        store.beginEditing(profileID: "movies", kind: .video)
        store.updateDraft { $0 = .twoRowExample }
        store.commit()
        let saved = try XCTUnwrap(object("layouts.json") as? [String: NSObject])
        XCTAssertEqual(saved["default/music"], try json(unknownLayout))
        let video = try XCTUnwrap(saved["default/video"] as? [String: Any])
        XCTAssertEqual((video["top"] as? [NSObject])?.last, try json(unknownItem))
        // The control this version cannot show does not count as a change.
        XCTAssertEqual(LayoutStore(location: location).layout(profileID: "default", kind: .video).top.map(\.control), [.logo])
        store.reset(profileID: "default", kind: .music)
        XCTAssertNil((try object("layouts.json") as? [String: Any])?["default/music"])
    }

    func testLayoutKeepsEmptyRowsAndPlaceOfHiddenRows() throws {
        let text = """
        {"default/video": {"top": [], "bottom": [[{"id": "a", "control": "previous"}], [], [{"id": "x", "control": "teleport"}], [{"id": "b", "control": "next"}]]}}
        """
        try write(text, to: "layouts.json")
        let store = LayoutStore(location: location)
        let layout = store.layout(profileID: "default", kind: .video)
        XCTAssertEqual(layout.bottom.map { $0.map(\.control) }, [[.previous], [], [.next]])
        store.beginEditing(profileID: "other", kind: .music)
        store.updateDraft { $0 = .twoRowExample }
        store.commit()
        let saved = try XCTUnwrap((object("layouts.json") as? [String: NSObject])?["default/video"])
        XCTAssertEqual(saved, try XCTUnwrap(json(text) as? [String: NSObject])["default/video"])
    }

    func testImportPinnedBeforeTheImportFlagIsStillRecognized() throws {
        let pins = PinStore(location: location)
        var media = MediaItem(id: "ml:9", mrl: "file:///c.mp4", title: "C", kind: .video)
        pins.pin(.media(media), title: "C")
        media.importedFile = true
        media.playCount = 1
        XCTAssertTrue(pins.isPinned(.media(media)))
        pins.pin(.media(media), title: "C")
        XCTAssertEqual(pins.pins.count, 1)
        pins.unpin(.media(media))
        XCTAssertTrue(pins.pins.isEmpty)
    }
}
