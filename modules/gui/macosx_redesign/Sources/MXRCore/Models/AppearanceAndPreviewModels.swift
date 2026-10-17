import CoreGraphics
import Foundation
import Observation

/// App theme (Settings ▸ General "Theme", onboarding step 2).
public enum ThemePreference: String, Sendable, Codable, Hashable, CaseIterable {
    case dark, light, system

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// The 9 accent colors of Settings ▸ General and onboarding, in design order. The actual colors
/// are design tokens; raw values match `Theme.Accent` in MXRDesign (`Theme.Accent(rawValue: choice.rawValue)`).
public enum AccentChoice: String, Sendable, Codable, Hashable, CaseIterable {
    case orange, red, olive, green, teal, blue, purple, pink, gray
}

/// Theme and accent, stored in the app options `macosx-redesign-theme` / `macosx-redesign-accent`.
@MainActor
@Observable
public final class AppearanceModel {
    public static let themeOption = "macosx-redesign-theme"
    public static let accentOption = "macosx-redesign-accent"

    public private(set) var theme: ThemePreference = .dark
    public private(set) var accent: AccentChoice = .orange

    @ObservationIgnored private let settings: any SettingsBackend

    public init(settings: any SettingsBackend) {
        self.settings = settings
        settings.addListener(self) { [weak self] event in
            switch event {
            case .valueChanged(let name) where name == Self.themeOption || name == Self.accentOption: self?.reload()
            case .reloaded: self?.reload()
            default: break
            }
        }
        reload()
    }

    public func setTheme(_ theme: ThemePreference) {
        self.theme = theme
        settings.setValue(.string(theme.rawValue), for: Self.themeOption, apply: .live("instance"))
        settings.save()
    }

    public func setAccent(_ accent: AccentChoice) {
        self.accent = accent
        settings.setValue(.string(accent.rawValue), for: Self.accentOption, apply: .live("instance"))
        settings.save()
    }

    private func reload() {
        if let raw = settings.value(for: Self.themeOption)?.stringValue, let value = ThemePreference(rawValue: raw) { theme = value }
        if let raw = settings.value(for: Self.accentOption)?.stringValue, let value = AccentChoice(rawValue: raw) { accent = value }
    }
}


/// A thumbnail backend that can also decode the exact frame at a time (not only the nearest
/// keyframe). The VLC backend adopts it; others fall back to `seekPreview(for:at:maxPixelSize:)`.
@MainActor
public protocol ExactFrameThumbnailBackend: ThumbnailBackend {
    /// `exact`: decode up to the frame at `time` (slower) instead of the nearest keyframe.
    /// Cancelling the task cancels the engine request.
    func seekPreview(for media: MediaItem, at time: MediaTime, exact: Bool, maxPixelSize: CGSize) async -> CGImage?
}

/// An in-memory LRU of decoded frames, bounded by bytes. Keys include the media, the time, the
/// precision and the requested pixel size.
@MainActor
final class FrameCache {
    struct Key: Hashable {
        var mediaID: String
        var time: Int64
        var exact: Bool
        var width: Int
        var height: Int
    }
    private struct Entry { let image: CGImage; let cost: Int; var used: UInt64 }
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0
    private var total = 0
    let budget: Int

    init(budget: Int) { self.budget = budget }

    subscript(key: Key) -> CGImage? {
        guard var entry = entries[key] else { return nil }
        clock &+= 1
        entry.used = clock
        entries[key] = entry
        return entry.image
    }

    func insert(_ image: CGImage, for key: Key) {
        clock &+= 1
        let cost = max(1, image.bytesPerRow * image.height)
        if let old = entries.updateValue(Entry(image: image, cost: cost, used: clock), forKey: key) { total -= old.cost }
        total += cost
        while total > budget, entries.count > 1,
              let victim = entries.min(by: { $0.value.used < $1.value.used })?.key {
            total -= entries.removeValue(forKey: victim)?.cost ?? 0
        }
    }

