import AppKit
import MXRCore
import MXRDesign
import SwiftUI

// Window chrome behaviour shared by the player composition: independent bar reveal (D023),
// cursor hiding over video, the top-bar window drag region (D022) and popup motion (D024).

/// D023: the top bar and the control bar each follow their own hover zone and hide timer. A bar
/// stays while the pointer is in its zone or while one of its popups is open; it hides right after
/// the pointer leaves (after the "Hide after" delay, 0.5 s by default in Settings › Interface).
/// The effective states live in ``InterfaceModel`` so the host can hide the traffic lights with the
/// top bar and the seek bar's display link can stop with the control bar.
@MainActor
final class PlayerChromeReveal {
    enum Bar: CaseIterable { case top, control }

    /// The inputs that pin or release the bars. Any change re-evaluates both bars.
    struct Inputs: Equatable {
        var allowed: Bool
        var autoHides: Bool
        var playing: Bool
        var customizing: Bool
        var libraryShown: Bool
        var sheetShown: Bool
        var appMenuOpen: Bool
        /// The bar whose anchored popup (speed, zoom, overflow ⋯ …) is open: that bar stays.
        var barPopup: Bar?
        var panelOpen: Bool
        var delay: TimeInterval
        /// D055: macOS shows its fullscreen strip (menu bar, titlebar) over the top of the window.
        var systemStripShown: Bool

        @MainActor init(app: AppModel) {
            let ui = app.interface
            allowed = app.controlsAllowed
            autoHides = app.shouldAutoHideControls
            playing = app.player.isPlaying
            customizing = ui.isCustomizing
            libraryShown = ui.library != .hidden
            sheetShown = ui.sheet != nil
            appMenuOpen = ui.isAppMenuOpen
            barPopup = Bar(owner: MXRPopupCenter.shared.anchoredOwner)
            panelOpen = ui.rightPanel != nil
            delay = app.controlsAutoHideDelay
            systemStripShown = app.player.isFullscreen && ui.fullscreenSystemInset > 0
        }

        /// Paused playback, Customize, the library and dialogs keep both bars (§03: bars hide only
        /// while watching). The app menu belongs to the top bar; track, sidebar and queue panels
        /// belong to the control bar.
        func pins(_ bar: Bar) -> Bool {
            if !playing || customizing || libraryShown || sheetShown || barPopup == bar { return true }
            // D055: the pointer at the top of a fullscreen window is over macOS's strip, not over
            // this window; the strip showing is what tells the top bar the pointer is there.
            return bar == .top ? appMenuOpen || systemStripShown : panelOpen
        }
    }

    private var nearTop = false
    private var nearBottom = false
    private var pointerInside = false
    private var hideTasks: [Bar: Task<Void, Never>] = [:]
    private var cursorTask: Task<Void, Never>?

    /// Pointer moved inside the window (`nil` when it left).
    func pointer(at point: CGPoint?, in size: CGSize, controlHeight: CGFloat, app: AppModel) {
        let ui = app.interface
        if let point {
            let fullscreen = app.player.isFullscreen
            let edge = fullscreen ? MXRPlayerPreferences(app: app).fullscreenHoverEdge : 0
            // A hidden fullscreen bar reveals from the configured edge; a shown bar stays while the
            // pointer is over it.
            func zone(_ height: CGFloat, visible: Bool) -> CGFloat { fullscreen && !visible ? edge : max(height, edge) }
            nearTop = point.y <= CGFloat(ui.topBarOffset) + zone(Theme.Metric.Window.topBar.height, visible: ui.isTopBarVisible)
            nearBottom = point.y >= size.height - zone(controlHeight, visible: ui.isControlBarVisible)
            pointerInside = true
        } else {
            nearTop = false; nearBottom = false; pointerInside = false
        }
        evaluate(app: app)
        armCursorHide(app: app)
    }

