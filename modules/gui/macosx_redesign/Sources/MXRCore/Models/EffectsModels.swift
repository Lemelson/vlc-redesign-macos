import Foundation
import Observation

/// The sidebar Video tab (S18): flip, rotate, zoom, HDR, aspect, crop, deinterlace and filter cards.
@MainActor
@Observable
public final class VideoEffectsModel {
    public private(set) var effects: VideoEffects = .default

    @ObservationIgnored public let backend: any PlayerBackend

    public init(backend: any PlayerBackend) {
        self.backend = backend
        effects = backend.videoEffects
        backend.addListener(self) { [weak self] event in
            guard let self, event == .videoEffects else { return }
            self.reload()
        }
    }

    /// Replaces all video effects, limited to what the engine accepts (``VideoEffects/sanitized``),
    /// so one unsupported legacy value cannot make the whole set fail to apply.
    public func set(_ effects: VideoEffects) {
        let effects = effects.sanitized
        guard effects != backend.videoEffects else { return }
        backend.setVideoEffects(effects)
        reload()
    }

    /// Edits in place: `video.update { $0.flip = .horizontal }`. Starts from the engine's value, so
    /// quick successive edits made before the change event arrives are not lost.
    public func update(_ change: (inout VideoEffects) -> Void) {
        var copy = backend.videoEffects
        change(&copy)
        set(copy)
    }

    private func reload() {
        if backend.videoEffects != effects { effects = backend.videoEffects }
    }

    /// Edits the Essential card. VLC's `adjust` filter is switched on exactly while the picture
    /// values differ from neutral (``EssentialVideoFilters/adjustsPicture``): the card has no enable
    /// switch (536:1860), and moving a slider back to neutral removes the filter again.
    public func updateEssential(_ change: (inout EssentialVideoFilters) -> Void) {
        update { effects in
            change(&effects.essential)
            effects.essential.isEnabled = effects.essential.adjustsPicture
        }
    }

    /// The Colors card's "Sepia Intensity" (673:1691) is its only sepia control: 0 while the sepia
    /// filter is off, otherwise VLC's `sepia-intensity`.
    public var sepiaIntensity: Int { effects.colors.sepia ? effects.colors.sepiaIntensity : 0 }

    /// Sets "Sepia Intensity": 0 removes the sepia filter, any other value applies it at that intensity.
    public func setSepiaIntensity(_ value: Int) {
        let value = min(max(value, 0), 255)
        update { effects in
            effects.colors.sepia = value > 0
            if value > 0 { effects.colors.sepiaIntensity = value }
        }
    }

    /// Restores every video effect to its default.
    public func reset() { set(.default) }

    /// True when anything differs from the defaults.
    public var isModified: Bool { effects != .default }
}

/// The sidebar Audio tab's effects (S19): stereo mode, equalizer, compressor, spatializer, widener, pitch.
@MainActor
@Observable
public final class AudioEffectsModel {
    public private(set) var effects: AudioEffects = .default
    public private(set) var isTestingOutput = false
    public private(set) var testOutputError: String?

    /// Presets for the Equalizer dropdown (with preview curves).
    @ObservationIgnored public let equalizerPresets: [EqualizerPreset] = EqualizerPreset.builtIn
    @ObservationIgnored public let backend: any PlayerBackend

    public init(backend: any PlayerBackend) {
        self.backend = backend
        effects = backend.audioEffects
        backend.addListener(self) { [weak self] event in
            guard let self, event == .audioEffects else { return }
            self.reload()
        }
    }

    public func set(_ effects: AudioEffects) {
        guard effects != backend.audioEffects else { return }
        backend.setAudioEffects(effects)
        reload()
    }

    /// Edits in place: `audio.update { $0.compressor.isEnabled = true }`. Starts from the engine's
    /// value, so dragging two equalizer bands before the first event arrives keeps both.
    public func update(_ change: (inout AudioEffects) -> Void) {
        var copy = backend.audioEffects
        change(&copy)
        set(copy)
    }

    private func reload() {
        if backend.audioEffects != effects { effects = backend.audioEffects }
    }

    /// The selected equalizer preset, nil when the bands were edited by hand.
    public var selectedEqualizerPreset: EqualizerPreset? {
        guard let id = effects.equalizer.presetID else { return nil }
        return equalizerPresets.first { $0.id == id }
    }

    /// Picks a preset: "None" disables the equalizer, any other enables it with the preset's values.
    public func applyEqualizerPreset(_ preset: EqualizerPreset) {
        update { effects in
            effects.equalizer.presetID = preset.id
            if preset.id == "none" {
                effects.equalizer.isEnabled = false
            } else {
                effects.equalizer.isEnabled = true
                effects.equalizer.preamp = preset.preamp
                effects.equalizer.bands = preset.bands
            }
        }
    }

    /// Moves one band slider (0...9); the preset becomes custom.
    public func setEqualizerBand(_ index: Int, gain: Double) {
        guard EqualizerSettings.bandFrequencies.indices.contains(index) else { return }
        update { effects in
            if effects.equalizer.bands.count < 10 { effects.equalizer.bands += Array(repeating: 0, count: 10 - effects.equalizer.bands.count) }
            effects.equalizer.bands[index] = min(max(gain, -20), 20)
            effects.equalizer.presetID = nil
            effects.equalizer.isEnabled = true
        }
    }

