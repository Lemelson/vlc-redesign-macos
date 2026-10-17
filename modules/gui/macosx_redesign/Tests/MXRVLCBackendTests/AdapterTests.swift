import MXRBridgeAPI
import XCTest
import CoreFoundation
@testable import MXRVLCBackend
import MXRCore

@MainActor
final class AdapterTests: XCTestCase {
    /// Recorded by MXRServicesBridge against real libvlccore with --ignore-config.
    func testRealNativeFixturePreservesSchemaAndEngineEnumValues() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "native-service-fixture", withExtension: "json", subdirectory: "Resources"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let service = TestServices()
        service.snapshots = fixture.compactMapValues { $0 as? [String: Any] }
        let queue = VLCQueueBackend(transport: service)
        XCTAssertEqual(queue.items.map(\.media.title), ["B", "C"])
        XCTAssertEqual(queue.mediaStoppedAction, .stop)
        XCTAssertNil(queue.currentIndex)
        XCTAssertEqual(VLCPlayerBackend(transport: service).state, .stopped)
        let settings = VLCSettingsBackend(transport: service)
        XCTAssertEqual(settings.value(for: "network-caching"), .integer(2345))
        XCTAssertEqual(settings.option(named: "network-caching")?.type, .integer)
        XCTAssertEqual(settings.option(named: "network-caching")?.defaultValue, .integer(1000))
        XCTAssertEqual(settings.value(for: "audio"), .bool(true))
        // The native track-defaults roundtrip clears the audio language preference.
        XCTAssertEqual(settings.value(for: "audio-language"), .string(""))
        XCTAssertEqual(settings.value(for: "rate"), .float(1))
        let flags = VLCWire.capabilities(fixture.dictionary("capabilities"))
        XCTAssertTrue(flags.hasThumbnails)
        XCTAssertTrue(flags.hasRecording)
        XCTAssertFalse(flags.hasMediaLibrary)
        XCTAssertEqual(flags.pictureInPicture, .unsupported)
        XCTAssertTrue(VLCShortcutsBackend(transport: service).actions.contains { $0.id == "play-pause" })
    }

    func testRealNativeEffectsFixtureDecodesAllTypedPlayerSettings() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "native-service-fixture", withExtension: "json", subdirectory: "Resources"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let snapshot = fixture.dictionary("player")
        let video = VLCWire.decode(VideoEffects.self, from: snapshot.dictionary("videoEffects"))
        let audio = VLCWire.decode(AudioEffects.self, from: snapshot.dictionary("audioEffects"))
        let style = VLCWire.decode(SubtitleStyle.self, from: snapshot.dictionary("subtitleStyle"))
        let defaults = VLCWire.decode(TrackDefaults.self, from: snapshot.dictionary("trackDefaults"))
        XCTAssertNotNil(video)
        XCTAssertNotNil(audio)
        XCTAssertNotNil(style)
        XCTAssertNotNil(defaults)
        XCTAssertEqual(video?.essential.hue, -30)
        XCTAssertEqual(video?.colors.gradientColor, false)
        XCTAssertEqual(video?.colors.cartoon, true)
        XCTAssertEqual(audio?.equalizer.twoPass, false)
        XCTAssertEqual(style?.bold, false)
        XCTAssertEqual(style?.shadow, true)
        XCTAssertEqual(style?.background, false)
        XCTAssertEqual(style?.relativeSize, .smaller)
        XCTAssertEqual(defaults?.audioTrack, 2)
        XCTAssertEqual(defaults?.subtitleLanguage, "ru")
        let service = TestServices()
        service.snapshots["player"] = snapshot
        let player = VLCPlayerBackend(transport: service)
        XCTAssertEqual(player.videoEffects, video)
        XCTAssertEqual(player.audioEffects, audio)
        XCTAssertEqual(player.subtitleStyle, style)
        XCTAssertEqual(player.trackDefaults, defaults)
        XCTAssertEqual(player.subtitleTextScale, 80)
    }

    func testPlayerReadsEngineStateAndEmitsVolumeChanges() throws {
        let service = TestServices()
        service.snapshots["player"] = ["state": 2, "media": ["id": "ml:42", "url": "file:///tmp/music.flac", "title": "Music", "kind": "audio", "duration": Int64(120_000_000)], "volume": 1.5, "canSeek": true]
        let player = VLCPlayerBackend(transport: service)
        XCTAssertEqual(player.currentMedia?.id, "ml:42")
        XCTAssertEqual(player.currentMedia?.kind, .audio)
        XCTAssertEqual(player.currentMedia?.duration, .seconds(120))
        XCTAssertEqual(player.volume, 1.5)
        XCTAssertEqual(player.state, .playing)
        var events: [PlayerEvent] = []
        player.addListener(self) { events.append($0) }
        service.snapshots["player"]?["volume"] = 0.75
        service.emit("player")
        XCTAssertEqual(player.volume, 0.75)
        XCTAssertTrue(events.contains(.volume))
    }

    /// Recorded from the native effects helper with deinterlace=1 and its default auto method.
    func testNativeForcedAutomaticDeinterlacePreservesEffectsSnapshot() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "native-deinterlace-forced-auto", withExtension: "json", subdirectory: "Resources"))
        let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let effects = try XCTUnwrap(VLCWire.decode(VideoEffects.self, from: snapshot))
        XCTAssertEqual(effects.deinterlace.rawValue, "auto")
        XCTAssertNotEqual(effects.deinterlace, .automatic, "Forced-on automatic method differs from automatic enable policy.")
        XCTAssertEqual(effects.zoom, .fitWindow)
        let service = TestServices()
        service.snapshots["player"] = ["videoEffects": snapshot]
        XCTAssertEqual(VLCPlayerBackend(transport: service).videoEffects, effects)
    }

    /// Captured after real AAC media loading and a custom equalizer edit in the native smoke harness.
    func testRealNativeMediaFixtureKeepsAudioMetadataAndCustomEqualizer() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "native-media-effects-fixture", withExtension: "json", subdirectory: "Resources"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let service = TestServices()
        service.snapshots = fixture.compactMapValues { $0 as? [String: Any] }
        let player = VLCPlayerBackend(transport: service)
        XCTAssertEqual(player.currentMedia?.kind, .audio)
        XCTAssertEqual(player.currentMedia?.title, "Native Song")
        XCTAssertEqual(player.currentMedia?.artist, "Bridge Artist")
        XCTAssertEqual(player.currentMedia?.album, "Bridge Album")
        XCTAssertTrue(player.audioEffects.equalizer.isEnabled)
        XCTAssertNil(player.audioEffects.equalizer.presetID, "Editing a native band must preserve the custom preset state.")
        XCTAssertEqual(player.audioEffects.equalizer.bands.first, 9)
    }

    /// Captured after the isolated native tone completed with decoded and played audio buffers.
    func testRealNativeAudioServicesFixtureHasUsableCapabilitiesAndPlaybackEvidence() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "native-media-effects-fixture", withExtension: "json", subdirectory: "Resources"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let capabilities = fixture.dictionary("capabilities")
        let flags = VLCWire.capabilities(capabilities)
        XCTAssertTrue(flags.hasStereoTest)
        XCTAssertTrue(flags.supportsWaveform)
        for name in ["stereoTest", "supportsWaveform"] {
            XCTAssertEqual(CFGetTypeID(try XCTUnwrap(capabilities[name] as? NSNumber)), CFBooleanGetTypeID())
        }
        let audioTest = fixture.dictionary("audioTest")
        XCTAssertEqual(audioTest.string("state"), "completed")
        XCTAssertGreaterThan(audioTest.integer("decodedAudio"), 0)
        XCTAssertGreaterThan(audioTest.integer("playedAudioBuffers"), 0)
        XCTAssertEqual(audioTest.double("volume"), 0.25)
        XCTAssertEqual(VLCWire.media(fixture.dictionary("player").dictionary("media"))?.title, "Native Song", "The isolated tone leaves main media selected.")
    }

    /// The final real bridge run uses an actual audio-output callback at 250% volume.
    func testFinalNativeFixturePreservesExtendedVolumeAndTypedEffects() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "native-media-effects-fixture", withExtension: "json", subdirectory: "Resources"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let snapshot = fixture.dictionary("player")
        let service = TestServices()
        service.snapshots = fixture.compactMapValues { $0 as? [String: Any] }
        let player = VLCPlayerBackend(transport: service)
        XCTAssertEqual(player.volume, 2.5, "The bridge must preserve volumes above 100% once the real output is ready.")
        XCTAssertNotNil(VLCWire.decode(VideoEffects.self, from: snapshot.dictionary("videoEffects")))
        XCTAssertNotNil(VLCWire.decode(AudioEffects.self, from: snapshot.dictionary("audioEffects")))
        XCTAssertNotNil(VLCWire.decode(SubtitleStyle.self, from: snapshot.dictionary("subtitleStyle")))
        XCTAssertNotNil(VLCWire.decode(TrackDefaults.self, from: snapshot.dictionary("trackDefaults")))
        for value in fixture.dictionary("capabilities").values {
            XCTAssertEqual(CFGetTypeID(try XCTUnwrap(value as? NSNumber)), CFBooleanGetTypeID())
        }
        let output = VLCOutputBackend(transport: service)
        XCTAssertTrue(output.isAvailable)
        XCTAssertEqual(output.profiles.map(\.id), ["copy", "h264", "audio"])
        XCTAssertEqual(output.profiles.map(\.fileExtension), ["ts", "mp4", "mp3"])
        XCTAssertTrue(output.jobs.isEmpty)
        let sources = VLCMediaSourcesBackend(transport: service)
        XCTAssertEqual(sources.sources(in: .myComputer).map(\.id), ["mxr.local.folders"])
        XCTAssertEqual(sources.sources(in: .devices).map(\.id), ["mxr.local.volumes"])
        let renderers = VLCRendererBackend(transport: service)
        XCTAssertNil(renderers.selectedID)
        XCTAssertFalse(renderers.isDiscovering)
    }

    func testNativeWaveformUsesNestedMediaAndSamplesResponse() async throws {
        let service = TestServices()
        service.capabilities = ["supportsWaveform": true]
        service.snapshots["thumbnails"] = ["samples": [NSNumber(value: 0.1), NSNumber(value: 0.7)], "duration": 1.5]
        let media = MediaItem(url: URL(fileURLWithPath: "/tmp/stereo.wav"))
        let samples = await VLCThumbnailBackend(transport: service).waveform(for: media, bins: 2)
        XCTAssertEqual(samples, [Float(0.1), Float(0.7)])
        let command = try XCTUnwrap(service.commands.last)
        XCTAssertEqual(command.name, "waveform")
        XCTAssertEqual(command.service, "thumbnails")
        XCTAssertEqual(command.arguments.dictionary("media").string("id"), media.id)
        XCTAssertEqual(command.arguments.dictionary("media").string("url"), media.mrl)
        XCTAssertEqual(command.arguments["bins"] as? Int, 2)
    }

    func testStereoOutputUsesIsolatedServiceAndKeepsFailureInAudioPanel() async throws {
        let service = TestServices()
        service.capabilities = ["stereoTest": true]
        service.snapshots["player"] = ["audioEffects": VLCWire.dictionary(AudioEffects(stereoMode: .left)), "currentAudioDeviceID": "device42"]
        service.snapshots["audioTest"] = ["state": "completed"]
        let player = VLCPlayerBackend(transport: service)
        try await player.testStereoOutput()
        let request = try XCTUnwrap(service.commands.last)
        XCTAssertEqual(request.name, "start")
        XCTAssertEqual(request.service, "audioTest")
        XCTAssertEqual(request.arguments["mode"] as? Int, StereoMode.left.rawValue)
        XCTAssertEqual(request.arguments["deviceID"] as? String, "device42")
        XCTAssertTrue(VLCWire.capabilities(service.capabilities).hasStereoTest)
        service.failure = BackendOperationError.invalidInput("Output device is unavailable.")
        let model = AudioEffectsModel(backend: player)
        await model.testStereoOutput()
        XCTAssertEqual(model.testOutputError, "Output device is unavailable.")
        XCTAssertTrue(service.reportedErrors.isEmpty, "A throwing stereo test reports into its panel rather than a global playback error.")
        XCTAssertNil(player.errorMessage)
    }

    func testCancellingStereoOutputStopsIsolatedNativeTone() async throws {
        let service = TestServices()
        service.suspendsStereoTest = true
        let player = VLCPlayerBackend(transport: service)
        let test = Task { try await player.testStereoOutput() }
        while service.stereoContinuation == nil { await Task.yield() }
        test.cancel()
        for _ in 0..<100 where service.stereoContinuation != nil { await Task.yield() }
        // Cleanup keeps the regression test bounded when native cancellation is missing.
        if let pending = service.stereoContinuation {
            service.stereoContinuation = nil
            pending.resume(throwing: CancellationError())
        }
        do { try await test.value; XCTFail("A cancelled tone must not complete as success.") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(service.commands.map(\.name), ["start", "cancel"])
        XCTAssertTrue(service.commands.allSatisfy { $0.service == "audioTest" })
        XCTAssertTrue(service.reportedErrors.isEmpty)
        service.suspendsStereoTest = false
        try await player.testStereoOutput()
        XCTAssertEqual(service.commands.map(\.name), ["start", "cancel", "start"], "A completed retry must not send cancellation.")
    }

    func testAutomaticLibraryReadsDoNotPresentErrorsWithoutMediaLibrary() async throws {
        let service = TestServices()
        service.capabilities = ["library": false]
        service.failure = BackendOperationError.unsupported("Media library")
        let library = VLCLibraryBackend(transport: service)
        let crumbs = await library.breadcrumb(for: .home)
        let media = await library.media(id: "file:///tmp/movie.mp4")
        let bookmarks = await library.bookmarks(mediaID: "file:///tmp/movie.mp4")
        XCTAssertEqual(crumbs.map(\.title), ["Home"])
        XCTAssertNil(media)
        XCTAssertTrue(bookmarks.isEmpty)
        XCTAssertTrue(service.commands.isEmpty)
        XCTAssertTrue(service.reportedErrors.isEmpty, "Automatic reads cannot open unsupported-feature dialogs.")
        library.setFavorite(true, mediaIDs: ["file:///tmp/movie.mp4"])
        XCTAssertEqual(service.reportedErrors.count, 1, "Explicit unsupported mutations still report a useful error.")

        service.reportedErrors.removeAll()
        service.capabilities = ["library": true]
        _ = await library.breadcrumb(for: .home)
        _ = await library.bookmarks(mediaID: "ml:42")
        XCTAssertTrue(service.reportedErrors.isEmpty, "Background read failures must stay optional.")
        XCTAssertEqual(service.loggedErrors.count, 2)
    }

    /// ARC-11, R13, MISS-03: a player command that cannot run is a transient OSD notice. It is
    /// never the playback-error card (engine input errors only) and never a dialog.
    func testPlayerCommandFailureIsATransientNoticeNotAPlaybackError() {
        let service = TestServices()
        let backend = VLCPlayerBackend(transport: service)
        let player = PlayerModel(backend: backend)
        service.failure = NSError(domain: "player", code: 1, userInfo: [NSLocalizedDescriptionKey: "Audio output rejected the volume."])
        player.setVolume(0.5)
        XCTAssertNil(player.errorMessage)
        XCTAssertEqual(service.notices, ["Audio output rejected the volume."])
        XCTAssertTrue(service.reportedErrors.isEmpty, "No dialog for a player command.")

        service.failure = nil
        service.snapshots["player.state"] = ["state": 0, "errorMessage": "The source disconnected"]
        service.emit("player.state")
        XCTAssertEqual(player.errorMessage, "The source disconnected", "Engine input errors still reach the card.")
        service.failure = NSError(domain: "player", code: 2)
        player.play()
        XCTAssertEqual(player.errorMessage, "The source disconnected")
        service.snapshots["player.state"] = ["state": 2]
        service.emit("player.state")
        XCTAssertNil(player.errorMessage)
    }

    /// BB-02, ARC-02: commands never re-read state; an engine topic re-reads only its keys.
    func testCommandsAreFireAndForgetAndTopicsReloadOnlyTheirKeys() {
        let service = TestServices()
        service.snapshots["player"] = ["state": 2, "volume": 1.0, "rate": 1.0, "audioTracks": [["id": "audio/1", "name": "Track 1", "selected": true]]]
        let player = VLCPlayerBackend(transport: service)
        var events: [PlayerEvent] = []
        player.addListener(self) { events.append($0) }
        service.snapshotReads.removeAll()
        player.setVolume(0.4)
        player.seek(toPosition: 0.5, precision: .fast)
        XCTAssertTrue(service.snapshotReads.isEmpty, "A command must not snapshot the player.")
        XCTAssertEqual(player.volume, 1.0, "The value changes when the engine reports it.")

        service.snapshots["player.volume"] = ["volume": 0.4, "isMuted": false]
        service.emit("player.volume")
        XCTAssertEqual(service.snapshotReads, ["player.volume"])
        XCTAssertEqual(player.volume, 0.4)
        XCTAssertEqual(events, [.volume])
        XCTAssertEqual(player.state, .playing, "Other topics keep their values.")
        XCTAssertEqual(player.tracks(of: .audio).first?.name, "Track 1")

        events.removeAll()
        service.snapshots["player.state"] = ["state": 3, "rate": 1.0]
        service.emit("player.state")
        XCTAssertEqual(player.state, .paused)
        XCTAssertEqual(events, [.state])
    }

    /// R12: a slave source's tracks are External Tracks, named after their file.
    func testExternalTracksCarryTheirFile() {
        let service = TestServices()
        service.snapshots["player"] = ["subtitleTracks": [
            ["id": "spu/2", "name": "Track 1 - [English]", "language": "en", "selected": false],
            ["id": "0123456789abcdef0123456789abcdef/spu/0", "name": "The_Wand_S01_EN.srt", "external": true,
             "url": "file:///Shows/The%20Wand/The_Wand_S01_EN.srt", "selected": true],
        ]]
        let tracks = TracksModel(backend: VLCPlayerBackend(transport: service))
        XCTAssertEqual(tracks.embeddedTracks(of: .subtitle).map(\.name), ["Track 1 - [English]"])
        XCTAssertEqual(tracks.externalTracks(of: .subtitle).map(\.name), ["The_Wand_S01_EN.srt"])
        XCTAssertEqual(tracks.externalTracks(of: .subtitle).first?.sourceURL?.lastPathComponent, "The_Wand_S01_EN.srt")
    }

    /// ARC-14: the keys Swift reads are produced (snapshot file, PiP, menus, scrambled programs, file name).
    func testMissingProducersReachTheModel() throws {
        let service = TestServices()
        service.snapshots["player"] = ["media": ["url": "file:///tmp/My%20Movie.mkv", "title": "Movie", "fileName": "My Movie.mkv"],
            "titles": [["index": 0, "name": "Menu", "isMenu": true, "length": 0, "chapters": []]],
            "programs": [["id": 3, "name": "News", "selected": true, "scrambled": true]], "isPictureInPicture": true]
        let player = PlayerModel(backend: VLCPlayerBackend(transport: service))
        let backend = try XCTUnwrap(player.backend as? VLCPlayerBackend)
        XCTAssertEqual(backend.currentMedia?.fileName, "My Movie.mkv")
        XCTAssertEqual(backend.titles.first?.isMenu, true)
        XCTAssertEqual(backend.programs.first?.isScrambled, true)
        XCTAssertTrue(player.isPictureInPicture)
        service.snapshots["player.snapshot"] = ["snapshotURL": "file:///tmp/vlcsnap-001.png"]
        service.emit("player.snapshot")
        XCTAssertEqual(player.lastSnapshotURL?.lastPathComponent, "vlcsnap-001.png")
    }

    /// SD-01: the dialog shows human action names (Figma wording, else VLC's text), never ids.
    func testShortcutTitlesAreHumanNamesInTheirFigmaGroups() {
        let service = TestServices()
        service.snapshots["shortcuts"] = ["actions": [
            ["id": "vol-up", "name": "Volume up", "hotkeys": ["Up"], "global": []],
            ["id": "toggle-fullscreen", "name": "Fullscreen", "hotkeys": ["f"], "global": []],
            ["id": "leave-fullscreen", "name": "Exit fullscreen", "hotkeys": ["Esc"], "global": []],
            ["id": "position", "name": "Position", "hotkeys": ["t"], "global": []],
            ["id": "play-pause", "name": "Play/Pause", "hotkeys": ["Space"], "global": []],
            ["id": "projection-toggle", "name": "", "hotkeys": [], "global": []],
            ["id": "crop-top", "name": "Crop one pixel from the top of the video", "hotkeys": [], "global": []],
            ["id": "some-new-action", "name": "", "hotkeys": [], "global": []],
        ], "appBindings": ["macosx-redesign-key-app-hide-ui": "Command+\\"]]
        let actions = VLCShortcutsBackend(transport: service).actions
        let byID = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
        XCTAssertEqual(byID["vol-up"]?.title, "Increase volume")
        XCTAssertEqual(byID["toggle-fullscreen"]?.title, "Toggle fullscreen")
        XCTAssertEqual(byID["leave-fullscreen"]?.title, "Exit fullscreen / close dialog")
        XCTAssertEqual(byID["play-pause"]?.title, "Play / pause")
        XCTAssertEqual(byID["crop-top"]?.title, "Crop one pixel from the top of the video")
        for id in ["toggle-fullscreen", "leave-fullscreen", "position"] { XCTAssertEqual(byID[id]?.group, .basic, id) }
        XCTAssertEqual(byID["play-pause"]?.group, .playback)
        XCTAssertEqual(byID["vol-up"]?.group, .audio)
        let rawID = try! NSRegularExpression(pattern: "^[a-z0-9+-]+$")
        for action in actions {
            XCTAssertNil(rawID.firstMatch(in: action.title, range: NSRange(action.title.startIndex..., in: action.title)), "Raw id shown: \(action.title)")
        }
        XCTAssertEqual(byID["app-hide-ui"]?.hotkeys.first?.modifiers, .command, "App bindings come with the shortcuts snapshot.")
    }

    /// D027, S13: the hotkey's result and the pressed key form one two-line OSD; notices show
    /// even with shortcut feedback off.
    func testOSDPairsEngineFeedbackWithThePressedKeyAndShowsNotices() {
        let service = TestServices()
        let osd = OSDModel(backend: VLCOSDBackend(transport: service))
        osd.keyPressed(KeyBinding(key: "c"))
        service.snapshots["osd"] = ["text": "Crop: 2.35:1", "kind": "feedback", "serial": 1]
        service.emit("osd")
        XCTAssertEqual(osd.message?.text, "Crop: 2.35:1")
        XCTAssertEqual(osd.message?.pressedKeyText, "Pressed C")

        osd.isFeedbackEnabled = false
        osd.hide()
        service.snapshots["osd"] = ["text": "Volume: 48%", "kind": "feedback", "serial": 2]
        service.emit("osd")
        XCTAssertNil(osd.message, "Shortcut feedback obeys the setting.")
        service.snapshots["osd"] = ["text": "The_Wand_S01E04.mkv", "kind": "notice", "duration": 5.0, "serial": 3]
        service.emit("osd")
        XCTAssertEqual(osd.message?.text, "The_Wand_S01E04.mkv")
        XCTAssertNil(osd.message?.pressedKey)
    }

    func testQueuePreservesLargeEngineIdentifiersAndRepeatMeaning() throws {
        let service = TestServices()
        let id = UInt64.max - 4
        service.snapshots["queue"] = ["items": [["id": String(id), "media": ["url": "file:///tmp/a.mp4"]]], "currentIndex": 0, "repeatMode": 1, "order": 1]
        let queue = VLCQueueBackend(transport: service)
        XCTAssertEqual(queue.items.first?.id, id)
        XCTAssertEqual(queue.repeatMode, .one)
        XCTAssertEqual(queue.order, .random)
        queue.move(ids: [id], to: 0)
        XCTAssertEqual(service.commands.last?.arguments["ids"] as? [String], [String(id)])
    }

    /// BB-02: index and mode callbacks publish `queue.state`, which re-reads no item.
    func testQueueStateEventKeepsItemsAndReadsOnlyTheState() throws {
        let service = TestServices()
        service.snapshots["queue"] = ["items": [["id": "1", "media": ["url": "file:///tmp/a.mp4"]], ["id": "2", "media": ["url": "file:///tmp/b.mp4"]]],
                                      "currentIndex": 0, "repeatMode": 0, "order": 0, "hasNext": true]
        let queue = VLCQueueBackend(transport: service)
        var events: [String] = []
        queue.addListener(self) { events.append("\($0)") }
        service.snapshotReads.removeAll()
        service.snapshots["queue"] = [:] // an items read would now empty the queue
        service.snapshots["queue.state"] = ["currentIndex": 1, "repeatMode": 2, "order": 0, "hasNext": false, "hasPrevious": true]
        service.emit("queue.state")
        XCTAssertEqual(service.snapshotReads, ["queue.state"])
        XCTAssertEqual(queue.items.map(\.id), [1, 2])
        XCTAssertEqual(queue.currentIndex, 1)
        XCTAssertEqual(queue.repeatMode, .all)
        XCTAssertFalse(events.contains("items"))
    }

    func testStoppedActionsMatchUpstreamValuesAndPauseUsesPlayAndPause() {
        let service = TestServices()
        service.snapshots["queue"] = ["mediaStoppedAction": 1]
        let queue = VLCQueueBackend(transport: service)
        XCTAssertEqual(queue.mediaStoppedAction, .stop)
        queue.setMediaStoppedAction(.exit)
        XCTAssertEqual(service.commands.last?.arguments["value"] as? Int, 2)
        queue.setMediaStoppedAction(.pause)
        XCTAssertTrue(service.commands.contains { $0.name == "setPauseAtEnd" && $0.arguments["value"] as? Bool == true })
        service.snapshots["queue"] = ["mediaStoppedAction": 0, "pauseAtEnd": true]
        service.emit("queue")
        XCTAssertEqual(queue.mediaStoppedAction, .pause)
    }

    func testCoreQueuePlayNowUsesAtomicNativeCommandAndPreservesQueueOnFailure() {
        let service = TestServices()
        service.snapshots["queue"] = ["items": [["id": "15", "media": ["url": "file:///tmp/old.mp4"]]], "currentIndex": 0]
        let model = QueueModel(backend: VLCQueueBackend(transport: service))
        service.failure = NSError(domain: "test", code: 7, userInfo: [NSLocalizedDescriptionKey: "Invalid new source"])
        model.playNow([MediaItem(url: URL(fileURLWithPath: "/tmp/new.mp4"))])
        XCTAssertTrue(service.commands.isEmpty, "Validation failure must not clear or mutate the existing playlist.")
        XCTAssertEqual(model.items.first?.id, 15)
        XCTAssertEqual(model.errorMessage, "Invalid new source")
        service.failure = nil
        model.playNow([MediaItem(url: URL(fileURLWithPath: "/tmp/new.mp4"))])
        XCTAssertEqual(service.commands.map(\.name), ["playNow"])
        XCTAssertNil(model.errorMessage)
    }

    func testMissingBackgroundArtworkAndPreviewDoNotPresentUserOperationErrors() async {
        let service = TestServices()
        service.failure = NSError(domain: "thumbnail", code: 1, userInfo: [NSLocalizedDescriptionKey: "No cover art is available."])
        let thumbnails = VLCThumbnailBackend(transport: service)
        let media = MediaItem(url: URL(fileURLWithPath: "/tmp/no-cover.mp3"))
        let art = await thumbnails.artwork(for: media, maxPixelSize: CGSize(width: 200, height: 200))
        let preview = await thumbnails.seekPreview(for: media, at: .seconds(10), maxPixelSize: CGSize(width: 200, height: 100))
        XCTAssertNil(art)
        XCTAssertNil(preview)
        XCTAssertTrue(service.reportedErrors.isEmpty, "Optional background images must not open error dialogs.")
        XCTAssertEqual(service.loggedErrors.count, 2)
        // An explicit playback action reports its failure in the OSD, not in a dialog.
        VLCPlayerBackend(transport: service).play()
        XCTAssertEqual(service.notices.count, 1)
        XCTAssertTrue(service.reportedErrors.isEmpty)
    }

    func testInputOptionsPropagateAndEngineFailureThrows() throws {
        let service = TestServices()
        let queue = VLCQueueBackend(transport: service)
        let options = [":sout=#std{access=file,mux=mp4,dst='/tmp/output.mp4'}"]
        try queue.playNow([MediaItem(url: URL(fileURLWithPath: "/tmp/input.mp4"))], startAt: 0, inputOptions: options)
        let items = try XCTUnwrap(service.commands.last?.arguments["items"] as? [[String: Any]])
        XCTAssertEqual(items.first?["options"] as? [String], options)
        service.failure = NSError(domain: "test", code: 7, userInfo: [NSLocalizedDescriptionKey: "Unsupported output"])
        XCTAssertThrowsError(try queue.playNow([MediaItem(url: URL(fileURLWithPath: "/tmp/input.mp4"))], startAt: 0, inputOptions: options))
    }

    func testSettingsKeepsBoolIntegerAndStringTypes() throws {
        let service = TestServices()
        service.snapshots["settings"] = ["options": [["name": "flag", "type": "bool", "defaultValue": true], ["name": "size", "type": "integer", "defaultValue": 123], ["name": "path", "type": "string", "defaultValue": ""]], "values": ["flag": NSNumber(value: false), "size": NSNumber(value: 42), "path": "/tmp/a"]]
        let settings = VLCSettingsBackend(transport: service)
        XCTAssertEqual(settings.value(for: "flag"), .bool(false))
        XCTAssertEqual(settings.value(for: "size"), .integer(42))
        XCTAssertEqual(settings.value(for: "path"), .string("/tmp/a"))
    }
}

