import MXRCore
import MXRDesign
import QuartzCore
import SwiftUI

/// Clipping in media time keeps cues stable when the subtitle delay or viewport changes.
enum SubtitleTimelineGeometry {
    static func fractions(cue: SubtitleCue, delay: MediaTime, start: MediaTime, duration: MediaTime) -> ClosedRange<Double>? {
        guard duration > .zero else { return nil }
        let lower = (cue.start + delay - start).seconds / duration.seconds
        let upper = (cue.end + delay - start).seconds / duration.seconds
        guard upper > 0, lower < 1, upper > lower else { return nil }
        return max(0, lower)...min(1, upper)
    }
}

/// The zoomed window shown by subtitle timeline mode (S21). It follows playback with the playhead
/// in the middle (frames 06m58.2 and 07m04.2, Figma 3744:12369) unless the user dragged or paged
/// it; the bar's time slots show its bounds with "*".
enum SubtitleTimelineWindow {
    static let duration: MediaTime = 50 // 3744:12370/12376: 01:50*–02:40*

    /// The window start that keeps `time` centred, clamped to the media.
    static func followStart(time: MediaTime, length: MediaTime) -> MediaTime {
        var start = max(.zero, time - duration * 0.5)
        if length > duration { start = min(start, length - duration) }
        return start
    }

    static func start(manual: MediaTime?, time: MediaTime, length: MediaTime) -> MediaTime {
        manual ?? followStart(time: time, length: length)
    }

    /// The latest start that still shows media.
    static func latestStart(length: MediaTime) -> MediaTime { max(.zero, length - duration) }
}

// Uncovered timeline metrics: 3750:12502 (18×24 arrow), 3750:12506 (22×24 nudge),
// 3744:12371 (1238×28 track), 3744:12370 (76×28 labels), 3749:12473 (cue radius 1),
// 5980:13201 / 3750:12509-12510 (4×12 chevrons and 10 pt crosses, 2 pt strokes).
private enum TimelineMetric {
    static let arrowWidth: CGFloat = 18
    static let nudgeWidth: CGFloat = 22
    static let cueRadius: CGFloat = 1
    static let chevronSize = CGSize(width: 4, height: 12)
    static let crossSize: CGFloat = 10
    static let glyphStroke: CGFloat = 2
    /// A paged or dragged window returns to following playback after this much playing time.
    static let resumeFollowDelay: Double = 5
    static let idlePollSeconds = 0.25
    /// Returning to the playhead glides instead of jumping (none under Reduce Motion).
    static let glideDuration: Double = 0.35
}

/// S21: a moving window of subtitle cues, with delayed cue times, seek dragging, 50 ms delay
/// nudges and viewport paging. In the player bar the time slots show the window bounds
/// (``MXRSubtitleTimelineRangeLabel``); the standalone view can draw them itself.
public struct MXRSubtitleTimelineView: View {
    public let showsRangeLabels: Bool
    @Environment(TracksModel.self) private var tracks
    @Environment(PlaybackClock.self) private var clock
    @Environment(PlayerModel.self) private var player
    @Environment(AppModel.self) private var app
    @Environment(InterfaceModel.self) private var ui
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragging = false
    @State private var scrub: ScrubSession?
    @State private var glide: Glide?
    public init(showsRangeLabels: Bool = true) { self.showsRangeLabels = showsRangeLabels }

    /// Whether the player bar shows the timeline instead of the seek bar.
    @MainActor public static func isActive(in app: AppModel) -> Bool {
        app.interface.showSubtitleTimeline && app.capabilities.supportsSubtitleTimeline
    }

    private struct Glide: Equatable {
        let from: MediaTime
        let began: CFTimeInterval
    }

