import XCTest
@testable import MXRCore

final class MediaTimeTests: XCTestCase {
    func testFormats() {
        XCTAssertEqual(MediaTime.hms(0, 2, 10).formatted(.hoursMinutesSeconds), "00:02:10")
        XCTAssertEqual((-MediaTime.hms(0, 23, 30)).formatted(.hoursMinutesSeconds), "-00:23:30")
        XCTAssertEqual(MediaTime.hms(0, 0, 42, milliseconds: 23).formatted(.hoursMinutesSecondsMilliseconds), "00:00:42:023")
        XCTAssertEqual(MediaTime.hms(0, 23, 6).formatted(.compact), "23:06")
        XCTAssertEqual(MediaTime.hms(1, 2, 3).formatted(.compact), "1:02:03")
        XCTAssertEqual(MediaTime.hms(2, 3, 0).formatted(.summary), "2h 3m")
        XCTAssertEqual(MediaTime.hms(0, 47, 12).formatted(.summary), "47m")
        XCTAssertEqual(MediaTime.milliseconds(-2_000).formatted(.signedSeconds), "-2.000 s")
        XCTAssertEqual(MediaTime.zero.formatted(.signedSeconds), "0.000 s")
    }

    func testArithmeticAndLiterals() {
        let ten: MediaTime = 10
        XCTAssertEqual(ten.microseconds, 10_000_000)
        XCTAssertEqual((ten + .seconds(0.5)).milliseconds, 10_500)
        XCTAssertEqual((ten * 0.5).seconds, 5)
        XCTAssertEqual(MediaTime(.seconds(3)).seconds, 3)
        XCTAssertEqual(MediaTime.seconds(-4).magnitude.seconds, 4)
        XCTAssertEqual(MediaTime.seconds(12).clamped(to: .zero...ten), ten)
    }

    func testParsing() {
        XCTAssertEqual(MediaTime(parsing: "00:02:10"), .hms(0, 2, 10))
        XCTAssertEqual(MediaTime(parsing: "2:10"), .hms(0, 2, 10))
        XCTAssertEqual(MediaTime(parsing: "130"), .seconds(130))
        XCTAssertEqual(MediaTime(parsing: "1:00:00.5"), .seconds(3_600.5))
        XCTAssertNil(MediaTime(parsing: "abc"))
        XCTAssertNil(MediaTime(parsing: "1:2:3:4"))
        XCTAssertNil(MediaTime(parsing: ""))
    }
}

final class ValueTests: XCTestCase {
    func testKeyBindingRoundTrip() throws {
        let binding = try XCTUnwrap(KeyBinding(vlcString: "Command+Shift+r"))
        XCTAssertEqual(binding.key, "r")
        XCTAssertEqual(binding.modifiers, [.command, .shift])
        XCTAssertEqual(binding.vlcString, "Shift+Command+r")
        XCTAssertEqual(binding.displayString, "⇧⌘R")
        XCTAssertEqual(KeyBinding(vlcString: "Esc")?.displayString, "esc")
        XCTAssertEqual(KeyBinding(vlcString: "Command++")?.key, "+")
        XCTAssertEqual(KeyBinding(vlcString: "+")?.key, "+")
        XCTAssertNil(KeyBinding(vlcString: "Hyper+x"))
        XCTAssertNil(KeyBinding(vlcString: ""))
    }

    func testRGBColor() {
        let color = RGBColor(hex: "#B8B8B8")
        XCTAssertEqual(color?.vlcValue, 0xB8B8B8)
        XCTAssertEqual(RGBColor(vlcValue: 0x0C0C0C).hex, "#0C0C0C")
        XCTAssertNil(RGBColor(hex: "#12"))
    }

