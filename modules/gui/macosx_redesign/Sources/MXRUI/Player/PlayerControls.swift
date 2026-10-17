import AppKit
import MXRCore
import MXRDesign
import QuartzCore
import SwiftUI

public struct MXRPlayerIconButton: View {
    let icon: MXRIcon.Name
    let title: String
    let active: Bool
    let highlightsActive: Bool
    let box: Theme.Box
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    /// Customize tiles draw the enabled default state (Player - customize shows nothing dimmed).
    @Environment(\.mxrLayoutEditing) private var editing

    public init(_ icon: MXRIcon.Name, title: String, active: Bool = false, highlightsActive: Bool = true,
                box: Theme.Box = Theme.Metric.ControlBar.iconButton, action: @escaping () -> Void) {
        self.icon = icon; self.title = title; self.active = active; self.highlightsActive = highlightsActive
        self.box = box; self.action = action
    }

    public var body: some View {
        Group {
            if editing {
                // A Customize tile is not a control: no Button, so a disabled command is not dimmed.
                label
            } else {
                Button(action: action) { label }
                    .buttonStyle(MXRBarButtonStyle())
                    .opacity(enabled ? 1 : Theme.Metric.ControlBar.iconButtonDisabledOpacity)
            }
        }
        .onHover { hovered = $0 }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var label: some View {
        MXRPlayerIconTile(icon: icon, active: active && highlightsActive, hovered: hovered && !editing, box: box)
    }
}

/// Bar buttons draw their label exactly: no press highlight (Figma and the video define none, D028)
/// and no system dimming when disabled, so an unavailable control is drawn at Figma's 30 %
/// (`iconButtonDisabledOpacity`) and not at that times the plain style's own dimming.
struct MXRBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// Figma Icon Wrapper 177:99: hover adds only the white 6 % radius-4 tile (`iconHover`); the glyph
/// keeps FG/A2 in every state except active.
struct MXRPlayerIconTile: View {
    let icon: MXRIcon.Name
    let active: Bool
    let hovered: Bool
    let box: Theme.Box

    var body: some View {
        MXRIcon(icon, state: active ? .active : .default, tint: Theme.Color.fgA2)
            .frame(width: box.width, height: box.height)
            .background(Theme.Color.iconHover.opacity(hovered ? 1 : 0),
                        in: .rect(cornerRadius: box.radius ?? Theme.Radius.md))
            .contentShape(.rect)
    }
}

public struct MXRPlayPauseButton: View {
    @Environment(AppModel.self) private var app
    @Environment(\.mxrLayoutEditing) private var editing
    @State private var hovered = false
    public init() {}

    public var body: some View {
        let playing = app.player.isPlaying
        Button { app.playOrOpenLibrary() } label: {
            MXRPlayPauseTile(playing: playing, hovered: hovered && !editing, editing: editing)
        }
        .buttonStyle(MXRBarButtonStyle())
        .onHover { hovered = $0 }
        .help(playing ? "Pause" : "Play")
        .accessibilityLabel(playing ? "Pause" : "Play")
    }
}

/// The play/pause tile (848:1711 / 848:1713). Figma draws no hover for it; the bar's hover rule
/// (Icon Wrapper 177:99, D048) applies to both states: the `iconHover` tile over the fill, so Play
/// stays Accent/Main under the pointer (a ~6 % change, spec-part1 §0 "about 8 %") and Pause reacts too.
struct MXRPlayPauseTile: View {
    let playing: Bool
    let hovered: Bool
    let editing: Bool

