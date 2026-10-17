import AppKit
import Foundation
import MXRCore
import MXRMockBackend
@testable import MXRUI
import SwiftUI
import XCTest

final class DialogsTests: XCTestCase {
    @MainActor
    func testNewPlaylistRemoveControlRemovesOnlyOneRepeatedOccurrence() async throws {
        let app = AppModel.mock(.idle)
        let library = try XCTUnwrap(app.backends.library as? MockLibrary)
        let selected = try XCTUnwrap(library.mediaItem(id: "ml:wand-s01e05"))
        let filename = try XCTUnwrap(URL(string: selected.mrl)?.lastPathComponent)
        app.presentNewPlaylist(media: Array(repeating: selected, count: 4))
        _ = NSApplication.shared
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let size = NSSize(width: 713, height: 589)
        // AX traversal and press stay offscreen: do not register this XCTest process as an app.
        let host = NSHostingView(rootView: MXRNewPlaylistView().appModel(app))
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) { host.cacheDisplay(in: host.bounds, to: bitmap) }
        try await Task.sleep(for: .milliseconds(150))

        // SwiftUI AX nodes expose Objective-C selectors without conforming to the NSAccessibility protocol.
        func value(_ object: NSObject, _ method: String) -> Any? {
            let selector = NSSelectorFromString(method)
            guard object.responds(to: selector) else { return nil }
            return object.perform(selector)?.takeUnretainedValue()
        }
        func elements(_ object: Any) -> [NSObject] {
            guard let node = object as? NSObject else { return [] }
            return [node] + ((value(node, "accessibilityChildren") as? [Any]) ?? []).flatMap(elements)
        }
        func removeControls() -> [NSObject] {
            elements(host).filter {
                let label = (value($0, "accessibilityLabel") as? String) ?? (value($0, "accessibilityTitle") as? String)
                return value($0, "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue && label == "Remove \(filename)"
            }
        }
        let controls = removeControls()
        XCTAssertEqual(controls.count, 4)
        let first = try XCTUnwrap(controls.first)
        let selector = NSSelectorFromString("accessibilityPerformPress")
        XCTAssertTrue(first.responds(to: selector))
        typealias Press = @convention(c) (AnyObject, Selector) -> Bool
        let press = unsafeBitCast(first.method(for: selector), to: Press.self)
        XCTAssertTrue(press(first, selector))
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(removeControls().count, 3, "One actual Remove press must preserve the other three copies.")
    }

    func testNetworkInputKeepsAllURLsAndRejectsRelativePaths() throws {
        let urls = try DialogInput.networkURLs("  https://example.com/tv.m3u\n\nrtsp://example.com/live  ")
        XCTAssertEqual(urls.map(\.absoluteString), ["https://example.com/tv.m3u", "rtsp://example.com/live"])
        XCTAssertThrowsError(try DialogInput.networkURLs("https://example.com/live\nrelative/path"))
        XCTAssertThrowsError(try DialogInput.networkURLs("file:///tmp/movie.mp4"))
    }

    func testWildcardUDPAndRTPListenersRequireExplicitValidBindPort() throws {
        XCTAssertEqual(try DialogInput.networkURLs("udp://@:1234\nrtp://@:5004").map(\.absoluteString),
                       ["udp://@:1234", "rtp://@:5004"])
        for invalid in ["http://@:1234", "udp://@", "udp://@:0", "rtp://@:65536", "udp://:1234"] {
            XCTAssertThrowsError(try DialogInput.networkURLs(invalid), invalid)
        }
    }

    func testSubtitleLinkRequiresRemoteSubtitleFile() throws {
        XCTAssertEqual(try DialogInput.subtitleURL(" https://example.com/E01.en.srt ").pathExtension, "srt")
        XCTAssertThrowsError(try DialogInput.subtitleURL("https://example.com/archive.zip"))
        XCTAssertThrowsError(try DialogInput.subtitleURL("/tmp/subtitle.srt"))
    }

    @MainActor
    func testFolderImportMatchesEpisodesAndLeavesUnmatchedVideoEmpty() {
        let videos = ["Show_S01E01.mp4", "Show_S01E02.mp4", "Show_S01E03.mp4"].map { MediaItem(url: URL(fileURLWithPath: "/tmp/" + $0)) }
        let subtitles = ["Show.1x02.en.srt", "Show_S01E01.srt"].map { URL(fileURLWithPath: "/tmp/" + $0) }
        let draft = SubtitleImportDraft(scope: .folder, source: .computer, media: videos, subtitles: subtitles)
        XCTAssertEqual(draft.assignments[videos[0].id]?.lastPathComponent, "Show_S01E01.srt")
        XCTAssertEqual(draft.assignments[videos[1].id]?.lastPathComponent, "Show.1x02.en.srt")
        XCTAssertNil(draft.assignments[videos[2].id])
        XCTAssertTrue(draft.canSave)
    }

