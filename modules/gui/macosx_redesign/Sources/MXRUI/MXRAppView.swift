import AppKit
import SwiftUI
import MXRCore
import MXRDesign

/// The window composition shared by the real VLC window and the gallery (D021, D030). One persistent
/// tree: the media canvas stays at a position that depends only on the window mode, and the bars,
/// library, panels and popups are layers above it. Opening a panel never moves or re-hosts the video.
///
/// The host draws the native traffic lights and publishes their width in
/// ``InterfaceModel/windowControlsReserve`` (D022); the content ignores the titlebar safe area so the
/// 40 pt top bar starts at y = 0.
@MainActor
public struct MXRAppView: View {
    @Environment(AppModel.self) private var app
    @Environment(InterfaceModel.self) private var interface
    @Environment(AppearanceModel.self) private var appearance
    private let videoView: AnyView
    private let onPictureInPicture: (() -> Void)?
    private let engineVersion: String?

    /// Named coordinate space of the window content (y = 0 at the top of the top bar). Gallery media
    /// fixtures use it to keep whole-window artwork in window coordinates.
    public static let coordinateSpace = "MXRAppWindow"

    public init(videoView: AnyView = AnyView(Color.clear), onPictureInPicture: (() -> Void)? = nil,
                engineVersion: String? = nil) {
        self.videoView = videoView
        self.onPictureInPicture = onPictureInPicture
        self.engineVersion = engineVersion
    }

    public var body: some View {
        MXRAppComposition(videoView: videoView, onPictureInPicture: onPictureInPicture)
            .ignoresSafeArea()
            // Dialogs are centred in-window modals over a scrim, one at a time (SD-11; MXRDialogHost.swift).
            .mxrDialogPresentation(engineVersion: engineVersion)
            .mxrTheme(Theme.Mode(appearance.theme))
            .mxrAccent(Theme.Accent(appearance.accent))
    }
}