    var body: some View {
        let box = playing ? Theme.Metric.ControlBar.pauseButton : Theme.Metric.ControlBar.playButton
        let shape = RoundedRectangle(cornerRadius: box.radius ?? Theme.Radius.lg)
        Group {
            if playing {
                // 848:1713 overrides Vector17 to BG/B1, while Vector16 remains FG/B1.
                ZStack {
                    MXRIcon(.pause, tint: Theme.Color.fgB1)
                    MXRIcon(.pause, tint: Theme.Color.bgB1)
                        .mask(alignment: .leading) { Rectangle().frame(width: Theme.Metric.iconSize / 2) }
                }
            } else { MXRIcon(.play, tint: Theme.Color.fgB1) }
        }
            .padding(box.padding)
            // Customize edit mode (2115:7369): the fill is 48 pt, 3 pt inside the 54 pt tile box.
            .frame(width: box.width - (editing ? 2 * Theme.Metric.Customization.outlinePlayFillInset : 0),
                   height: box.height)
            .background {
                ZStack {
                    shape.fill(playing ? AnyShapeStyle(PauseButtonFill()) : AnyShapeStyle(Theme.Color.accentMain))
                    shape.fill(Theme.Color.iconHover).opacity(hovered ? 1 : 0)
                }
            }
            .frame(width: box.width)
    }
}

/// The pause button's FG/A3 surface (848:1713). Increase Contrast lifts FG/A3 *text* to FG/A1
/// (D046); this is a surface under the two-tone FG/B1 · BG/B1 glyph, so it keeps the Figma value:
/// in light mode the lifted #3C3C3C would leave the FG/B1 half at about 1.6:1 (B-11).
struct PauseButtonFill: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> SwiftUI.Color {
        Self.value(scheme: environment.colorScheme, accent: environment.mxrAccent).color
    }
    static func value(scheme: ColorScheme, accent: Theme.Accent = .orange) -> Theme.RGBA {
        Theme.Color.fgA3.value(scheme: scheme, accent: accent, contrast: .standard)
    }
}

public struct MXRTimeLabel: View {
    public enum Kind: Sendable { case current, duration }
    let kind: Kind
    @Environment(AppModel.self) private var app
    @State private var hovered = false
    @State private var editing = false
    @State private var input = ""
    @State private var invalid = false
    @FocusState private var focused: Bool
    public init(_ kind: Kind = .current) { self.kind = kind }
    /// The duration of media without a known length (live streams), as VLC's "--:--".
    static let unknownLength = "--:--:--"

    private var remaining: Bool { kind == .duration && app.interface.timeDisplay == .remaining }
    /// The elapsed label reads the clock, which follows the pointer while scrubbing (D028).
    private var label: String {
        if kind == .current { return app.clock.displayTime.formatted(.hoursMinutesSeconds) }
        return Self.durationText(length: app.clock.length, remaining: remaining ? app.clock.displayRemaining : nil)
    }

    /// The right label: the length, or `-remaining` when `remaining` is given. A live stream has no
    /// length: VLC shows dashes rather than a zero duration (D048).
    static func durationText(length: MediaTime, remaining: MediaTime?) -> String {
        guard length > .zero else { return unknownLength }
        if let remaining { return "-" + remaining.formatted(.hoursMinutesSeconds) }
        return length.formatted(.hoursMinutesSeconds)
    }