    public var body: some View {
        HStack(spacing: Theme.Metric.ControlBar.seekGroup.gap) {
            if showsRangeLabels { MXRSubtitleTimelineRangeLabel(.start) }
            track
            if showsRangeLabels { MXRSubtitleTimelineRangeLabel(.end) }
        }
        .frame(height: Theme.Metric.ControlBar.seekTrack.height)
        .task(id: tracks.selectedTrack(of: .subtitle)?.id) { tracks.loadSubtitleCues() }
        .task(id: ui.subtitleTimelineWindowStart) { await resumeFollowingWhenIdle() }
        .task(id: glide) {
            guard glide != nil else { return }
            try? await Task.sleep(for: .seconds(TimelineMetric.glideDuration))
            if !Task.isCancelled { glide = nil }
        }
        .onChange(of: player.media?.id) { scrub?.cancel(); dragging = false; ui.subtitleTimelineWindowStart = nil; glide = nil }
        .onDisappear { scrub?.cancel(); dragging = false; ui.subtitleTimelineWindowStart = nil }
        .disabled(!app.capabilities.supportsSubtitleTimeline || !player.canSeek)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Subtitle timeline")
        .accessibilityValue("\(tracks.subtitleCues.count) subtitle cues, delay \(tracks.subtitleDelay.formatted(.signedSeconds))")
        .accessibilityAction(named: "Earlier subtitle window") { scroll(-1) }
        .accessibilityAction(named: "Later subtitle window") { scroll(1) }
        .accessibilityAction(named: "Follow the playhead") { resumeFollowing() }
    }