/// Layers, back to front: window background (drag region) · media canvas or full library ·
/// outside-click catcher · compact library · bars · right panel · Customize
/// palette · OSD and continue-watching toast.
@MainActor
private struct MXRAppComposition: View {
    @Environment(AppModel.self) private var app
    @Environment(InterfaceModel.self) private var interface
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal = PlayerChromeReveal()
    let videoView: AnyView
    let onPictureInPicture: (() -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let style = canvasStyle
            ZStack(alignment: .topLeading) {
                // Frame bands and empty chrome move the window (D022), also in Hide UI.
                MXRWindowDragArea(onMouseDown: dismissPopup)
                    .background(Theme.Color.bgA3)
                if interface.library == .full && !interface.isUIHidden {
                    fullLibrary(size: size)
                } else {
                    MXRPlayerView(videoView: videoView, style: style, controlHeight: controlHeight,
                                  reservesBars: !app.player.isFullscreen && !interface.isUIHidden)
                        .frame(width: size.width, height: size.height)
                        .overlay {
                            if app.player.isPictureInPicture {
                                pictureInPicturePlaceholder(style: style)
                            }
                        }
                    // §15: Customize keeps the paused video visible behind the translucent palette
                    // (Player - customize uses the same video fill as Player; 19m12.4). No scrim.
                }
                if interface.hasTransientPopup && !interface.isUIHidden {
                    // D024: a click outside closes the popup and is not also a play/pause click.
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { _ = dismissPopup() }
                        .accessibilityHidden(true)
                }
                if !interface.isUIHidden {
                    if libraryWidth(in: size.width) > 0 {
                        MXRLibraryView(compact: true)
                            .frame(width: libraryWidth(in: size.width),
                                   height: max(0, size.height - topBarBottom - controlHeight))
                            .offset(y: topBarBottom)
                            .mxrPopupTransition(from: .leading, reduceMotion: reduceMotion)
                    }
                    bars(size: size)
                    if let panel = interface.rightPanel, let frame = rightPanelFrame(in: size) {
                        MXRRightPanelView()
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                            .id(panelFamily(panel))
                            .mxrPopupTransition(from: panelEdge(panel), reduceMotion: reduceMotion)
                    }
                }
                if interface.isCustomizing { customization(size: size) }
                overlays(size: size)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .coordinateSpace(.named(MXRAppView.coordinateSpace))
            // D057: in a window too narrow for both, the compact library yields to a right panel and
            // comes back when it closes; opening the library closes the panel instead.
            .onChange(of: interface.library) { old, library in
                interface.reconcileLibraryAndPanel(fit: libraryFitsBesidePanel(size.width),
                                                   libraryOpened: old != .compact && library == .compact)
            }
            .onChange(of: interface.rightPanel) { _, _ in
                interface.reconcileLibraryAndPanel(fit: libraryFitsBesidePanel(size.width))
            }
            .onChange(of: size.width, initial: true) { _, width in
                interface.reconcileLibraryAndPanel(fit: libraryFitsBesidePanel(width))
            }
            .animation(reduceMotion ? nil : .easeOut(duration: Theme.Popup.appearDuration), value: interface.rightPanel.map(panelFamily))
            .animation(reduceMotion ? nil : .easeOut(duration: Theme.Popup.appearDuration), value: interface.library)
            // D023/WT-11: SwiftUI hover stops at the embedded vout NSView, so the pointer comes from an
            // AppKit tracking area behind every layer (tracking areas ignore z-order) that never takes clicks.
            .background {
                MXRPointerTracker { point in
                    reveal.pointer(at: point, in: size, controlHeight: controlHeight, app: app)
                }
                .accessibilityHidden(true)
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard !urls.isEmpty else { return false }
                app.open(urls: urls)
                return true
            }
        }
        .onAppear { reveal.evaluate(app: app) }
        .onDisappear { reveal.cancel() }
        .onChange(of: PlayerChromeReveal.Inputs(app: app)) { _, _ in reveal.evaluate(app: app) }
        .onChange(of: interface.isTopBarVisible) { _, _ in reveal.evaluate(app: app) }
        .onChange(of: interface.isControlBarVisible) { _, _ in reveal.evaluate(app: app) }
        .onChange(of: subtitleSafeInset, initial: true) { _, inset in
            if interface.subtitleSafeInset != inset { interface.subtitleSafeInset = inset }
        }
    }

    /// The control bar overlays the picture only where the canvas runs under it (fullscreen,
    /// Customize); between pinned bars nothing covers the subtitles.
    private var subtitleSafeInset: Double {
        guard !interface.isUIHidden, interface.library != .full, !app.player.isAudioOnly,
              interface.isControlBarVisible else { return 0 }
        return Double(max(0, controlHeight - canvasStyle.windowPictureInsets(controlHeight: controlHeight).bottom))
    }

    // MARK: Layers

    @ViewBuilder
    private func bars(size: CGSize) -> some View {
        let topVisible = interface.isTopBarVisible
        let controlVisible = interface.isControlBarVisible
        let reveal: Animation? = reduceMotion ? nil : .easeOut(duration: MXRPlayerMetrics.revealDuration)
        // A hidden bar leaves the tree: nothing of it draws, takes the pointer or keeps a tooltip
        // open after it faded (live run 1, "Fullscreen" tooltip).
        Group {
            if topVisible {
                MXRTopBar(onPictureInPicture: onPictureInPicture)
                    .frame(width: size.width)
                    .opacity(chromeOpacity)
                    .offset(y: interface.topBarOffset)
                    .transition(.opacity)
            }
            if interface.library != .full && controlVisible {
                MXRControlBar(usesOpaqueVideoBackground: true, onPictureInPicture: onPictureInPicture)
                    .frame(width: size.width)
                    .offset(y: size.height - controlHeight)
                    .opacity(chromeOpacity)
                    .transition(.opacity)
            }
        }
        .animation(reveal, value: topVisible)
        .animation(reveal, value: controlVisible)
        .animation(reveal, value: interface.topBarOffset)
        // D053: pinned beside the Light picture, the bars are their tint over the canvas base.
        .environment(\.mxrBarsBesidePicture, canvasStyle == .underBars && interface.library != .full)
    }