    public var body: some View {
        let box = Theme.Metric.ControlBar.timeLabel
        Group {
            if editing {
                TextField("HH:MM:SS", text: $input)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.time.font)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { editing = false; focused = false }
                    .onChange(of: focused) { _, newValue in if !newValue { editing = false } }
                    .accessibilityLabel(remaining ? "Seek by remaining time" : "Seek to time")
            } else {
                staticLabel(box: box)
            }
        }
        .foregroundStyle(invalid ? Theme.Color.accentMain : Theme.Color.fgA2)
        .frame(width: box.width, height: box.height)
        .background(Theme.Color.bgB2.opacity(hovered || editing ? 1 : 0),
                    in: .rect(cornerRadius: box.radius ?? Theme.Radius.lg))
        .contentShape(.rect)
        .onHover { hovered = $0 }
        .help(kind == .current ? "Click to enter a playback time"
                               : (remaining ? "Click to show the duration" : "Click to show the remaining time"))
        // A container named for the field; the value is the inner button's (or the text field's) only.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(kind == .current ? "Elapsed time" : (remaining ? "Remaining time" : "Duration"))
    }

    /// B-10: Figma 1904:7236 is Inter Regular 15 with proportional digits, centred in the fixed
    /// 76 × 28 box (D047). The whole box is the click target (B-06).
    private func staticLabel(box: Theme.Box) -> some View {
        let hint = kind == .current && !app.player.canSeek ? "Not available for this stream" : ""
        let title = kind == .current ? "Edit playback time" : "Toggle duration or remaining time"
        return Text(label).mxrTextStyle(Theme.Font.time).fixedSize()
            .frame(width: box.width, height: box.height)
            .contentShape(.rect)
            .onTapGesture(perform: activate)
            // No system focus ring; keyboard navigation draws the design ring (D028).
            .mxrKeyboardFocusable(cornerRadius: box.radius ?? Theme.Radius.lg)
            .onKeyPress(.space) { activate(); return .handled }
            .onKeyPress(.return) { activate(); return .handled }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title)
            .accessibilityValue(label == Self.unknownLength ? "Unknown" : label)
            .accessibilityHint(hint)
            .accessibilityAction { activate() }
    }

    private func activate() {
        if kind == .current { beginEditing() } else { app.interface.toggleTimeDisplay() }
    }

    private func beginEditing() {
        guard app.player.canSeek else { return }
        input = kind == .duration && !remaining ? app.clock.displayTime.formatted(.hoursMinutesSeconds) : label
        invalid = false; editing = true; focused = true
    }

    private func commit() {
        guard let time = PlayerGeometry.typedTime(input, length: app.clock.length, remaining: remaining) else {
            invalid = true; return
        }
        app.player.seek(to: time, precision: .precise)
        invalid = false; editing = false; focused = false
    }
}

/// S04's nonlinear cone: 100% fills 63 pt of the 88 pt cone, leaving boost travel on the right.
public struct MXRVolumeCone: View {
    @Environment(AppModel.self) private var app
    @State private var hovered = false
    @State private var dragging = false
    @Environment(\.isEnabled) private var enabled
    public init() {}

    public var body: some View {
        let box = Theme.Metric.Volume.cone
        let fillWidth = PlayerGeometry.volumeFillWidth(percent: app.player.isMuted ? 0 : Double(app.player.volumePercent),
                                                      maximumPercent: app.player.maximumVolume * 100)
        ZStack(alignment: .leading) {
            VolumeConeTrackShape().fill(Theme.Gradient.volumeConeTrack)
                .frame(width: MXRPlayerMetrics.coneTrackSize.width, height: MXRPlayerMetrics.coneTrackSize.height)
            VolumeConeGradient()
                .frame(width: MXRPlayerMetrics.coneFillSize.width, height: MXRPlayerMetrics.coneFillSize.height)
                .offset(x: MXRPlayerMetrics.coneInset)
                .mask(alignment: .leading) {
                    UnevenRoundedRectangle(topLeadingRadius: Theme.Stroke.hairline,
                                           bottomLeadingRadius: Theme.Stroke.hairline,
                                           bottomTrailingRadius: Theme.Radius.xs,
                                           topTrailingRadius: Theme.Radius.xs)
                        .frame(width: fillWidth, height: box.height + Theme.Spacing.gap2)
                }
        }
        // The 89 pt track starts at x=0 inside its 88 pt component (244:235/236).
        .frame(width: box.width, height: box.height, alignment: .leading)
        .contentShape(.rect)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in dragging = true; setVolume(at: value.location.x) }
            .onEnded { value in setVolume(at: value.location.x); dragging = false })
        .onHover { hovered = $0 }
        .overlay(alignment: .top) {
            if hovered || dragging {
                MXRVolumeTooltip()
                    .offset(y: -Theme.Metric.ControlBar.volumeTooltip.height - Theme.Spacing.gap8)
                    .allowsHitTesting(false)
            }
        }
        .mxrConeScroll(enabled: enabled && ConeScrollAvailability.isEnabled(in: app),
                       reversed: { [app] in ConeScrollAvailability.isReversed(in: app) },
                       adjust: { [app] in app.player.adjustVolume(steps: $0) })
        // No system focus ring after a click or drag (C1); keyboard navigation shows the design ring.
        .mxrKeyboardFocusable(cornerRadius: Theme.Radius.lg)
        .onKeyPress(.leftArrow) { app.player.adjustVolume(steps: -1); return .handled }
        .onKeyPress(.rightArrow) { app.player.adjustVolume(steps: 1); return .handled }
        .onKeyPress(.upArrow) { app.player.adjustVolume(steps: 1); return .handled }
        .onKeyPress(.downArrow) { app.player.adjustVolume(steps: -1); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(app.player.volumePercent) percent\(app.player.isMuted ? ", muted" : "")")
        .accessibilityRepresentation {
            Slider(value: Binding(get: { app.player.volume }, set: { app.player.setVolume($0) }), in: 0...app.player.maximumVolume)
                .accessibilityLabel("Volume")
                .accessibilityAdjustableAction { direction in app.player.adjustVolume(steps: direction == .increment ? 1 : -1) }
                .accessibilityValue("\(app.player.volumePercent) percent\(app.player.isMuted ? ", muted" : "")")
        }
    }

    private func setVolume(at x: CGFloat) {
        app.player.setVolume(PlayerGeometry.volumePercent(at: x, maximumPercent: app.player.maximumVolume * 100) / 100)
    }
}

