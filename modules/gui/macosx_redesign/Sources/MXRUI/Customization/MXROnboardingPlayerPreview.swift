import MXRCore
import MXRDesign
import SwiftUI

/// The 0.55-scale player inside S70. Controls use the same token metrics as the real bars;
/// appearance is inherited from the onboarding, so each theme/accent updates immediately.
struct MXROnboardingPlayerPreview: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // D022: the Mac player's bar (traffic lights, then the cone; only the fullscreen button on the
            // right, D007 amended), not Figma's Windows minimise/maximise/close.
            HStack(spacing: 0) {
                MXRIcon(.vlc)
                Spacer()
                MXRIcon(.fullscreen)
            }
            .padding(.leading, Theme.Metric.Window.topBar.padding.leading + Theme.MacWindowControls.trailingEdge
                     + Theme.Metric.Window.topBarLeftGroup.gap)
            .padding(.trailing, Theme.Metric.Window.topBar.padding.trailing)
            .frame(height: Theme.Metric.topBarHeight)
            .overlay(alignment: .leading) { trafficLights }
            .background { bar(dark: Theme.Color.bgA4) }
            Spacer(minLength: 0)
            controls
        }
        .frame(width: Theme.Metric.Window.player.width, height: Theme.Metric.Window.player.height)
        .background(Theme.Color.bgB2)
        .scaleEffect(Theme.Metric.Onboarding.previewScale, anchor: .topLeading)
        .frame(width: Theme.Metric.Onboarding.preview.width, height: Theme.Metric.Onboarding.preview.height, alignment: .topLeading)
        .clipped()
    }

    /// Figma's dark preview fills (1902:3670); in Light the bars are the Light window's own (no Figma
    /// frame): BG/A3 Transparent over the canvas base, Player - Light's #ABABAA (D053).
    @ViewBuilder private func bar(dark: ThemeColor) -> some View {
        if colorScheme == .light {
            MXRBackdropSurface(tint: Theme.Color.bgA3Transparent, overCanvasBase: true)
        } else {
            Rectangle().fill(dark)
        }
    }

    private var trafficLights: some View {
        let lights = Theme.MacWindowControls.self
        return HStack(spacing: lights.spacing) {
            ForEach([lights.close, lights.minimize, lights.zoom], id: \.self) { color in
                Circle().fill(color.color)
                    .overlay(Circle().strokeBorder(lights.edge.color, lineWidth: Theme.Stroke.hairline))
                    .frame(width: lights.diameter, height: lights.diameter)
            }
        }
        .padding(.leading, lights.leadingInset)
        .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: Theme.Metric.ControlBar.bar.gap) {
            HStack(spacing: Theme.Metric.ControlBar.transportGroup.gap) {
                Button { app.queue.previous() } label: { transportIcon(.previous) }.buttonStyle(.plain)
                    .accessibilityLabel("Previous item in preview")
                Button { app.player.togglePlayPause() } label: {
                    MXRIcon(app.player.isPlaying ? .pause : .play, tint: Theme.Color.fgB1)
                        .frame(width: Theme.Metric.ControlBar.playButton.width, height: Theme.Metric.ControlBar.playButton.height)
                        .background(Theme.Color.accentMain,
                                    in: RoundedRectangle(cornerRadius: Theme.Metric.ControlBar.playButton.radius ?? Theme.Radius.lg))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play or pause preview")
                Button { app.queue.next() } label: { transportIcon(.next) }.buttonStyle(.plain)
                    .accessibilityLabel("Next item in preview")
            }
            HStack(spacing: Theme.Metric.ControlBar.seekGroup.gap) {
                timeLabel(app.clock.displayTime)
                seekTrack
                timeLabel(app.clock.length)
            }
            HStack(spacing: Theme.Metric.ControlBar.volumeGroup.gap) {
                MXRIcon(.volumeHigh)
                volumeCone
            }
            HStack(spacing: Theme.Metric.ControlBar.trackButtonsGroup.gap) {
                controlIcon(.audio)
                controlIcon(.subtitles)
                controlIcon(.playbackSettings)
            }
            controlIcon(.lists)
        }
        .padding(.horizontal, Theme.Metric.ControlBar.bar.padding.leading)
        .frame(height: Theme.Metric.controlBarHeight)
        .background { bar(dark: Theme.Color.bgA3Transparent) }
    }

    private func transportIcon(_ name: MXRIcon.Name) -> some View {
        MXRIcon(name).frame(width: Theme.Metric.ControlBar.prevNextCell.width,
                            height: Theme.Metric.ControlBar.prevNextCell.height)
    }

    private func controlIcon(_ name: MXRIcon.Name) -> some View {
        MXRIcon(name).frame(width: Theme.Metric.ControlBar.iconButton.width,
                            height: Theme.Metric.ControlBar.iconButton.height)
    }

    private func timeLabel(_ time: MediaTime) -> some View {
        Text(time.formatted(.hoursMinutesSeconds)).mxrTextStyle(.time).foregroundStyle(Theme.Color.fgA1)
            .frame(width: Theme.Metric.ControlBar.timeLabel.width, height: Theme.Metric.ControlBar.timeLabel.height)
    }

    private var seekTrack: some View {
        GeometryReader { geometry in
            let track = Theme.Metric.ControlBar.seekTrack
            let fill = Theme.Metric.ControlBar.seekFill
            let head = Theme.Metric.ControlBar.playhead
            let inset = (track.height - fill.height) / 2
            let fraction = app.clock.length > .zero ? app.clock.displayTime.seconds / app.clock.length.seconds : 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: track.radius ?? Theme.Radius.lg).fill(Theme.Color.bgB2)
                RoundedRectangle(cornerRadius: fill.radius ?? Theme.Radius.lg).fill(Theme.Color.bgAccentBright)
                    .frame(width: max(head.width, (geometry.size.width - inset * 2) * fraction), height: fill.height)
                    .overlay(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: head.radius ?? Theme.Radius.lg).fill(Theme.Color.accentMain)
                            .frame(width: head.width, height: head.height)
                    }
                    .padding(.leading, inset)
            }
        }
        .frame(height: Theme.Metric.ControlBar.seekTrack.height)
        .accessibilityLabel("Playback progress preview")
    }

    private var volumeCone: some View {
        let box = Theme.Metric.Volume.cone
        return MXRPreviewVolumeShape()
            .fill(Theme.Gradient.volumeConeTrack)
            .overlay(alignment: .leading) {
                MXRPreviewVolumeShape()
                    .fill(LinearGradient(stops: Theme.Gradient.volumeCone.map { .init(color: $0.color.color, location: $0.location) },
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay(MXRPreviewVolumeShape().fill(Theme.Gradient.volumeConeOverlay))
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: volumeFillWidth)
                    }
            }
            .frame(width: box.width, height: box.height)
            .accessibilityLabel("Volume preview")
    }

    private var volumeFillWidth: CGFloat {
        let steps = Theme.Metric.Volume.fillWidthByStep
        let percent = app.player.volume * 100
        for (lower, upper) in zip(steps, steps.dropFirst()) where percent <= Double(upper.percent) {
            let fraction = (percent - Double(lower.percent)) / Double(upper.percent - lower.percent)
            return lower.value + (upper.value - lower.value) * CGFloat(max(0, fraction))
        }
        return Theme.Metric.Volume.cone.width
    }
}

private struct MXRPreviewVolumeShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