    func evaluate(app: AppModel) {
        let inputs = Inputs(app: app)
        let ui = app.interface
        guard inputs.allowed else {
            cancel()
            if ui.isTopBarVisible { ui.isTopBarVisible = false }
            if ui.isControlBarVisible { ui.isControlBarVisible = false }
            if ui.topBarOffset != 0 { ui.topBarOffset = 0 }
            return
        }
        // D055: the top bar moves below macOS's fullscreen strip when it appears, and keeps that
        // place while it stays shown so the pointer coming down from the menu bar can reach it.
        let systemInset = app.player.isFullscreen ? max(0, ui.fullscreenSystemInset) : 0
        if !app.player.isFullscreen, ui.topBarOffset != 0 { ui.topBarOffset = 0 }
        else if systemInset > ui.topBarOffset { ui.topBarOffset = systemInset }
        for bar in Bar.allCases {
            let pinned = !inputs.autoHides || inputs.pins(bar) || (bar == .top ? nearTop : nearBottom)
            if pinned {
                hideTasks.removeValue(forKey: bar)?.cancel()
                if !isVisible(bar, ui) { setVisible(bar, true, ui) }
            } else if isVisible(bar, ui), hideTasks[bar] == nil {
                let delay = inputs.delay
                hideTasks[bar] = Task { @MainActor [weak self, weak app] in
                    if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                    guard !Task.isCancelled, let self, let app else { return }
                    self.hideTasks[bar] = nil
                    let now = Inputs(app: app)
                    let stillPinned = !now.allowed || !now.autoHides || now.pins(bar) || (bar == .top ? self.nearTop : self.nearBottom)
                    if !stillPinned { self.setVisible(bar, false, app.interface) }
                }
            }
        }
    }

    func cancel() {
        hideTasks.values.forEach { $0.cancel() }
        hideTasks.removeAll()
        cursorTask?.cancel()
        cursorTask = nil
    }

    /// WT-11: VLC's `mouse-hide-timeout` hides the pointer over video once both bars are hidden,
    /// in fullscreen or in a window whose bars always auto-hide. Popups and dialogs keep it.
    private func armCursorHide(app: AppModel) {
        cursorTask?.cancel()
        cursorTask = nil
        guard pointerInside, !nearTop, !nearBottom, eligibleForCursorHide(app) else { return }
        let configured = app.settings.backend.value(for: "mouse-hide-timeout")?.doubleValue.map { $0 / 1000 }
        let delay = configured.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? MXRPlayerMetrics.cursorHideDelay
        cursorTask = Task { @MainActor [weak self, weak app] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let app, self.pointerInside,
                  self.eligibleForCursorHide(app),
                  !app.interface.isTopBarVisible, !app.interface.isControlBarVisible else { return }
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    private func eligibleForCursorHide(_ app: AppModel) -> Bool {
        let ui = app.interface
        guard app.player.media != nil, !app.player.isAudioOnly, ui.library == .hidden,
              !ui.hasTransientPopup, ui.sheet == nil, !ui.isCustomizing else { return false }
        return app.player.isFullscreen || app.controlsAutoHideMode == .always
    }

    private func isVisible(_ bar: Bar, _ ui: InterfaceModel) -> Bool {
        bar == .top ? ui.isTopBarVisible : ui.isControlBarVisible
    }

    private func setVisible(_ bar: Bar, _ visible: Bool, _ ui: InterfaceModel) {
        if bar == .top {
            ui.isTopBarVisible = visible
            if !visible, ui.topBarOffset != 0 { ui.topBarOffset = 0 }
        } else { ui.isControlBarVisible = visible }
    }
}

// MARK: - Window drag region

/// D022/WT-10: empty top-bar space (and the video frame in Hide UI) moves the window, and a
/// double-click follows the system "Double-click a window's title bar to" preference.
struct MXRWindowDragArea: NSViewRepresentable {
    /// Called before a drag starts; returns true when the click only dismissed a popup (D024).
    var onMouseDown: (() -> Bool)?

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) { view.onMouseDown = onMouseDown }

    final class DragView: NSView {
        var onMouseDown: (() -> Bool)?
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if onMouseDown?() == true { return }
            if event.clickCount == 2 {
                MXRWindowDragArea.performTitlebarDoubleClick(window)
            } else {
                window.performDrag(with: event)
            }
        }
    }

    /// AppKit's titlebar honours `AppleActionOnDoubleClick` ("Maximize", "Minimize" or "None");
    /// the older `AppleMiniaturizeOnDoubleClick` flag applies when the newer key is absent.
    static func performTitlebarDoubleClick(_ window: NSWindow) {
        let defaults = UserDefaults.standard
        let action = defaults.string(forKey: "AppleActionOnDoubleClick")
            ?? (defaults.bool(forKey: "AppleMiniaturizeOnDoubleClick") ? "Minimize" : "Maximize")
        switch action {
        case "Minimize": window.performMiniaturize(nil)
        case "None": break
        default: window.performZoom(nil)
        }
    }
}

// MARK: - Popup motion

extension View {
    /// D024: fade plus a 6 pt slide from `edge` (the side the popup grows from), 0.15 s ease-out
    /// in and 0.1 s out, the same motion as the design-system menus (``Theme/Popup``); opacity only
    /// under Reduce Motion.
    func mxrPopupTransition(from edge: Edge, reduceMotion: Bool) -> some View {
        transition(MXRPopupTransition.make(from: edge, reduceMotion: reduceMotion))
    }
}