/// Cubic paths from research/from-forks/volume-svg, normalized to the Figma vector bounds.
private struct VolumeConeTrackShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 3.59756, y: 19.0454))
        path.addCurve(to: CGPoint(x: 0, y: 15.0657), control1: CGPoint(x: 1.55468, y: 18.8388), control2: CGPoint(x: 0, y: 17.119))
        path.addLine(to: CGPoint(x: 0, y: 12.2975))
        path.addCurve(to: CGPoint(x: 3.59756, y: 8.31783), control1: CGPoint(x: 0, y: 10.2442), control2: CGPoint(x: 1.55467, y: 8.52441))
        path.addLine(to: CGPoint(x: 85.6982, y: 0.0155207))
        path.addCurve(to: CGPoint(x: 89, y: 3.0003), control1: CGPoint(x: 87.4654, y: -0.163183), control2: CGPoint(x: 89, y: 1.2241))
        path.addLine(to: CGPoint(x: 89, y: 24.363))
        path.addCurve(to: CGPoint(x: 85.6982, y: 27.3477), control1: CGPoint(x: 89, y: 26.1392), control2: CGPoint(x: 87.4654, y: 27.5264))
        path.addLine(to: CGPoint(x: 3.59756, y: 19.0454))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 89, y: rect.height / 27.3633))
    }
}

/// Core Graphics interpolates the Figma stops directly in sRGB, preserving the cone's colors.
struct VolumeConeGradient: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let overlay = Theme.Gradient.volumeConeOverlay.value(scheme: colorScheme).cgColor
        Canvas { context, size in
            context.withCGContext { cg in
                let rect = CGRect(origin: .zero, size: size)
                cg.addPath(VolumeConeFillShape().path(in: rect).cgPath)
                cg.clip()
                if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                             colors: Theme.Gradient.volumeCone.map { $0.color.cgColor } as CFArray,
                                             locations: Theme.Gradient.volumeCone.map { CGFloat($0.location) }) {
                    cg.drawLinearGradient(gradient,
                                          start: CGPoint(x: MXRPlayerMetrics.coneGradientStartX * size.width, y: size.height / 2),
                                          end: CGPoint(x: MXRPlayerMetrics.coneGradientEndX * size.width, y: size.height / 2),
                                          options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
                cg.setFillColor(overlay)
                cg.fill(rect)
            }
        }
    }
}