    func testMediaItemDerivedTitles() {
        var episode = MediaItem(id: "ml:1", mrl: "file:///a/The_Wand_S01E04.mp4", title: "The_Wand_S01E04.mp4", fileName: "The_Wand_S01E04.mp4",
                                kind: .video, duration: .hms(0, 25, 40), episode: EpisodeInfo(showName: "The Wand", season: 1, episode: 4))
        XCTAssertEqual(episode.displayTitle, "The Wand S01E04")
        XCTAssertEqual(episode.listTitle, "The_Wand_S01E04.mp4")
        XCTAssertEqual(episode.presetKey, "show:the wand")
        XCTAssertNil(episode.displayProgress)
        episode.progress = 0.5
        XCTAssertTrue(episode.isInProgress)
        XCTAssertEqual(episode.resumeTime, .hms(0, 12, 50))
        episode.playCount = 1
        XCTAssertFalse(episode.isInProgress)
        XCTAssertEqual(episode.displayProgress, 1)

        let song = MediaItem(id: "ml:2", mrl: "file:///untangle.mp3", title: "untangle", kind: .audio, artist: "juxtopposed")
        XCTAssertEqual(song.listTitle, "untangle - juxtopposed")
        XCTAssertEqual(MediaItem(url: URL(fileURLWithPath: "/tmp/x.flac")).kind, .audio)
        XCTAssertEqual(MediaItem(url: URL(string: "https://example.com/live.m3u8")!).kind, .stream)
    }

    func testSettingValueDecodingAndEquivalence() throws {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        let choices = try decoder.decode([SettingChoice].self, from: Data("[[0, 'Off'], [3, 'Title with extra characters'], ['dark', 'Dark'], [true, 'On']]".utf8))
        XCTAssertEqual(choices[0].value, .integer(0))
        XCTAssertEqual(choices[1].title, "Title with extra characters")
        XCTAssertEqual(choices[2].value, .string("dark"))
        XCTAssertEqual(choices[3].value, .bool(true))
        XCTAssertTrue(SettingValue.integer(1).isEquivalent(to: .bool(true)))
        XCTAssertTrue(SettingValue.float(2).isEquivalent(to: .integer(2)))
        XCTAssertFalse(SettingValue.string("a").isEquivalent(to: .string("b")))
    }

    func testRepeatCycleAndSorts() {
        XCTAssertEqual(RepeatMode.off.next, .all)
        XCTAssertEqual(RepeatMode.all.next, .one)
        XCTAssertEqual(RepeatMode.one.next, .off)
        XCTAssertEqual(LibrarySort.allCases.map(\.title).prefix(6), ["Unwatched First", "Watched First", "Newest First", "Oldest First", "Title A-Z", "Title Z-A"])
        XCTAssertFalse(LibrarySort.available(at: .songs).contains(.unwatchedFirst))
        XCTAssertEqual(EqualizerPreset.builtIn.count, 19)
        XCTAssertTrue(EqualizerPreset.builtIn.allSatisfy { $0.bands.count == 10 })
    }

    func testSubtitleMatcher() {
        let videos = (1...3).map { "The_Wand_S01E0\($0).mp4" }
        let subs = ["the.wand.s01e02.en.srt", "The_Wand_S01E01.srt", "Unrelated.srt", "The Wand 1x03.ass"]
        let result = SubtitleMatcher.match(videos: videos, subtitles: subs)
        XCTAssertEqual(result["The_Wand_S01E01.mp4"], "The_Wand_S01E01.srt")
        XCTAssertEqual(result["The_Wand_S01E02.mp4"], "the.wand.s01e02.en.srt")
        XCTAssertEqual(result["The_Wand_S01E03.mp4"], "The Wand 1x03.ass")
        XCTAssertEqual(SubtitleMatcher.language(in: "The_Wand_S01E01_Japanese.srt"), "Japanese")
        XCTAssertEqual(SubtitleMatcher.baseName("Movie_English.srt"), "Movie")
        let byName = SubtitleMatcher.match(videos: ["Paper Planes.mp4"], subtitles: ["Paper Planes.French.srt"])
        XCTAssertEqual(byName["Paper Planes.mp4"], "Paper Planes.French.srt")
    }

    @MainActor
    func testEventChannelDropsDeadOwners() {
        let channel = EventChannel<Int>()
        var received: [Int] = []
        var owner: NSObject? = NSObject()
        channel.add(owner!) { received.append($0) }
        channel.send(1)
        owner = nil
        channel.send(2)
        XCTAssertEqual(received, [1])
        XCTAssertEqual(channel.listenerCount, 0)
    }
}