    var count: Int { entries.count }
}

/// The seek-bar thumbnail preview (S03, D028): latest-wins throttled frame requests, cancellable
/// down to the engine, cached per (media, slot) in an LRU.
///
/// While the pointer moves, the keyframe nearest each quantized slot is requested; one request runs
/// at a time and only the newest target waits behind it, so the card keeps updating during a
/// continuous drag. When the pointer rests for ``debounce``, the exact frame under it replaces the
/// keyframe, so the image matches the time printed below it.
@MainActor
@Observable
public final class SeekPreviewModel {
    /// The time under the pointer (shown under the thumbnail), nil when not hovering.
    public private(set) var time: MediaTime?
    /// The newest frame for the pointer's neighbourhood, nil while nothing has loaded yet.
    public private(set) var image: CGImage?

    /// How long the pointer must rest before the exact frame under it is requested.
    @ObservationIgnored public var debounce: Duration = .milliseconds(150)
    /// Pixel size requested from the thumbnailer: 2× the 252×142 pt image well (2151:9674).
    @ObservationIgnored public var maxPixelSize = CGSize(width: 504, height: 284)
    /// A running request older than this is replaced by the newest target instead of waited for.
    @ObservationIgnored public var staleAfter: Duration = .milliseconds(400)

    @ObservationIgnored private let thumbnails: any ThumbnailBackend
    @ObservationIgnored private let player: any PlayerBackend
    @ObservationIgnored let cache = FrameCache(budget: 32 << 20)
    @ObservationIgnored private var desired: FrameCache.Key?
    @ObservationIgnored private var shown: FrameCache.Key?
    @ObservationIgnored private var inFlight: InFlight?
    @ObservationIgnored private var pending: (key: FrameCache.Key, media: MediaItem)?
    @ObservationIgnored private var restTask: Task<Void, Never>?
    @ObservationIgnored private var nextRequestID = 0

    private struct InFlight {
        let id: Int
        let key: FrameCache.Key
        let task: Task<Void, Never>
        let started: ContinuousClock.Instant
    }

    public init(thumbnails: any ThumbnailBackend, player: any PlayerBackend) {
        self.thumbnails = thumbnails
        self.player = player
        player.addListener(self) { [weak self] event in
            if event == .media { self?.end() }
        }
    }

    /// Call while hovering or dragging over the seek bar.
    public func hover(at time: MediaTime) {
        self.time = time
        guard let media = player.currentMedia, media.kind != .stream, player.capabilities.contains(.seek) else {
            end()
            return
        }
        let quantum = Self.quantum(for: media.duration)
        let slot = time.microseconds / quantum.microseconds * quantum.microseconds
        let key = key(media, MediaTime(microseconds: slot), exact: false)
        if key != desired {
            desired = key
            // An exact frame in the same slot is closer than the slot's keyframe: keep it until
            // the resting pointer refines it again.
            let exactInSlot = shown.map { $0.exact && $0.mediaID == media.id
                && $0.time / quantum.microseconds * quantum.microseconds == slot } ?? false
            if !exactInSlot {
                if let cached = cache[key] { show(key, cached) } else { request(key, media: media) }
            }
        }
        scheduleExactFrame(media: media, time: time)
    }

    /// Call when the pointer leaves the bar.
    public func end() {
        restTask?.cancel()
        restTask = nil
        inFlight?.task.cancel()
        inFlight = nil
        pending = nil
        desired = nil
        shown = nil
        time = nil
        image = nil
    }

    /// Quantization step: `max(2 s, length / 300)`.
    public static func quantum(for length: MediaTime?) -> MediaTime {
        let minimum = MediaTime.seconds(2)
        guard let length, length > .zero else { return minimum }
        return max(minimum, MediaTime(microseconds: length.microseconds / 300))
    }