private struct VolumeConeFillShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 1.79183, y: 15.9675))
        path.addCurve(to: CGPoint(x: 0, y: 13.9783), control1: CGPoint(x: 0.773415, y: 15.8609), control2: CGPoint(x: 0, y: 15.0023))
        path.addLine(to: CGPoint(x: 0, y: 10.5816))
        path.addCurve(to: CGPoint(x: 1.79183, y: 8.59245), control1: CGPoint(x: 0, y: 9.55761), control2: CGPoint(x: 0.773416, y: 8.69903))
        path.addLine(to: CGPoint(x: 83.7918, y: 0.0110748))
        path.addCurve(to: CGPoint(x: 86, y: 2.00021), control1: CGPoint(x: 84.9723, y: -0.112463), control2: CGPoint(x: 86, y: 0.813294))
        path.addLine(to: CGPoint(x: 86, y: 22.5597))
        path.addCurve(to: CGPoint(x: 83.7918, y: 24.5489), control1: CGPoint(x: 86, y: 23.7467), control2: CGPoint(x: 84.9723, y: 24.6724))
        path.addLine(to: CGPoint(x: 1.79183, y: 15.9675))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 86, y: rect.height / 24.56))
    }
}

public struct MXRVolumeTooltip: View {
    @Environment(AppModel.self) private var app
    public init() {}
    public var body: some View {
        let box = Theme.Metric.ControlBar.volumeTooltip
        Text("\(app.player.volumePercent) %")
            .mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA2)
            .frame(width: box.width, height: box.height)
            .background { MXRBackdropSurface(tint: Theme.Color.bgB1Transparent, cornerRadius: box.radius ?? Theme.Radius.lg) }
            .modifier(PlayerOutsideShadow(radius: box.radius ?? Theme.Radius.lg))
            .accessibilityLabel("Volume")
            .accessibilityValue("\(app.player.volumePercent) percent")
    }
}

public struct MXRVolumeControl: View {
    @Environment(AppModel.self) private var app
    public init() {}
    public var body: some View {
        HStack(spacing: Theme.Metric.ControlBar.volumeGroup.gap) {
            MXRPlayerIconButton(.volumeHigh, title: app.player.isMuted ? "Unmute" : "Mute", active: app.player.isMuted,
                                box: Theme.Box(node: "491:1732", width: Theme.Metric.iconSize, height: Theme.Metric.iconSize)) {
                app.player.toggleMute()
            }
            MXRVolumeCone()
        }
        .frame(width: Theme.Metric.ControlBar.volumeGroup.width, height: Theme.Metric.ControlBar.volumeGroup.height)
    }
}

public struct MXRSeekPreview: View {
    @Environment(AppModel.self) private var app
    public init() {}
    public var body: some View {
        let box = Theme.Metric.ControlBar.seekThumbnail
        let imageBox = Theme.Metric.ControlBar.seekThumbnailImage
        VStack(spacing: box.gap) {
            ZStack {
                Rectangle().fill(Theme.Color.thumbPlaceholder)
                if let image = app.seekPreview.image {
                    // Fit, not fill: 2.39:1 films and 4:3 video keep their whole frame (CB-M3).
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                } else {
                    MXRIcon(.video, tint: Theme.Color.fgA3)
                }
            }
            .frame(width: imageBox.width, height: imageBox.height)
            .clipShape(.rect(cornerRadius: imageBox.radius ?? Theme.Radius.md))
            Text((app.seekPreview.time ?? .zero).formatted(.hoursMinutesSeconds))
                .mxrTextStyle(Theme.Font.time).monospacedDigit().foregroundStyle(Theme.Color.fgA2)
        }
        .padding(box.padding)
        .frame(width: box.width, height: box.height)
        .background { MXRBackdropSurface(tint: Theme.Color.bgA3Transparent, cornerRadius: box.radius ?? Theme.Radius.xxl) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seek preview")
        .accessibilityValue((app.seekPreview.time ?? .zero).formatted(.hoursMinutesSeconds))
    }
}

/// Hover feedback when no frame can be shown (music, streams, previews off): the time under the
/// pointer in the volume-value chip style (2245:9805), BB-17.
struct MXRSeekTimeChip: View {
    let time: MediaTime
    var body: some View {
        let box = Theme.Metric.ControlBar.volumeTooltip
        Text(time.formatted(.hoursMinutesSeconds))
            .mxrTextStyle(Theme.Font.body).monospacedDigit().foregroundStyle(Theme.Color.fgA2)
            .frame(width: box.width, height: box.height)
            .background { MXRBackdropSurface(tint: Theme.Color.bgB1Transparent, cornerRadius: box.radius ?? Theme.Radius.lg) }
            .modifier(PlayerOutsideShadow(radius: box.radius ?? Theme.Radius.lg))
            .accessibilityHidden(true)
    }
}

/// The seek bar (S02/S03, D028).
///
/// - Solid thick bar by default; the waveform (S34) only when "Show Waveform on Seekbar" is on, and
///   the audio is analysed only then.
/// - Scrubbing is a ``ScrubSession``: the playhead and elapsed label follow the pointer on every
///   event, engine seeks are coalesced, one precise seek lands on release.
/// - Only ``SeekProgressView`` (fill and head) redraws while playing; this body does not depend on
///   the playback time.
public struct MXRSeekBar: View {
    @Environment(AppModel.self) private var app
    @State private var hoverX: CGFloat?
    @State private var previewsAllowed = false
    @State private var scrub: ScrubSession?
    @State private var waveform: WaveformSamples?
    public init() {}

