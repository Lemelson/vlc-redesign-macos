import MXRCore
import MXRDesign
import SwiftUI

/// The media canvas: the retained video host (or the music now-playing view) at the position the
/// window mode gives it (``PlayerCanvasStyle``). Bars, library and panels are composed above it by
/// ``MXRAppView``; this view never moves when they appear (D021, VIDEO_BREAKDOWN §03).
public struct MXRPlayerView: View {
    @Environment(AppModel.self) private var app
    private let videoView: AnyView
    private let style: PlayerCanvasStyle
    private let controlHeight: CGFloat
    private let reservesBars: Bool

    init(videoView: AnyView, style: PlayerCanvasStyle, controlHeight: CGFloat, reservesBars: Bool) {
        self.videoView = videoView; self.style = style
        self.controlHeight = controlHeight; self.reservesBars = reservesBars
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                if app.player.isAudioOnly {
                    if MXRPlayerPreferences(app: app).showsCoverArtwork {
                        MXRMusicBackdrop().frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    // S34 centres the artwork between the bars; in fullscreen the bars overlay it.
                    MXRMusicNowPlayingView(showsBackdrop: false)
                        .padding(.top, reservesBars ? Theme.Metric.Window.topBar.height : 0)
                        .padding(.bottom, reservesBars ? controlHeight : 0)
                } else {
                    videoSurface.padding(style.insets(controlHeight: controlHeight).edgeInsets)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .mxrVideoContextMenu()
        }
    }

    private var videoSurface: some View {
        ZStack {
            Group {
                videoView
                MXRPausedSeekStill() // D031: exact frame over the video after a paused seek (agent B)
            }
            .padding(style.pictureInsets(controlHeight: controlHeight).edgeInsets)
            if let error = app.player.errorMessage, app.player.media != nil {
                // A real input failure on the current media. Play with an empty queue opens the
                // library instead (D029), so no card appears without media.
                VStack(spacing: Theme.Spacing.gap12) {
                    Text(error).mxrTextStyle(Theme.Font.bodyLarge).foregroundStyle(Theme.Color.fg1)
                        .multilineTextAlignment(.center)
                    DialogButton(title: "Try Again", primary: true) { app.player.play() }
                }.padding(Theme.Metric.panelInset)
                    .background { MXRBackdropSurface(tint: Theme.Color.bgB1Transparent, cornerRadius: Theme.Radius.xl) }
            } else if app.player.media == nil {
                Button { app.interface.request(.openFiles) } label: {
                    VStack(spacing: Theme.Spacing.gap20) {
                        MXRIcon(.vlc, size: Theme.Metric.ControlBar.playButton.width)
                        Text("Open a media file").mxrTextStyle(Theme.Font.bodyLarge).foregroundStyle(Theme.Color.fgA2)
                    }
                }.buttonStyle(.plain).accessibilityLabel("Open a media file")
            } else if app.player.isBuffering {
                ProgressView().controlSize(.large).accessibilityLabel("Buffering")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { canvasFill }
        .clipShape(.rect(cornerRadius: style.cornerRadius))
    }

    /// BG/B2 behind the picture; in Light (D055) the bands under the pinned bars are the dark base
    /// their translucent material is drawn for (D046), so the bars read Player - Light's #ABABAA.
    private var canvasFill: some View {
        let bands = style.pictureInsets(controlHeight: controlHeight)
        return VStack(spacing: 0) {
            Rectangle().fill(MXRBackdropBase()).frame(height: bands.top)
            Rectangle().fill(Theme.Color.bgB2)
            Rectangle().fill(MXRBackdropBase()).frame(height: bands.bottom)
        }
    }
}

public struct MXRContinueWatchingToast: View {
    @Environment(AppModel.self) private var app
    public init() {}
    public var body: some View {
        if let prompt = app.player.restorePrompt {
            // A narrow video drops the whole message rather than truncating it to "You alr…": the
            // toast then hugs its actions, and the button keeps the time as its accessibility hint.
            // Below the actions' width (a window near its 480 pt minimum with the compact library or a
            // panel open) the button hugs VLC's own short label, "Continue" (qt/player/qml/ResumeDialog.qml);
            // only narrower still does the last layout take the offered width and truncate it. The
            // close button stays whole and nothing draws outside the video (D051).
            ViewThatFits(in: .horizontal) {
                toast(prompt, showsMessage: true)
                toast(prompt, showsMessage: false)
                toast(prompt, showsMessage: false, button: .short)
                toast(prompt, showsMessage: false, button: .compressed)
            }
            .onHover { app.player.holdRestorePrompt($0) } // BB-10: no timeout while hovered
        }
    }

    /// The narrowest toast that still reads: its padding, the close button and a Continue button
    /// with room for a few characters. A narrower video area shows no toast (D042: player
    /// information draws only in the visible video); the prompt keeps its timeout.
    public static var minimumWidth: CGFloat {
        let box = Theme.Metric.Dialogs.resumeToast
        return box.padding.leading + Theme.Metric.Dialogs.resumeContinueButton.width / 2 + Theme.Spacing.gap10
            + Theme.Metric.Dialogs.resumeCloseButton.width + box.padding.trailing
    }

    /// The Continue button's three widths: Figma's 146 pt "Continue Watching" (1922:9585), VLC's
    /// short "Continue" hugging its label, and that label truncating in whatever width is left.
    enum ContinueButtonWidth { case figma, short, compressed }

    private func toast(_ prompt: RestorePrompt, showsMessage: Bool, button: ContinueButtonWidth = .figma) -> some View {
        let box = Theme.Metric.Dialogs.resumeToast
        let time = prompt.time.formatted(.hoursMinutesSeconds)
        return HStack(spacing: 0) {
            if showsMessage {
                // 1922:9584: the time is Inter SemiBold 16, the same size as the text (.bold() fell back to SF, BB-10).
                (Text("You already watched till ") + Text(time).font(Theme.Font.buttonLarge.font))
                    .mxrTextStyle(Theme.Font.bodyLarge).foregroundStyle(Theme.Color.fg2)
                    .lineLimit(1).fixedSize()
                Spacer(minLength: Theme.Spacing.gap10)
            }
            Button(button == .figma ? MXRPlayerCopy.continueWatching : MXRPlayerCopy.continueShort) { app.player.resumePlayback() }
                .buttonStyle(ContinueButtonStyle(width: button))
                .fixedSize(horizontal: button != .compressed, vertical: true)
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityLabel(MXRPlayerCopy.continueWatching)
                .accessibilityHint("Resumes at \(time)")
            MXRPlayerIconButton(.close, title: "Dismiss continue watching", box: Theme.Metric.Dialogs.resumeCloseButton) {
                app.player.dismissRestorePrompt()
            }.background(Theme.Color.bgA1, in: .rect(cornerRadius: Theme.Radius.lg)) // 6309:14029 BG/A1
                .padding(.leading, Theme.Spacing.gap10)
        }
        .padding(box.padding)
        .frame(maxWidth: showsMessage ? box.width : nil)
        .frame(height: box.height)
        .background { MXRBackdropSurface(tint: Theme.Color.bgA3Transparent, cornerRadius: box.radius ?? Theme.Radius.toast) }
        .accessibilityElement(children: .contain)
    }
}

private struct ContinueButtonStyle: ButtonStyle {
    /// Figma's 146 pt, or (short, compressed) the label with the button's own side padding; a
    /// compressed button gives up width, truncating, instead of overflowing the toast.
    var width: MXRContinueWatchingToast.ContinueButtonWidth = .figma
    func makeBody(configuration: Configuration) -> some View {
        let box = Theme.Metric.Dialogs.resumeContinueButton
        configuration.label.mxrTextStyle(Theme.Font.button).foregroundStyle(Theme.Color.fgB1)
            .lineLimit(1).truncationMode(.tail)
            .padding(.horizontal, width == .figma ? 0 : box.padding.leading)
            .frame(minWidth: width == .figma ? box.width : 0, maxWidth: box.width)
            .frame(height: box.height)
            .background(configuration.isPressed ? Theme.Color.accentDim : Theme.Color.accentMain,
                        in: .rect(cornerRadius: box.radius ?? Theme.Radius.lg))
    }
}

/// S34: the current artwork drives both the centered cover and the enlarged blurred backdrop.
public struct MXRMusicNowPlayingView: View {
    @Environment(AppModel.self) private var app
    private let showsBackdrop: Bool
    public init() { showsBackdrop = true }
    init(showsBackdrop: Bool) { self.showsBackdrop = showsBackdrop }
    public var body: some View {
        GeometryReader { geometry in
            let art = MXRPlayerMetrics.artwork
            let fullHeight = art.height + MXRPlayerMetrics.artworkTitleGap + Theme.Font.nowPlayingTitle.lineHeight
            let scale = min(1, max(0, geometry.size.height - Theme.Metric.panelInset * 2) / fullHeight,
                            max(0, geometry.size.width - Theme.Metric.panelInset * 2) / art.width)
            ZStack {
                if showsBackdrop && MXRPlayerPreferences(app: app).showsCoverArtwork { MXRMusicBackdrop() }
                VStack(spacing: MXRPlayerMetrics.artworkTitleGap * scale) {
                    if MXRPlayerPreferences(app: app).showsCoverArtwork {
                    MXRMediaArtwork()
                        .frame(width: art.width * scale, height: art.height * scale)
                        .clipShape(.rect(cornerRadius: art.radius ?? Theme.Radius.albumArt))
                        .background {
                            RoundedRectangle(cornerRadius: (art.radius ?? Theme.Radius.albumArt) + Theme.Effect.albumArtGlow.spread)
                                .fill(Theme.Effect.albumArtGlow.color.color)
                                .frame(width: art.width * scale + Theme.Effect.albumArtGlow.spread * 2,
                                       height: art.height * scale + Theme.Effect.albumArtGlow.spread * 2)
                                .blur(radius: Theme.Effect.albumArtGlow.blur / 2)
                                .padding(Theme.Effect.albumArtGlow.blur)
                                .drawingGroup()
                        }
                    }
                    Text(nowPlayingTitle).mxrTextStyle(Theme.Font.nowPlayingTitle)
                        .foregroundStyle(Theme.Color.fgA1).lineLimit(1)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now playing")
        .accessibilityValue(nowPlayingTitle)
    }
    private var nowPlayingTitle: String {
        guard let media = app.player.media else { return "" }
        return media.artist.map { media.displayTitle + " - " + $0 } ?? media.displayTitle
    }
}

private struct MXRMusicBackdrop: View {
    var body: some View {
        MXRMediaArtwork()
            .frame(width: MXRPlayerMetrics.backdropSize, height: MXRPlayerMetrics.backdropSize)
            .blur(radius: Theme.Effect.albumBackdropBlurRadius / 2)
            .drawingGroup()
            .allowsHitTesting(false)
    }
}

/// Cached artwork is available on the first gallery frame; real media is loaded asynchronously.
public struct MXRMediaArtwork: View {
    @Environment(AppModel.self) private var app
    @State private var artwork: CGImage?
    @State private var artworkMediaID: String?
    public init() {}
    public var body: some View {
        let media = app.player.media
        let size = CGSize(width: MXRPlayerMetrics.artwork.width * 2, height: MXRPlayerMetrics.artwork.height * 2)
        let cached = media.flatMap { app.backends.thumbnails.cachedArtwork(for: $0, maxPixelSize: size) }
        Group {
            if let image = cached ?? (artworkMediaID == media?.id ? artwork : nil) {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Rectangle().fill(Theme.Color.thumbPlaceholder).overlay { MXRIcon(.music, tint: Theme.Color.accentMain) }
            }
        }
        .clipped()
        .task(id: media?.id) {
            artwork = nil; artworkMediaID = nil
            guard let media else { return }
            let result = await app.backends.thumbnails.artwork(for: media, maxPixelSize: size)
            guard !Task.isCancelled else { return }
            artwork = result; artworkMediaID = media.id
        }
        .accessibilityHidden(true)
    }
}