    /// Exact-frame requests are rounded to this step so a resting pointer reuses cached frames.
    static let exactStep = MediaTime.seconds(0.1)

    private func key(_ media: MediaItem, _ time: MediaTime, exact: Bool) -> FrameCache.Key {
        FrameCache.Key(mediaID: media.id, time: time.microseconds, exact: exact,
                       width: Int(maxPixelSize.width), height: Int(maxPixelSize.height))
    }

    private func scheduleExactFrame(media: MediaItem, time: MediaTime) {
        restTask?.cancel()
        guard thumbnails is any ExactFrameThumbnailBackend else { return }
        let delay = debounce
        restTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.time == time else { return }
            let step = Self.exactStep.microseconds
            let exact = self.key(media, MediaTime(microseconds: (time.microseconds + step / 2) / step * step), exact: true)
            self.desired = exact
            if let cached = self.cache[exact] { self.show(exact, cached) } else { self.request(exact, media: media) }
        }
    }

    /// Latest wins: one request runs at a time; a newer target waits (replacing any older waiting
    /// target), unless the running request is an exact frame or is taking too long, in which case
    /// it is cancelled (`vlc_preparser_Cancel`) and the newest target starts at once.
    private func request(_ key: FrameCache.Key, media: MediaItem) {
        if inFlight?.key == key { pending = nil; return }
        if let running = inFlight {
            if running.key.exact || ContinuousClock.now - running.started > staleAfter {
                running.task.cancel()
                inFlight = nil
            } else {
                pending = (key, media)
                return
            }
        }
        start(key, media: media)
    }

    private func start(_ key: FrameCache.Key, media: MediaItem) {
        nextRequestID += 1
        let id = nextRequestID
        let thumbnails = self.thumbnails
        let size = CGSize(width: key.width, height: key.height)
        let time = MediaTime(microseconds: key.time)
        let task = Task { @MainActor [weak self] in
            let frame: CGImage?
            if key.exact, let exact = thumbnails as? any ExactFrameThumbnailBackend {
                frame = await exact.seekPreview(for: media, at: time, exact: true, maxPixelSize: size)
            } else {
                frame = await thumbnails.seekPreview(for: media, at: time, maxPixelSize: size)
            }
            guard let self, self.inFlight?.id == id else { return }
            self.inFlight = nil
            if let frame, !Task.isCancelled {
                self.cache.insert(frame, for: key)
                // Show the wanted frame, or any newer frame while the wanted one is still missing.
                if key == self.desired || self.shown != self.desired, self.player.currentMedia?.id == media.id,
                   self.time != nil {
                    self.show(key, frame)
                }
            }
            if let next = self.pending {
                self.pending = nil
                if let cached = self.cache[next.key] {
                    if next.key == self.desired { self.show(next.key, cached) }
                } else {
                    self.request(next.key, media: next.media)
                }
            }
        }
        inFlight = InFlight(id: id, key: key, task: task, started: .now)
    }

    private func show(_ key: FrameCache.Key, _ frame: CGImage) {
        shown = key
        image = frame
    }
}

/// D031 mitigation: with the stock engine, a seek while paused leaves the previous picture on
/// screen until playback resumes. While paused, a seek therefore shows the exact frame at the new
/// time as a still over the video, until the next real frame arrives (playback resumes, or the
/// engine reports a newly displayed picture), the media changes or another seek replaces it.
@MainActor
@Observable
public final class PausedSeekFrameModel {
    /// The still to draw over the video (aspect-fit), nil when the video itself is current.
    public private(set) var image: CGImage?
    /// The media time of ``image``.
    public private(set) var time: MediaTime?

    /// Pixel size requested for the still; set it from the video view's backing size.
    @ObservationIgnored public var maxPixelSize = CGSize(width: 1920, height: 1080)
    /// Settling time after the last paused seek before the frame is requested (key repeat).
    @ObservationIgnored public var settleDelay: Duration = .milliseconds(80)
    /// After playback resumes, the still stays this long so real frames are already flowing.
    @ObservationIgnored public var resumeGrace: Duration = .milliseconds(250)