    /// Where the thumbnail card (2151:9673) sits, in the seek bar's coordinates. Video 03m29.3: the
    /// card is centred on the pointer and floats `gap5` above the control bar's top edge (18 pt above
    /// the track), so it never overlaps the bar. Near the window's sides it slides to stay inside the
    /// window (`window`: the window's horizontal extent in the bar's coordinates), keeping the
    /// framed video's side inset; without a window it stays over the bar.
    static func previewOrigin(pointerX: CGFloat, barWidth: CGFloat, window: ClosedRange<CGFloat>?) -> CGPoint {
        let card = Theme.Metric.ControlBar.seekThumbnail
        let barInset = (Theme.Metric.ControlBar.bar.height - Theme.Metric.ControlBar.seekTrack.height) / 2
        let margin = window == nil ? 0 : Theme.Metric.Window.videoArea.padding.leading
        let lower = (window?.lowerBound ?? 0) + margin
        let upper = max(lower, (window?.upperBound ?? barWidth) - margin - card.width)
        return CGPoint(x: min(max(pointerX - card.width / 2, lower), upper),
                       y: -(card.height + barInset + Theme.Spacing.gap5))
    }

    /// Reads settings (a bridge round trip): evaluate when hovering starts, not per pointer event.
    private var previewsEnabled: Bool {
        MXRPlayerPreferences(app: app).showsSeekThumbnails && app.capabilities.hasThumbnails && !app.player.isAudioOnly
    }