@MainActor
private final class TestServices: VLCServiceTransport {
    struct Command { var name: String; var service: String; var arguments: [String: Any] }
    var snapshots: [String: [String: Any]] = [:]
    var commands: [Command] = []
    var failure: Error?
    var suspendsStereoTest = false
    var stereoContinuation: CheckedContinuation<[String: Any], Error>?
    var reportedErrors: [String] = []
    var loggedErrors: [String] = []
    var notices: [String] = []
    var snapshotReads: [String] = []
    let events = EventChannel<MXRBridgeService>()
    var capabilities: [String: Any] = [:]
    func snapshot(for service: MXRBridgeService) -> [String: Any] { let service = service.rawValue; snapshotReads.append(service); return snapshots[service] ?? [:] }
    func perform(_ command: MXRBridgeCommand, service: MXRBridgeService, arguments: [String: Any]) throws { let command = command.rawValue; let service = service.rawValue;
        if let failure { throw failure }
        commands.append(Command(name: command, service: service, arguments: arguments))
    }
    func request(_ request: MXRBridgeRequest, service: MXRBridgeService, arguments: [String: Any]) async throws -> [String: Any] { let request = request.rawValue; let service = service.rawValue;
        if let failure { throw failure }
        commands.append(Command(name: request, service: service, arguments: arguments))
        if service == "audioTest", request == "start", suspendsStereoTest {
            return try await withCheckedThrowingContinuation { stereoContinuation = $0 }
        }
        if service == "audioTest", request == "cancel" {
            stereoContinuation?.resume(throwing: CancellationError())
            stereoContinuation = nil
        }
        return snapshot(for: MXRBridgeService(rawValue: service))
    }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MXRBridgeService) -> Void) { events.add(owner, handler: handler) }
    func emit(_ service: String) { events.send(MXRBridgeService(rawValue: service)) }
    func log(_ error: Error) { loggedErrors.append(error.localizedDescription) }
    func report(_ error: Error) { reportedErrors.append(error.localizedDescription) }
    func notify(_ message: String) { notices.append(message) }
}