    @ObservationIgnored private let thumbnails: any ThumbnailBackend
    @ObservationIgnored private let player: PlayerModel
    @ObservationIgnored private let clock: PlaybackClock
    @ObservationIgnored private var mediaID: String?
    /// The time the screen correctly shows while paused (engine frame or our still).
    @ObservationIgnored private var shownTime: MediaTime?
    @ObservationIgnored private var requestedTime: MediaTime?
    @ObservationIgnored private var displayedPictures: Int?
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    /// A paused time change larger than this is a seek (frame stepping stays below it).
    static let seekThreshold = MediaTime.seconds(0.25)

    public init(thumbnails: any ThumbnailBackend, player: PlayerModel, clock: PlaybackClock) {
        self.thumbnails = thumbnails
        self.player = player
        self.clock = clock
        observe()
    }

    /// Hides the still and stops requesting (view went away).
    public func invalidate() {
        requestTask?.cancel()
        hideTask?.cancel()
        clear()
    }

    private func observe() {
        withObservationTracking { [weak self] in
            self?.evaluate()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
    }

    private func evaluate() {
        let running = clock.isRunning
        _ = clock.revision
        let scrubbing = clock.scrubTime != nil
        let pictures = player.statistics?.displayedPictures
        guard let media = player.media, media.kind == .video, player.canSeek,
              thumbnails is any ExactFrameThumbnailBackend else {
            mediaID = nil; shownTime = nil; clear(); return
        }
        if media.id != mediaID { mediaID = media.id; shownTime = nil; clear() }
        if running {
            shownTime = nil
            requestTask?.cancel(); requestTask = nil; requestedTime = nil
            if image != nil, hideTask == nil {
                let grace = resumeGrace
                hideTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: grace)
                    guard !Task.isCancelled, let self else { return }
                    self.hideTask = nil
                    if self.clock.isRunning { self.clear() }
                }
            }
            return
        }
        hideTask?.cancel(); hideTask = nil
        // The engine displayed a new picture at a new time (frame stepping): the video is current
        // again. Statistics lag the pause by up to a second, so an increase while the time still
        // equals the still's time is the picture shown before the pause, not a new one.
        if image != nil, let pictures, let before = displayedPictures, pictures > before,
           let stillTime = time, abs((clock.currentTime - stillTime).seconds) > 0.001 {
            displayedPictures = pictures
            clear()
            shownTime = clock.currentTime
            return
        }
        if image == nil { displayedPictures = pictures }
        guard !scrubbing else { return } // the seek preview card covers the drag
        let now = clock.currentTime
        guard let shown = shownTime else { shownTime = now; return } // just paused: the frame is right
        if abs((now - shown).seconds) <= Self.seekThreshold.seconds {
            if image == nil { shownTime = now } // frame stepping is displayed by the engine
            return
        }
        guard requestedTime != now else { return }
        request(at: now, media: media)
    }

    private func request(at time: MediaTime, media: MediaItem) {
        requestTask?.cancel()
        requestedTime = time
        let delay = settleDelay
        let size = maxPixelSize
        guard let exact = thumbnails as? any ExactFrameThumbnailBackend else { return }
        requestTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let frame = await exact.seekPreview(for: media, at: time, exact: true, maxPixelSize: size)
            guard !Task.isCancelled, let self, self.requestedTime == time, !self.clock.isRunning,
                  self.player.media?.id == media.id else { return }
            self.requestTask = nil
            if let frame {
                self.image = frame
                self.time = time
                self.shownTime = time
                self.displayedPictures = self.player.statistics?.displayedPictures
            }
        }
    }

    private func clear() {
        if image != nil { image = nil }
        if time != nil { time = nil }
        requestedTime = nil
    }
}