    @ViewBuilder
    private func fullLibrary(size: CGSize) -> some View {
        MXRLibraryView(compact: false)
            .overlay {
                if app.player.media != nil { MXRMiniPlayerDock(videoView: videoView) }
            }
            .frame(width: size.width, height: max(0, size.height - Theme.Metric.Window.topBar.height))
            .offset(y: Theme.Metric.Window.topBar.height)
    }

    @ViewBuilder
    private func customization(size: CGSize) -> some View {
        let available = max(0, size.height - Theme.Metric.Window.topBar.height - controlHeight - Theme.Metric.panelInset * 2)
        let height = min(Theme.Metric.Customization.panel.height, available)
        MXRCustomizationView()
            .frame(width: min(Theme.Metric.Customization.panel.width, max(0, size.width - Theme.Metric.panelInset * 2)),
                   height: height)
            .offset(y: PlayerGeometry.customizationOffset(windowHeight: size.height, paletteHeight: height,
                                                          controlHeight: controlHeight))
            .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func overlays(size: CGSize) -> some View {
        let top = interface.isTopBarVisible && !interface.isUIHidden ? topBarBottom : 0
        let bottom = interface.isControlBarVisible && !interface.isUIHidden && interface.library != .full ? controlHeight : 0
        // A-02/A-08: player information stays in the visible video: right of the compact library,
        // left of an open right panel, between the visible bars.
        let area = PlayerGeometry.informationRect(in: size, top: top, bottom: bottom,
                                                  leading: libraryWidth(in: size.width), rightPanel: rightPanelFrame(in: size))
        if interface.library != .full {
            // D027: top-right in the video. The full library has no video; the mini-player shows the state.
            // B-08: sized from the picture in the media canvas, anchored to its visible part.
            let insets = canvasStyle.windowPictureInsets(controlHeight: controlHeight)
            MXRPlayerOSD(canvas: CGRect(x: insets.leading, y: insets.top,
                                        width: max(0, size.width - insets.leading - insets.trailing),
                                        height: max(0, size.height - insets.top - insets.bottom)),
                         bounds: area)
        }
        if interface.showMetadata && interface.showsPlayerInformation {
            // Playback tab "Show Metadata" (S17): bottom-left, clear of the OSD and the right panels.
            MXRMetadataOverlayView()
                .frame(width: area.width, height: area.height, alignment: .bottomLeading)
                .offset(x: area.minX, y: area.minY)
        }
        if app.player.restorePrompt != nil && interface.showsPlayerInformation
            && area.width >= MXRContinueWatchingToast.minimumWidth {
            // 14m09.8: centred in the video, never under the library or a panel.
            MXRContinueWatchingToast()
                .frame(width: area.width)
                .offset(x: area.minX, y: area.maxY - Theme.Metric.Dialogs.resumeToast.height)
                .transition(.opacity.animation(reduceMotion ? nil : .easeOut(duration: Theme.Popup.appearDuration))) // BB-10
        }
    }

    /// A-06, D042: macOS players leave a quiet placeholder where the video was; a click returns the
    /// video from the PiP window.
    private func pictureInPicturePlaceholder(style: PlayerCanvasStyle) -> some View {
        Button {
            if let onPictureInPicture { onPictureInPicture() } else { app.player.setPictureInPicture(false) }
        } label: {
            VStack(spacing: Theme.Spacing.gap20) {
                MXRIcon(.pip, size: MXRPlayerMetrics.pictureInPictureIcon, tint: Theme.Color.fg2)
                Text(MXRPlayerCopy.pictureInPicturePlaceholder)
                    .mxrTextStyle(Theme.Font.bodyLarge).foregroundStyle(Theme.Color.fg2)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Metric.panelInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Color.bgB2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // D042: the placeholder stands in for the video, which is dark in both themes; in Light the
        // translucent bars over it then read as over video (D053), not over a light panel.
        .mxrTheme(.dark)
        .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius))
        .padding(style.windowPictureInsets(controlHeight: controlHeight).edgeInsets)
        .accessibilityLabel(MXRPlayerCopy.pictureInPicturePlaceholder)
        .accessibilityHint(MXRPlayerCopy.pictureInPictureReturn)
    }

    private func rightPanelFrame(in size: CGSize) -> CGRect? {
        guard let panel = interface.rightPanel, interface.library != .full, !interface.isUIHidden else { return nil }
        return PlayerGeometry.rightPanelFrame(panel, in: size, controlHeight: controlHeight, leadingInset: libraryWidth(in: size.width),
                                              topBarOffset: interface.topBarOffset)
    }

    // MARK: State

    /// D024: Esc and outside clicks close the front-most popup.
    private func dismissPopup() -> Bool { interface.dismissTransientPopup() }

    private var canvasStyle: PlayerCanvasStyle {
        PlayerCanvasStyle.resolve(fullscreen: app.player.isFullscreen, uiHidden: interface.isUIHidden,
                                  customizing: interface.isCustomizing, light: colorScheme == .light,
                                  autoHidesInWindow: !app.player.isFullscreen && app.controlsAutoHideMode == .always)
    }

    private var chromeOpacity: Double {
        app.player.isFullscreen ? MXRPlayerPreferences(app: app).fullscreenControlsOpacity : 1
    }

    /// The bottom edge of the top bar, below macOS's fullscreen strip while it shows (D055).
    private var topBarBottom: CGFloat { Theme.Metric.Window.topBar.height + CGFloat(interface.topBarOffset) }

    private var controlHeight: CGFloat {
        CGFloat(PlayerGeometry.controlRows(layoutRows: app.playerLayout.bottom.count, customizing: interface.isCustomizing))
            * Theme.Metric.ControlBar.bar.height
    }

    /// The compact library's column, 0 when it is closed, hidden by Hide UI or yields to a right panel
    /// in a narrow window (D019, D057).
    private func libraryWidth(in width: CGFloat) -> CGFloat {
        guard interface.library == .compact && !interface.isUIHidden else { return 0 }
        return PlayerGeometry.compactLibraryWidth(windowWidth: width, panelOpen: interface.rightPanel != nil)
    }

    private func libraryFitsBesidePanel(_ width: CGFloat) -> Bool {
        PlayerGeometry.compactLibraryWidth(windowWidth: width, panelOpen: true) > 0
    }

    /// Switching tabs keeps the panel in place; changing family (tracks ↔ sidebar ↔ queue) animates.
    private func panelFamily(_ panel: RightPanel) -> Int {
        switch panel {
        case .tracks: 0
        case .sidebar: 1
        case .queue: 2
        }
    }

    /// The track popover rises from the bar; the sidebar and queue come in from the right edge.
    private func panelEdge(_ panel: RightPanel) -> Edge {
        if case .tracks = panel { .bottom } else { .trailing }
    }
}

/// Reports the pointer in window-content coordinates (y down, `nil` when it leaves) from an AppKit
/// tracking area. Hit-testing passes through, so clicks, drags and SwiftUI hover effects are untouched.
private struct MXRPointerTracker: NSViewRepresentable {
    let onMove: (CGPoint?) -> Void

    func makeNSView(context: Context) -> TrackingView { TrackingView() }
    func updateNSView(_ view: TrackingView, context: Context) { view.onMove = onMove }

    final class TrackingView: NSView {
        var onMove: ((CGPoint?) -> Void)?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self, userInfo: nil))
        }

        override func mouseEntered(with event: NSEvent) { report(event) }
        override func mouseMoved(with event: NSEvent) { report(event) }
        override func mouseDragged(with event: NSEvent) { report(event) }
        override func mouseExited(with event: NSEvent) { onMove?(nil) }

        private func report(_ event: NSEvent) {
            onMove?(convert(event.locationInWindow, from: nil))
        }
    }
}