    @MainActor
    func testSingleFileImportAddsSelectedTracksToCurrentPlayer() async throws {
        let app = AppModel.mock(.playingEpisode)
        let media = try XCTUnwrap(app.player.media)
        let urls = ["English", "Spanish"].map { URL(fileURLWithPath: "/tmp/The_Wand_S01E04_\($0).srt") }
        let draft = SubtitleImportDraft(scope: .file, source: .computer, media: [media], subtitles: urls)
        draft.selected = Set(urls)
        try await draft.save(to: app)
        XCTAssertTrue(urls.allSatisfy { url in app.tracks.externalTracks(of: .subtitle).contains { $0.sourceURL == url } })
    }

    @MainActor
    func testLibrarySubtitleImportLoadsTrackForPlayingURIWithDifferentLibraryID() async throws {
        let mock = MockBackend(scenario: .idle)
        let playing = MediaItem(url: URL(fileURLWithPath: "/tmp/Playing.mp4"))
        mock.player.load(playing)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        var selected = playing
        selected.id = "ml:41"
        app.presentAddSubtitles(media: [selected])
        let draft = SubtitleImportDraft(scope: .file, source: .computer)
        await draft.loadTargets(from: app)
        let subtitle = URL(fileURLWithPath: "/tmp/Playing.en.srt")
        draft.importFiles([subtitle])
        var attached: [String] = []
        mock.library.addListener(self) { event in
            if case .mediaUpdated(let ids) = event { attached += ids }
        }
        try await draft.save(to: app)
        XCTAssertEqual(attached, ["ml:41"])
        XCTAssertEqual(app.player.media?.id, playing.mrl)
        XCTAssertTrue(app.tracks.externalTracks(of: .subtitle).contains { $0.sourceURL == subtitle })
    }