    public func setEqualizerPreamp(_ gain: Double) {
        update { effects in
            effects.equalizer.preamp = min(max(gain, -20), 20)
            effects.equalizer.isEnabled = true
        }
    }

    /// Serializes repeated clicks and keeps output-device failures local to the audio panel.
    public func testStereoOutput() async {
        guard !isTestingOutput else { return }
        isTestingOutput = true
        testOutputError = nil
        defer { isTestingOutput = false }
        do { try await backend.testStereoOutput() }
        catch { if !Task.isCancelled && !(error is CancellationError) { testOutputError = error.localizedDescription } }
    }

    public func reset() { set(.default) }
    public var isModified: Bool { effects != .default }
}

/// Titles and chapters of the current media: the Chapters tab (S24) and chapter navigation.
@MainActor
@Observable
public final class ChaptersModel {
    public private(set) var titles: [MediaTitle] = []
    public private(set) var selectedTitleIndex: Int?
    public private(set) var chapters: [Chapter] = []
    public private(set) var selectedChapterIndex: Int?
    public private(set) var programs: [MediaProgram] = []

    @ObservationIgnored public let backend: any PlayerBackend

    public init(backend: any PlayerBackend) {
        self.backend = backend
        backend.addListener(self) { [weak self] event in
            switch event {
            case .titles, .media: self?.reload()
            case .programs: self?.programs = self?.backend.programs ?? []
            default: break
            }
        }
        reload()
    }

    public var currentChapter: Chapter? {
        guard let selectedChapterIndex else { return nil }
        return chapters.first { $0.index == selectedChapterIndex }
    }

    /// Plays from the chapter's start.
    public func select(_ chapter: Chapter) { backend.selectChapter(index: chapter.index) }
    public func select(_ title: MediaTitle) { backend.selectTitle(index: title.index) }
    public func select(_ program: MediaProgram) { backend.selectProgram(id: program.id) }
    public func nextChapter() {
        guard let index = selectedChapterIndex, index + 1 < chapters.count else { return }
        backend.selectChapter(index: index + 1)
    }

    private func reload() {
        titles = backend.titles
        selectedTitleIndex = backend.selectedTitleIndex
        chapters = backend.chapters
        selectedChapterIndex = backend.selectedChapterIndex
        programs = backend.programs
    }
}

/// Bookmarks of the current media: the Bookmarks tab (S23) and ⌃B.
@MainActor
@Observable
public final class BookmarksModel {
    public private(set) var bookmarks: [Bookmark] = []
    public private(set) var isLoading = false

    @ObservationIgnored private let player: any PlayerBackend
    @ObservationIgnored private let library: any LibraryBackend
    @ObservationIgnored private let clock: PlaybackClock
    @ObservationIgnored private var mediaID: String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    public init(player: any PlayerBackend, library: any LibraryBackend, clock: PlaybackClock) {
        self.player = player
        self.library = library
        self.clock = clock
        player.addListener(self) { [weak self] event in
            if event == .media { self?.reload() }
        }
        library.addListener(self) { [weak self] event in
            if case .bookmarksChanged(let id) = event, id == self?.mediaID { self?.reload() }
        }
        reload()
    }

    /// "2 Bookmarks".
    public var summary: String { bookmarks.count == 1 ? "1 Bookmark" : "\(bookmarks.count) Bookmarks" }

    /// Adds a bookmark at the current time, named "<title> <n>" ("DON’T BLINK 1").
    public func addAtCurrentTime() {
        guard let media = player.currentMedia else { return }
        let time = clock.currentTime
        let name = "\(media.displayTitle) \(bookmarks.count + 1)"
        let library = self.library
        Task { @MainActor [weak self] in
            _ = try? await library.addBookmark(mediaID: media.id, time: time, name: name)
            self?.reload()
        }
    }

    /// Seeks to the bookmark.
    public func jump(to bookmark: Bookmark) { player.seek(to: bookmark.time, precision: .precise) }

    public func rename(_ bookmark: Bookmark, to name: String) {
        let library = self.library
        Task { @MainActor [weak self] in
            try? await library.renameBookmark(id: bookmark.id, mediaID: bookmark.mediaID, name: name)
            self?.reload()
        }
    }

    public func remove(_ bookmark: Bookmark) {
        let library = self.library
        Task { @MainActor [weak self] in
            try? await library.removeBookmark(id: bookmark.id, mediaID: bookmark.mediaID)
            self?.reload()
        }
    }

    /// Reloads the list for the current media.
    public func reload() {
        loadTask?.cancel()
        mediaID = player.currentMedia?.id
        guard let mediaID else {
            bookmarks = []
            return
        }
        if let cached = library.cachedBookmarks(mediaID: mediaID) {
            bookmarks = cached.sorted { $0.time < $1.time }
            isLoading = false
            return
        }
        isLoading = true
        let library = self.library
        loadTask = Task { @MainActor [weak self] in
            let list = await library.bookmarks(mediaID: mediaID)
            guard !Task.isCancelled, let self, self.mediaID == mediaID else { return }
            self.bookmarks = list.sorted { $0.time < $1.time }
            self.isLoading = false
        }
    }
}