    private var track: some View {
        GeometryReader { geometry in
            let inset = PanelMetric.sliderInset
            let width = max(1, geometry.size.width - inset * 2)
            ZStack(alignment: .leading) {
                // Only the drawing below runs per frame: one Canvas, no per-cue views (ARC-08).
                TimelineView(.animation(paused: !isAnimating)) { _ in
                    let host = CACurrentMediaTime()
                    let time = clock.time(at: host)
                    let start = windowStart(time: time, host: host)
                    let cues = tracks.subtitleCues
                    let delay = tracks.subtitleDelay
                    Canvas(rendersAsynchronously: false) { context, size in
                        draw(in: &context, size: size, time: time, start: start, cues: cues, delay: delay)
                    }
                }
                HStack(spacing: Theme.Spacing.gap2) {
                    timelineButton(.earlier, title: "Earlier subtitle window", width: TimelineMetric.arrowWidth) { scroll(-1) }
                    timelineButton(.minus, title: "Subtitles 50 milliseconds earlier", width: TimelineMetric.nudgeWidth) { tracks.nudgeSubtitleDelay(steps: -1) }
                    Spacer(minLength: 0)
                    timelineButton(.plus, title: "Subtitles 50 milliseconds later", width: TimelineMetric.nudgeWidth) { tracks.nudgeSubtitleDelay(steps: 1) }
                    timelineButton(.later, title: "Later subtitle window", width: TimelineMetric.arrowWidth) { scroll(1) }
                }.padding(.leading, inset) // 3750:12503 ends at the track's right edge, unlike the 2 pt left inset.
            }
            .frame(height: Theme.Metric.ControlBar.seekTrack.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                guard isSeekArea(gesture.startLocation.x, totalWidth: geometry.size.width) else { return }
                if !dragging {
                    dragging = true
                    // Hold the window still while seeking moves the playhead under the pointer.
                    if ui.subtitleTimelineWindowStart == nil { ui.subtitleTimelineWindowStart = currentStart() }
                }
                session.update(to: seekTime(gesture.location.x, width: width))
            }.onEnded { gesture in
                guard isSeekArea(gesture.startLocation.x, totalWidth: geometry.size.width) else { return }
                session.end(at: seekTime(gesture.location.x, width: width))
                dragging = false
                resumeFollowing()
            })
        }.frame(height: Theme.Metric.ControlBar.seekTrack.height)
    }

    private var session: ScrubSession {
        if let scrub { return scrub }
        let player = player
        let created = ScrubSession(clock: clock) { time, precision in player.seek(to: time, precision: precision) }
        scrub = created
        return created
    }

    private var isAnimating: Bool {
        guard ui.areBarsVisible, !ui.isUIHidden, !player.isPictureInPicture else { return false }
        return clock.isRunning || glide != nil
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: MediaTime, start: MediaTime,
                      cues: [SubtitleCue], delay: MediaTime) {
        let duration = SubtitleTimelineWindow.duration
        let track = Theme.Metric.ControlBar.seekTrack
        let fill = Theme.Metric.ControlBar.seekFill
        let head = Theme.Metric.ControlBar.playhead
        let inset = PanelMetric.sliderInset
        let width = max(1, size.width - inset * 2)
        let fillY = (size.height - fill.height) / 2
        let position = (time - start).seconds / duration.seconds

        context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: track.radius ?? Theme.Radius.lg),
                     with: .style(Theme.Color.bgB2))
        let played = min(max(position, 0), 1)
        if played > 0 {
            context.fill(Path(roundedRect: CGRect(x: inset, y: fillY, width: played * width, height: fill.height),
                              cornerRadius: fill.radius ?? Theme.Radius.md),
                         with: .style(Theme.Color.bgAccentBright))
        }
        // White 14 % cues read orange-brown over the played fill and grey ahead of the playhead.
        for cue in cues {
            guard let span = SubtitleTimelineGeometry.fractions(cue: cue, delay: delay, start: start, duration: duration) else { continue }
            let rect = CGRect(x: inset + span.lowerBound * width, y: fillY,
                              width: (span.upperBound - span.lowerBound) * width, height: fill.height)
            context.fill(Path(roundedRect: rect, cornerRadius: TimelineMetric.cueRadius), with: .style(Theme.Color.subtitleCue))
        }
        // The playhead disappears while the user looks at another part of the media.
        if (0...1).contains(position) {
            let x = inset + position * max(0, width - head.width)
            context.fill(Path(roundedRect: CGRect(x: x, y: (size.height - head.height) / 2, width: head.width, height: head.height),
                              cornerRadius: head.radius ?? Theme.Radius.md),
                         with: .style(Theme.Color.accentMain))
        }
    }

    // MARK: Window

    private func windowStart(time: MediaTime, host: CFTimeInterval) -> MediaTime {
        if let manual = ui.subtitleTimelineWindowStart { return manual }
        let follow = SubtitleTimelineWindow.followStart(time: time, length: clock.length)
        guard let glide, !reduceMotion else { return follow }
        let progress = min(max((host - glide.began) / TimelineMetric.glideDuration, 0), 1)
        let eased = 1 - pow(1 - progress, 3)
        return glide.from + (follow - glide.from) * eased
    }

    private func currentStart() -> MediaTime {
        let host = CACurrentMediaTime()
        return windowStart(time: clock.time(at: host), host: host)
    }

    private func scroll(_ direction: Double) {
        let next = currentStart() + SubtitleTimelineWindow.duration * direction
        ui.subtitleTimelineWindowStart = next.clamped(to: .zero...SubtitleTimelineWindow.latestStart(length: clock.length))
    }

    /// Back to following playback, gliding from the window the user left.
    private func resumeFollowing() {
        guard let manual = ui.subtitleTimelineWindowStart else { return }
        glide = reduceMotion ? nil : Glide(from: manual, began: CACurrentMediaTime())
        ui.subtitleTimelineWindowStart = nil
    }

    /// A paged window follows playback again after a few seconds of playing without interaction,
    /// or as soon as the playhead runs out of the window it was in.
    private func resumeFollowingWhenIdle() async {
        guard let window = ui.subtitleTimelineWindowStart else { return }
        let end = window + SubtitleTimelineWindow.duration
        var wasInside = (window...end).contains(clock.currentTime)
        var idle = 0.0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(TimelineMetric.idlePollSeconds))
            guard !Task.isCancelled, !dragging else { continue }
            let time = clock.currentTime
            let inside = (window...end).contains(time)
            if wasInside && !inside && clock.isRunning { break }
            wasInside = wasInside || inside
            if clock.isRunning { idle += TimelineMetric.idlePollSeconds }
            if idle >= TimelineMetric.resumeFollowDelay { break }
        }
        if !Task.isCancelled { resumeFollowing() }
    }

    // MARK: Input

    private func isSeekArea(_ x: CGFloat, totalWidth: CGFloat) -> Bool {
        let safe = TimelineMetric.arrowWidth + TimelineMetric.nudgeWidth + PanelMetric.sliderInset * 2
        return x > safe && x < totalWidth - safe
    }

    private func seekTime(_ x: CGFloat, width: CGFloat) -> MediaTime {
        let fraction = min(max((x - PanelMetric.sliderInset) / width, 0), 1)
        let start = ui.subtitleTimelineWindowStart ?? currentStart()
        return (start + SubtitleTimelineWindow.duration * fraction).clamped(to: .zero...max(.zero, clock.length))
    }

    private func timelineButton(_ glyph: TimelineGlyph, title: String, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            glyph.stroke(Theme.Color.bgB2, style: StrokeStyle(lineWidth: TimelineMetric.glyphStroke, lineCap: .round, lineJoin: .round))
                .frame(width: width, height: Theme.Metric.ControlBar.seekFill.height)
                .background(Theme.Color.accentDim, in: .rect(cornerRadius: Theme.Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.md).inset(by: -Theme.Spacing.gap1)
                        .stroke(Theme.Color.bgB2, lineWidth: PanelMetric.controlBorder) // 3750:12502/12503/12506, 6101:13373: outside 2 pt stroke.
                }
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
}