    public var body: some View {
        GeometryReader { geometry in
            let track = Theme.Metric.ControlBar.seekTrack
            let samples = app.interface.showWaveform ? waveform : nil
            let head = app.player.isAudioOnly || samples != nil ? MXRPlayerMetrics.musicPlayhead : Theme.Metric.ControlBar.playhead
            let width = max(0, geometry.size.width - SeekProgressView.inset * 2)
            let resume: Double? = app.player.restorePrompt.flatMap { prompt in
                app.clock.length > .zero ? min(max(prompt.time.seconds / app.clock.length.seconds, 0), 1) : nil
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: track.radius ?? Theme.Radius.lg).fill(Theme.Color.bgB2)
                SeekProgressView(width: width, head: head, samples: samples, resume: resume)
            }
            .clipShape(.rect(cornerRadius: track.radius ?? Theme.Radius.lg))
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    drag(to: value.location.x, width: geometry.size.width)
                    hover(at: value.location.x, width: geometry.size.width)
                }
                .onEnded { value in
                    release(at: value.location.x, width: geometry.size.width)
                    if !CGRect(origin: .zero, size: geometry.size).contains(value.location) { endHover() }
                })
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hover(at: point.x, width: geometry.size.width)
                case .ended: if scrub?.isActive != true { endHover() }
                }
            }
            .overlay(alignment: .topLeading) {
                if let hoverX, app.player.canSeek {
                    let x = min(max(hoverX, 0), geometry.size.width)
                    if previewsAllowed {
                        let window = geometry.bounds(of: .named(MXRAppView.coordinateSpace))
                        let origin = Self.previewOrigin(pointerX: x, barWidth: geometry.size.width,
                                                        window: window.map { $0.minX...$0.maxX })
                        MXRSeekPreview()
                            .offset(x: origin.x, y: origin.y)
                            .allowsHitTesting(false)
                    } else if app.clock.length > .zero {
                        let chip = Theme.Metric.ControlBar.volumeTooltip
                        MXRSeekTimeChip(time: app.clock.length * PlayerGeometry.seekPosition(x: x, width: geometry.size.width))
                            .offset(x: min(max(x - chip.width / 2, 0), max(0, geometry.size.width - chip.width)),
                                    y: -chip.height - Theme.Spacing.gap8)
                            .allowsHitTesting(false)
                    }
                }
            }
            .onChange(of: app.player.media?.id) { _, _ in
                scrub?.cancel(); endHover()
            }
            .onDisappear { scrub?.cancel(); app.seekPreview.end() }
        }
        .frame(minWidth: Theme.Metric.ControlBar.playButton.width, idealWidth: Theme.Metric.ControlBar.seekTrack.width,
               maxWidth: .infinity, minHeight: Theme.Metric.ControlBar.seekTrack.height,
               maxHeight: Theme.Metric.ControlBar.seekTrack.height)
        .disabled(!app.player.canSeek)
        .opacity(app.player.canSeek ? 1 : Theme.Metric.ControlBar.iconButtonDisabledOpacity)
        // No system focus ring after a click (C1); keyboard navigation shows the design ring.
        .mxrKeyboardFocusable(cornerRadius: Theme.Metric.ControlBar.seekTrack.radius ?? Theme.Radius.lg)
        .onKeyPress(.leftArrow) { app.player.jump(by: -10); return .handled }
        .onKeyPress(.rightArrow) { app.player.jump(by: 10); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(app.clock.displayTime.formatted(.hoursMinutesSeconds))
        .accessibilityRepresentation {
            Slider(value: Binding(get: { app.clock.currentPosition }, set: { app.player.seek(toPosition: $0, precision: .precise) }), in: 0...1)
                .accessibilityLabel("Playback position")
                .accessibilityAdjustableAction { direction in app.player.jump(by: direction == .increment ? 10 : -10) }
                .accessibilityValue(app.clock.displayTime.formatted(.hoursMinutesSeconds))
                .disabled(!app.player.canSeek)
        }
        // D028: the waveform is computed only when it will be drawn; cancelling the task (toggle
        // off, media change, bar gone) stops the analysis.
        .task(id: WaveformRequest(mediaID: app.player.media?.id, enabled: app.interface.showWaveform)) {
            waveform = nil
            guard app.interface.showWaveform, app.capabilities.supportsWaveform, let media = app.player.media else { return }
            let samples = await app.backends.thumbnails.waveform(for: media, bins: MXRPlayerMetrics.waveformBins)
            guard !Task.isCancelled, let samples, !samples.isEmpty else { return }
            waveform = WaveformSamples(samples)
        }
    }

    private struct WaveformRequest: Hashable { let mediaID: String?; let enabled: Bool }

    private func target(at x: CGFloat, width: CGFloat) -> MediaTime {
        app.clock.length * PlayerGeometry.seekPosition(x: x, width: width)
    }

    private func drag(to x: CGFloat, width: CGFloat) {
        guard app.player.canSeek, app.clock.length > .zero else { return }
        session.update(to: target(at: x, width: width))
    }

    private func release(at x: CGFloat, width: CGFloat) {
        guard app.player.canSeek else { scrub?.cancel(); return }
        guard app.clock.length > .zero else {
            app.player.seek(toPosition: PlayerGeometry.seekPosition(x: x, width: width), precision: .precise)
            return
        }
        session.end(at: target(at: x, width: width))
    }

    private var session: ScrubSession {
        if let scrub { return scrub }
        let player = app.player
        let created = ScrubSession(clock: app.clock) { time, precision in player.seek(to: time, precision: precision) }
        scrub = created
        return created
    }

    private func hover(at x: CGFloat, width: CGFloat) {
        guard app.player.canSeek else { endHover(); return }
        if hoverX == nil { previewsAllowed = previewsEnabled }
        hoverX = x
        if previewsAllowed { app.seekPreview.hover(at: target(at: x, width: width)) }
    }

    private func endHover() {
        hoverX = nil
        app.seekPreview.end()
    }
}