    @MainActor
    func testLibrarySubtitleImportRecognizesStandardizedAndSymlinkFileURLs() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let originals = directory.appendingPathComponent("Originals")
        let alias = directory.appendingPathComponent("Alias")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = originals.appendingPathComponent("Episode.mp4")
        try Data().write(to: source)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: originals)
        let mock = MockBackend(scenario: .idle)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        let subtitle = directory.appendingPathComponent("Episode.en.srt")
        for location in [directory.appendingPathComponent("Originals/../Originals/Episode.mp4"), alias.appendingPathComponent("Episode.mp4")] {
            mock.player.load(MediaItem(url: source))
            var selected = MediaItem(url: location)
            selected.id = "ml:42"
            let draft = SubtitleImportDraft(scope: .file, source: .computer, media: [selected], subtitles: [subtitle])
            try await draft.save(to: app)
            XCTAssertTrue(app.tracks.externalTracks(of: .subtitle).contains { $0.sourceURL == subtitle }, location.absoluteString)
        }
    }

    @MainActor
    func testLibrarySubtitleImportDoesNotLoadTrackForDifferentFileWithSameName() async throws {
        let mock = MockBackend(scenario: .idle)
        mock.player.load(MediaItem(url: URL(fileURLWithPath: "/tmp/Playing/Episode.mp4")))
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        var selected = MediaItem(url: URL(fileURLWithPath: "/tmp/Selected/Episode.mp4"))
        selected.id = "ml:43"
        let subtitle = URL(fileURLWithPath: "/tmp/Selected/Episode.en.srt")
        let draft = SubtitleImportDraft(scope: .file, source: .computer, media: [selected], subtitles: [subtitle])
        try await draft.save(to: app)
        XCTAssertFalse(app.tracks.externalTracks(of: .subtitle).contains { $0.sourceURL == subtitle })
    }

    @MainActor
    func testLibrarySubtitleImportKeepsNetworkURLQueryAndPathIdentity() async throws {
        let source = "https://example.com/live/video?token=one"
        let mock = MockBackend(scenario: .idle)
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        let subtitle = URL(fileURLWithPath: "/tmp/Network.en.srt")
        for location in [source, "https://example.com/live/video?token=two", "https://example.com/other/../live/video?token=one"] {
            mock.player.load(MediaItem(id: source, mrl: source, title: "Live", kind: .stream))
            let selected = MediaItem(id: "ml:44", mrl: location, title: "Live", kind: .stream)
            let draft = SubtitleImportDraft(scope: .file, source: .computer, media: [selected], subtitles: [subtitle])
            try await draft.save(to: app)
            XCTAssertEqual(app.tracks.externalTracks(of: .subtitle).contains { $0.sourceURL == subtitle }, location == source)
        }
    }

    @MainActor
    func testSubtitleTargetsUseSelectedLibraryMediaWhilePlayerIsIdle() async {
        let app = AppModel.mock(.idle)
        let selected = MediaItem(url: URL(fileURLWithPath: "/tmp/Selected.mp4"))
        app.presentAddSubtitles(media: [selected])
        let draft = SubtitleImportDraft(scope: .file, source: .computer)
        await draft.loadTargets(from: app)
        XCTAssertEqual(draft.media.map(\.id), [selected.id])
        XCTAssertNil(draft.error)
    }

    @MainActor
    func testSwitchingFiveFolderTargetsToFileRemembersSubtitleForOnlySelectedFile() async throws {
        let app = AppModel.mock(.playingEpisode)
        let targets = (1...5).map { MediaItem(url: URL(fileURLWithPath: "/tmp/Selected_S01E0\($0).mp4")) }
        app.presentAddSubtitles(media: targets, scope: .folder)
        let draft = SubtitleImportDraft(scope: .folder, source: .computer)
        await draft.loadTargets(from: app)
        XCTAssertEqual(draft.media.count, 5)
        draft.scope = .file
        XCTAssertFalse(draft.canSave, "Changing scope must invalidate the previous target set synchronously.")
        await draft.loadTargets(from: app)
        let subtitle = URL(fileURLWithPath: "/tmp/Selected_S01E01.srt")
        draft.importFiles([subtitle])
        var attached: [String] = []
        app.backends.library.addListener(self) { event in
            if case .mediaUpdated(let ids) = event { attached += ids }
        }
        try await draft.save(to: app, rules: SubtitleFolderRulesStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        XCTAssertEqual(draft.media.map(\.id), [targets[0].id])
        XCTAssertEqual(attached, [], "Files outside the library are remembered by path, not attached in the media library")
        XCTAssertNotEqual(draft.media.first?.id, app.player.media?.id)
        draft.scope = .folder
        await draft.loadTargets(from: app)
        XCTAssertEqual(draft.media.map(\.id), targets.map(\.id))
    }

    @MainActor
    func testFileWithoutFolderOrPlaylistContextCannotReuseFileForBatchScopes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppModel.mock(.playingEpisode)
        let selected = MediaItem(url: directory.appendingPathComponent("Selected.mp4"))
        app.presentAddSubtitles(media: [selected], scope: .file)
        let draft = SubtitleImportDraft(scope: .file, source: .computer)
        await draft.loadTargets(from: app)
        draft.importFiles([URL(fileURLWithPath: "/tmp/Selected.srt")])
        XCTAssertTrue(draft.canSave)
        for scope in [AddSubtitlesScope.folder, .playlist] {
            draft.scope = scope
            await draft.loadTargets(from: app)
            XCTAssertTrue(draft.media.isEmpty)
            XCTAssertFalse(draft.canSave)
            XCTAssertNotNil(draft.error)
        }
    }

    @MainActor
    func testFileScopeExpandsKnownSelectedFolderInsteadOfPlayingMediaFolder() async throws {
        let app = AppModel.mock(.playingEpisode)
        let folder = LibraryLocation.folder("wand-s02")
        let expected = await app.library.allMedia(at: folder)
        let selected = try XCTUnwrap(expected.first)
        app.presentAddSubtitles(media: [selected], scope: .file)
        let draft = SubtitleImportDraft(scope: .file, source: .computer)
        await draft.loadTargets(from: app)
        draft.scope = .folder
        await draft.loadTargets(from: app)
        XCTAssertEqual(Set(draft.media.map(\.id)), Set(expected.map(\.id)))
        XCTAssertFalse(draft.media.contains { $0.id == app.player.media?.id })
    }

    @MainActor
    func testPlaylistScopeUsesCapturedPlaylistInsteadOfReusingSelectedFile() async throws {
        let app = AppModel.mock(.playingEpisode)
        let playlist = LibraryLocation.playlist("pl-anime-to-watch")
        let expected = await app.library.allMedia(at: playlist)
        let selected = try XCTUnwrap(expected.first)
        app.library.navigate(to: playlist)
        app.presentAddSubtitles(media: [selected], scope: .file)
        let draft = SubtitleImportDraft(scope: .file, source: .computer)
        await draft.loadTargets(from: app)
        app.library.navigate(to: .folder("wand-s02"))
        draft.scope = .playlist
        await draft.loadTargets(from: app)
        XCTAssertEqual(Set(draft.media.map(\.id)), Set(expected.map(\.id)))
        XCTAssertEqual(draft.media.count, 7)
    }

    /// SD-18: a file opened from Finder can add subtitles to its whole folder, and the choice comes
    /// back for episodes added later.
    @MainActor
    func testFolderScopeWorksForFinderFilesAndIsRememberedForNewEpisodes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let subtitlesFolder = directory.appendingPathComponent("Subs")
        try FileManager.default.createDirectory(at: subtitlesFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for episode in 1...2 { try Data().write(to: directory.appendingPathComponent("Show S01E0\(episode).mkv")) }
        let subtitles = (1...3).map { subtitlesFolder.appendingPathComponent("Show.S01E0\($0).English.srt") }
        for url in subtitles { try Data().write(to: url) }
        let mock = MockBackend(scenario: .idle)
        mock.player.load(MediaItem(url: directory.appendingPathComponent("Show S01E01.mkv")))
        let app = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        let draft = SubtitleImportDraft(scope: .folder, source: .computer)
        await draft.loadTargets(from: app)
        XCTAssertEqual(draft.media.map(\.fileName), ["Show S01E01.mkv", "Show S01E02.mkv"])
        XCTAssertNil(draft.error)
        draft.importFiles(Array(subtitles.prefix(2)))
        XCTAssertEqual(draft.assignments.count, 2)
        let store = SubtitleFolderRulesStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        try await draft.save(to: app, rules: store)
        XCTAssertTrue(app.tracks.externalTracks(of: .subtitle).contains { $0.sourceURL == subtitles[0] }, "The playing episode gets it now")
        // Episode 3 arrives later; its subtitle sits beside the others and is found by the remembered rule.
        let third = directory.appendingPathComponent("Show S01E03.mkv")
        try Data().write(to: third)
        XCTAssertEqual(store.rules.subtitle(for: third)?.lastPathComponent, subtitles[2].lastPathComponent)
        XCTAssertEqual(store.rules.subtitle(for: directory.appendingPathComponent("Show S01E02.mkv"))?.lastPathComponent,
                       subtitles[1].lastPathComponent)
    }

    /// SD-18: a library episode's subtitle is attached by the media library (a bridge slave), so the
    /// remembered rule must not load it a second time; a later non-library save takes it back.
    func testRememberedRuleSkipsVideosTheLibraryAttaches() {
        let video = URL(fileURLWithPath: "/Shows/Show S01E01.mkv")
        let subtitle = URL(fileURLWithPath: "/Subs/Show.S01E01.English.srt")
        var rules = SubtitleFolderRules()
        rules.remember([(video, subtitle)], forFolder: nil, inLibrary: [video])
        XCTAssertNil(rules.subtitle(for: video, fileExists: { _ in true }))
        rules.remember([(video, subtitle)], forFolder: nil)
        XCTAssertEqual(rules.subtitle(for: video, fileExists: { _ in true }), subtitle)
    }

    func testStreamDestinationsAreBuiltFromPlainFields() throws {
        XCTAssertEqual(try DialogInput.streamURL(kind: .http, host: "0.0.0.0", port: "8080", path: "live").absoluteString, "http://0.0.0.0:8080/live")
        XCTAssertEqual(try DialogInput.streamURL(kind: .udp, host: "239.255.0.1", port: "1234", path: "/ignored").absoluteString, "udp://239.255.0.1:1234")
        XCTAssertThrowsError(try DialogInput.streamURL(kind: .rtp, host: "", port: "5004"))
        XCTAssertThrowsError(try DialogInput.streamURL(kind: .http, host: "0.0.0.0", port: "70000"))
        XCTAssertEqual(try DialogInput.conversionDestination(URL(fileURLWithPath: "/tmp/a.m4a"), fileExtension: "m4a").pathExtension, "m4a")
        XCTAssertThrowsError(try DialogInput.conversionDestination(URL(fileURLWithPath: "/tmp/a.mp4"), fileExtension: "m4a"))
        XCTAssertEqual(OutputFormat.available(engine: [], mode: .stream).map(\.id), ["h264", "copy"])
    }

    func testDiscAndCaptureRequestsPreserveNativeMRLs() throws {
        XCTAssertEqual(try DialogInput.discURL(kind: .dvd, path: "/Volumes/My DVD").absoluteString, "dvd:///Volumes/My%20DVD")
        XCTAssertEqual(try DialogInput.captureURL(deviceID: " camera-id ").absoluteString, "avcapture://camera-id")
        XCTAssertThrowsError(try DialogInput.captureURL(deviceID: ""))
    }

    func testOutputDestinationsPreserveQuotedPathsAndValidateStreamEndpoint() throws {
        let destination = URL(fileURLWithPath: "/tmp/Someone's video.mp4")
        XCTAssertEqual(try DialogInput.conversionDestination(destination), destination)
        XCTAssertThrowsError(try DialogInput.conversionDestination(URL(fileURLWithPath: "/tmp/video.webm")))
        XCTAssertEqual(try DialogInput.streamURL("http://127.0.0.1:8080/live").absoluteString,
                       "http://127.0.0.1:8080/live")
        XCTAssertThrowsError(try DialogInput.streamURL("https://example.com/live"))
        XCTAssertThrowsError(try DialogInput.streamURL("http://127.0.0.1/live"))
    }
}