/// The bold glyphs drawn on the orange timeline buttons (Figma vectors, not icon-set artwork).
private enum TimelineGlyph: Shape {
    case earlier, later, minus, plus

    func path(in rect: CGRect) -> Path {
        let chevron = TimelineMetric.chevronSize
        let half = TimelineMetric.crossSize / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        switch self {
        case .earlier, .later:
            let tip = self == .earlier ? -chevron.width / 2 : chevron.width / 2
            path.move(to: CGPoint(x: center.x - tip, y: center.y - chevron.height / 2))
            path.addLine(to: CGPoint(x: center.x + tip, y: center.y))
            path.addLine(to: CGPoint(x: center.x - tip, y: center.y + chevron.height / 2))
        case .minus, .plus:
            path.move(to: CGPoint(x: center.x - half, y: center.y))
            path.addLine(to: CGPoint(x: center.x + half, y: center.y))
            if self == .plus {
                path.move(to: CGPoint(x: center.x, y: center.y - half))
                path.addLine(to: CGPoint(x: center.x, y: center.y + half))
            }
        }
        return path
    }
}

/// The player bar's time slots in subtitle timeline mode: the window bounds marked "*"
/// (video 07m04.2 "00:06:00*" … "00:07:00*", Figma 3744:12370/12376). Clicking one brings a
/// paged window back to the playhead.
public struct MXRSubtitleTimelineRangeLabel: View {
    public enum Edge: Sendable { case start, end }
    private let edge: Edge
    @Environment(AppModel.self) private var app
    @State private var hovered = false
    public init(_ edge: Edge) { self.edge = edge }

    public var body: some View {
        let box = Theme.Metric.ControlBar.timeLabel
        let manual = app.interface.subtitleTimelineWindowStart
        let start = SubtitleTimelineWindow.start(manual: manual, time: app.clock.displayTime, length: app.clock.length)
        let time = edge == .start ? start : start + SubtitleTimelineWindow.duration
        let label = time.formatted(.hoursMinutesSeconds) + "*"
        Text(label).mxrTextStyle(Theme.Font.time)
            .fixedSize()
            .foregroundStyle(Theme.Color.fgA2)
            .frame(width: box.width, height: box.height)
            .background(Theme.Color.bgB2.opacity(hovered && manual != nil ? 1 : 0), in: .rect(cornerRadius: box.radius ?? Theme.Radius.lg))
            .contentShape(.rect)
            .onHover { hovered = $0 }
            .onTapGesture { app.interface.subtitleTimelineWindowStart = nil }
            .help(manual == nil ? "Subtitle timeline window" : "Click to show the playhead again")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(edge == .start ? "Subtitle window start" : "Subtitle window end")
            .accessibilityValue(label)
            .accessibilityAction(named: "Follow the playhead") { app.interface.subtitleTimelineWindowStart = nil }
    }
}