/// Waveform peaks, compared by identity so unchanged samples never re-path the waveform.
final class WaveformSamples: Equatable, @unchecked Sendable {
    let values: [Float]
    init(_ values: [Float]) { self.values = values }
    static func == (lhs: WaveformSamples, rhs: WaveformSamples) -> Bool { lhs === rhs }
}

/// The part of the seek bar that moves with time: resume span and marker (S12), the fill or the
/// played waveform, and the playhead. ``SeekProgressNSView`` observes the clock and moves its
/// layers itself, so neither playback nor a scrub re-evaluates this body or lays out the host.
struct SeekProgressView: View {
    let width: CGFloat
    let head: Theme.Box
    let samples: WaveformSamples?
    /// The continue-watching position 0...1 while the toast is up.
    let resume: Double?
    @Environment(PlaybackClock.self) private var clock
    @Environment(InterfaceModel.self) private var ui
    @Environment(PlayerModel.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let inset = Theme.Spacing.gap2

    var body: some View {
        NativeSeekProgress(clock: clock, width: width, head: head, samples: samples, resume: resume,
                           visible: ui.areBarsVisible && !ui.isUIHidden && !player.isPictureInPicture,
                           reduceMotion: reduceMotion, rate: player.rate)
    }
}

/// 4778:26191: waveform bars at a fixed pitch, with a gap (the head slot) where the playhead sits.
/// Equal when the samples and the head slot are equal, so the path is rebuilt only when the head
/// crosses a slot.
struct WaveformShape: Shape, Equatable {
    let samples: WaveformSamples
    var headSlot: Int = 0
    /// The bar index the playhead sits in front of, for a head position measured from the first bar.
    static func slot(forHeadX x: CGFloat) -> Int { max(0, Int((x / MXRPlayerMetrics.waveformPitch).rounded())) }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let samples = samples.values
        guard rect.width > 0, rect.height > 0, !samples.isEmpty else { return path }
        let pitch = MXRPlayerMetrics.waveformPitch
        let capacity = max(1, Int((rect.width - MXRPlayerMetrics.waveformHeadSlotWidth - MXRPlayerMetrics.waveformWidth) / pitch) + 1)
        let count = min(samples.count, capacity)
        for index in 0..<count {
            // Each visible bar covers its part of the entire signal, preserving peaks at narrow widths.
            // When all samples fit, every range contains one unchanged source sample.
            let lower = index * samples.count / count
            let upper = (index + 1) * samples.count / count
            let sample = samples[lower..<upper].max() ?? 0
            let x = rect.minX + CGFloat(index) * pitch + (index >= headSlot ? MXRPlayerMetrics.waveformHeadSlotWidth : 0)
            guard x < rect.maxX else { break }
            let h = max(Theme.Stroke.hairline, CGFloat(min(max(sample, 0), 1)) * rect.height)
            path.addRoundedRect(in: CGRect(x: x, y: rect.midY - h / 2, width: MXRPlayerMetrics.waveformWidth, height: h),
                                cornerSize: CGSize(width: Theme.Radius.xs, height: Theme.Radius.xs))
        }
        return path
    }
}