enum MXRPopupTransition {
    static func make(from edge: Edge, reduceMotion: Bool) -> AnyTransition {
        let distance = reduceMotion ? 0 : Theme.Popup.slideDistance
        let offset: CGSize = switch edge {
        case .top: CGSize(width: 0, height: -distance)
        case .bottom: CGSize(width: 0, height: distance)
        case .leading: CGSize(width: -distance, height: 0)
        case .trailing: CGSize(width: distance, height: 0)
        }
        let moved = AnyTransition.opacity.combined(with: .offset(offset))
        return .asymmetric(insertion: moved.animation(.easeOut(duration: Theme.Popup.appearDuration)),
                           removal: moved.animation(.easeIn(duration: Theme.Popup.disappearDuration)))
    }
}

// MARK: - Native window controls

/// D022 geometry shared by the window host and the shipping-composition gallery entries.
public enum MXRWindowControls {
    /// The traffic lights fade with the top bar (D022, D023).
    public static let fadeDuration = MXRPlayerMetrics.revealDuration
    /// The top bar keeps the traffic lights' width plus the Figma left-group gap (247:448) before
    /// the cone, so the cone follows the lights like the other items of the group.
    public static func leadingReserve(zoomButtonMaxX: CGFloat) -> CGFloat {
        zoomButtonMaxX + Theme.Metric.Window.topBarLeftGroup.gap
    }

    /// A compact unified toolbar makes the titlebar exactly one 40 pt top bar tall, so AppKit centres
    /// the traffic lights in the bar without moving them by hand (D022). The empty toolbar draws
    /// nothing and lets clicks through to the SwiftUI bar.
    @MainActor
    public static func configure(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = NSToolbar(identifier: "MXRPlayerWindowToolbar")
        window.toolbarStyle = .unifiedCompact
    }

    /// D055: how far macOS's fullscreen strip (menu bar and titlebar, a separate window) reaches
    /// down into the fullscreen window, in points; 0 while it is hidden above the screen.
    public static func fullscreenSystemInset(stripFrame: CGRect, windowFrame: CGRect, stripShown: Bool) -> Double {
        guard stripShown, stripFrame.width > 0, stripFrame.height > 0,
              stripFrame.minY < windowFrame.maxY, stripFrame.maxX > windowFrame.minX, stripFrame.minX < windowFrame.maxX else { return 0 }
        // AppKit frames grow upwards: the strip's bottom edge is its minY.
        return Double(min(max(0, windowFrame.maxY - stripFrame.minY), windowFrame.height / 2))
    }

    /// The traffic lights' leading reserve in `window` (0 in fullscreen, where macOS hides them).
    @MainActor
    public static func leadingReserve(in window: NSWindow) -> CGFloat {
        guard !window.styleMask.contains(.fullScreen), let zoom = window.standardWindowButton(.zoomButton) else { return 0 }
        return leadingReserve(zoomButtonMaxX: zoom.convert(zoom.bounds, to: nil).maxX)
    }
}

// MARK: - Fullscreen strip (D055)

/// D055: follows how far macOS's fullscreen strip (menu bar and titlebar, its own window) covers
/// the fullscreen window. AppKit does not promise move, resize or occlusion notifications for that
/// window while it animates the menu-bar reveal, so the host does not depend on them: while the
/// window is fullscreen the tracker reads the strip's frame on a short timer (and on every
/// notification that does arrive) and reports each change once. Both paths run the same `sample`.
@MainActor
public final class MXRSystemStripTracker {
    /// The reveal slides in over about a quarter second; a 10 Hz sample shows the bar within one
    /// reveal step, and the timer runs only while the window is fullscreen.
    public static let sampleInterval: TimeInterval = 0.1
    private let sample: @MainActor () -> Double
    private let report: @MainActor (Double) -> Void
    private var timer: Timer?
    private var last: Double?

    /// `sample` returns the strip's current inset (``MXRWindowControls/fullscreenSystemInset(stripFrame:windowFrame:stripShown:)``);
    /// `report` receives it whenever it changes.
    public init(sample: @escaping @MainActor () -> Double, report: @escaping @MainActor (Double) -> Void) {
        self.sample = sample
        self.report = report
    }

    public var isRunning: Bool { timer != nil }

    public func start(interval: TimeInterval = MXRSystemStripTracker.sampleInterval) {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        timer.tolerance = interval / 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        update()
    }

    /// Reads the strip now (a notification arrived, or the timer fired).
    public func update() {
        let inset = sample()
        guard inset != last else { return }
        last = inset
        report(inset)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        last = nil
    }
}
