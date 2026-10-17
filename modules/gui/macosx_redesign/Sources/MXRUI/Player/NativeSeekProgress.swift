import AppKit
import MXRCore
import MXRDesign
import Observation
import QuartzCore
import SwiftUI

/// The moving part of the seek bar (fill or played waveform, resume span and marker, playhead) as
/// Core Animation layers owned by AppKit (D028, D038, ARCHITECTURE §3).
///
/// - The view observes ``PlaybackClock`` itself (`revision`, `displaySecond`, `isRunning`, `length`),
///   so a scrub, a paused seek, a typed time or a Reduce Motion second moves the head without any
///   SwiftUI body or `updateNSView` pass.
/// - While playback runs and the bar is on screen, a `CADisplayLink` moves the layers at the rate
///   the head needs to advance half a point. It stops when the bar is hidden, in PiP, with Reduce
///   Motion, when the window is occluded or the app is hidden.
/// - A frame changes only layer geometry; nothing is drawn with Core Graphics per tick.
struct NativeSeekProgress: NSViewRepresentable {
    let clock: PlaybackClock
    let width: CGFloat
    let head: Theme.Box
    let samples: WaveformSamples?
    let resume: Double?
    /// The bar is shown (bars visible, UI not hidden, not in PiP).
    let visible: Bool
    let reduceMotion: Bool
    let rate: Double
    @Environment(\.colorScheme) private var scheme
    @Environment(\.mxrAccent) private var accent

    func makeNSView(context: Context) -> SeekProgressNSView { SeekProgressNSView() }
    func updateNSView(_ view: SeekProgressNSView, context: Context) {
        view.configure(clock: clock, width: width, head: head, samples: samples, resume: resume,
                       visible: visible, reduceMotion: reduceMotion, rate: rate, scheme: scheme, accent: accent)
    }
    static func dismantleNSView(_ view: SeekProgressNSView, coordinator: ()) { view.stop() }
}

final class SeekProgressNSView: NSView {
    private var scheme: ColorScheme = .dark
    private var accent: Theme.Accent = .orange
    private var clock: PlaybackClock?
    private var head = Theme.Metric.ControlBar.playhead
    private var samples: WaveformSamples?
    private var resume: Double?
    private var drawingWidth: CGFloat = 0
    private var visible = true
    private var reduceMotion = false
    private var rate = 1.0
    private var lastStep: CFTimeInterval = 0
    private var displayLink: CADisplayLink?
    /// Bumped whenever the observed clock changes or the view stops, so stale callbacks are dropped.
    private var observation = 0
    private var observedWindow: NSWindow?
    /// The waveform path is rebuilt only when its inputs change (the head slot moves every few points).
    private var waveformKey: WaveformKey?

    private let resumeSpanLayer = CALayer()
    private let fillLayer = CALayer()
    private let waveformLayer = CAShapeLayer()
    private let playedClipLayer = CALayer()
    private let playedWaveformLayer = CAShapeLayer()
    private let resumeMarkerLayer = CALayer()
    private let headLayer = CALayer()

    /// The playhead's leading x in this view, as last laid out (tests).
    var renderedHeadX: CGFloat { headLayer.frame.minX }
    var rendersHead: Bool { !headLayer.isHidden }
    var renderedHeadCornerRadius: CGFloat { headLayer.cornerRadius }
    var renderedPlayedWaveformColor: CGColor? { playedWaveformLayer.fillColor }
    /// Whether the per-frame display link is running (tests).
    var isAnimating: Bool { displayLink != nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        playedClipLayer.masksToBounds = true
        playedClipLayer.addSublayer(playedWaveformLayer)
        for layer in [resumeSpanLayer, fillLayer, waveformLayer, playedClipLayer, resumeMarkerLayer, headLayer] {
            self.layer?.addSublayer(layer)
        }
        for layer in [resumeSpanLayer, fillLayer, waveformLayer, playedClipLayer, playedWaveformLayer, resumeMarkerLayer, headLayer] {
            layer.actions = Self.noActions
        }
    }

    required init?(coder: NSCoder) { nil }

    private static let noActions: [String: any CAAction] = [
        "bounds": NSNull(), "position": NSNull(), "frame": NSNull(), "path": NSNull(), "hidden": NSNull(),
        "backgroundColor": NSNull(), "fillColor": NSNull(), "cornerRadius": NSNull(), "contentsScale": NSNull(),
    ]

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(clock: PlaybackClock, width: CGFloat, head: Theme.Box, samples: WaveformSamples?, resume: Double?,
                   visible: Bool, reduceMotion: Bool, rate: Double, scheme: ColorScheme, accent: Theme.Accent) {
        let colorsChanged = self.scheme != scheme || self.accent != accent || self.clock == nil
        self.scheme = scheme; self.accent = accent
        drawingWidth = width; self.head = head; self.samples = samples; self.resume = resume
        self.visible = visible; self.reduceMotion = reduceMotion; self.rate = rate
        if self.clock !== clock {
            self.clock = clock
            observeClock()
        }
        if colorsChanged { applyColors() }
        updateLayers()
        updateAnimation()
    }

    func stop() {
        observation &+= 1
        displayLink?.invalidate(); displayLink = nil
        clock = nil
        stopObservingWindow()
    }

    // MARK: Clock observation

    /// Re-registers after every change: Observation reports one change per registration.
    private func observeClock() {
        observation &+= 1
        guard let clock else { return }
        let token = observation
        withObservationTracking {
            _ = clock.revision
            _ = clock.displaySecond
            _ = clock.isRunning
            _ = clock.length
        } onChange: { [weak self] in
            // Called before the new value is stored: apply it on the next main-actor turn.
            Task { @MainActor [weak self] in
                guard let self, self.observation == token else { return }
                self.observeClock()
                self.updateLayers()
                self.updateAnimation()
            }
        }
    }

    // MARK: Display link

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObservingWindow()
        if let window {
            observedWindow = window
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(visibilityChanged(_:)),
                               name: NSWindow.didChangeOcclusionStateNotification, object: window)
            center.addObserver(self, selector: #selector(visibilityChanged(_:)), name: NSApplication.didHideNotification, object: nil)
            center.addObserver(self, selector: #selector(visibilityChanged(_:)), name: NSApplication.didUnhideNotification, object: nil)
            updateContentsScale()
        }
        updateLayers()
        updateAnimation()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    override func viewDidHide() { super.viewDidHide(); updateAnimation() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateLayers(); updateAnimation() }

    private func stopObservingWindow() {
        guard observedWindow != nil else { return }
        NotificationCenter.default.removeObserver(self)
        observedWindow = nil
    }

    @objc private func visibilityChanged(_ notification: Notification) {
        updateLayers()
        updateAnimation()
    }

    /// The window can show the bar: on screen, not occluded, the app not hidden.
    private var isOnScreen: Bool {
        guard let window, !isHiddenOrHasHiddenAncestor else { return false }
        return window.occlusionState.contains(.visible) && !NSApp.isHidden
    }

    /// Seconds for the head to travel half a point at the current rate (bounded to 1/60…0.5 s).
    private var interval: Double {
        let length = clock?.length.seconds ?? 0
        let speed = Double(max(0, drawingWidth - head.width)) * max(abs(rate), 0.01) / max(length, 1)
        return min(max(0.5 / max(speed, 0.01), 1.0 / 60), 0.5)
    }

    private func updateAnimation() {
        let running = clock?.isRunning ?? false
        let animate = PlayerGeometry.animatesSeek(running: running, barsVisible: visible, hidden: false, pip: false,
                                                  reduceMotion: reduceMotion) && isOnScreen
        guard animate else {
            displayLink?.invalidate(); displayLink = nil
            return
        }
        let rate = Float(min(max(1 / interval, 2), 60))
        let range = CAFrameRateRange(minimum: min(rate, 2), maximum: rate, preferred: rate)
        if let displayLink {
            if displayLink.preferredFrameRateRange != range { displayLink.preferredFrameRateRange = range }
            return
        }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = range
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func step(_ link: CADisplayLink) {
        // The display may tick faster than asked for: move only when the head can move half a point.
        let now = CACurrentMediaTime()
        guard now - lastStep >= interval * 0.9 else { return }
        lastStep = now
        updateLayers()
    }

    // MARK: Layers

    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for layer in [resumeSpanLayer, fillLayer, waveformLayer, playedClipLayer, playedWaveformLayer, resumeMarkerLayer, headLayer] {
            layer.contentsScale = scale
        }
    }

    private func color(_ token: ThemeColor) -> CGColor { token.value(scheme: scheme, accent: accent).cgColor }

    private func applyColors() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        resumeSpanLayer.backgroundColor = color(Theme.Color.bgAccentDark)
        fillLayer.backgroundColor = color(Theme.Color.bgAccentBright)
        waveformLayer.fillColor = color(Theme.Color.fgA4)
        // 4778:26181 / 4767:23726: the 18 played bars are Accent/DIm; only the head is Accent/Main.
        playedWaveformLayer.fillColor = color(Theme.Color.accentDim)
        resumeMarkerLayer.backgroundColor = color(Theme.Color.bgAccentBright)
        headLayer.backgroundColor = color(Theme.Color.accentMain)
        CATransaction.commit()
    }

    private func updateLayers() {
        guard let clock else { return }
        let progress = clock.position(at: CACurrentMediaTime())
        let inset = SeekProgressView.inset
        let travel = max(0, drawingWidth - head.width)
        let x = PlayerGeometry.seekHeadX(progress: progress, width: drawingWidth, headWidth: head.width)
        let y = (bounds.height - head.height) / 2
        // Figma clamps a corner radius to half the shorter side (the 4 pt music head with radius 4 is a
        // pill); a CALayer does not, and draws a notched cap. Clamp like Figma.
        let headRadius = min(head.radius ?? Theme.Radius.md, head.width / 2, head.height / 2)
        // A live stream (or media whose length is not known yet) has no position along the track:
        // no fill and no head at 0, which would read as a zero-length file (VLC Qt hides its slider
        // handle the same way).
        let hasPosition = clock.length > .zero

        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if let resume {
            resumeSpanLayer.isHidden = false
            resumeSpanLayer.frame = CGRect(x: inset, y: y, width: travel * resume + head.width, height: head.height)
            resumeSpanLayer.cornerRadius = headRadius
            resumeMarkerLayer.isHidden = false
            resumeMarkerLayer.frame = CGRect(x: inset + travel * resume, y: y, width: head.width, height: head.height)
            resumeMarkerLayer.cornerRadius = headRadius
        } else {
            resumeSpanLayer.isHidden = true
            resumeMarkerLayer.isHidden = true
        }

        if let samples {
            fillLayer.isHidden = true
            waveformLayer.isHidden = false
            playedClipLayer.isHidden = false
            let rect = bounds.insetBy(dx: MXRPlayerMetrics.waveformInset, dy: Theme.Spacing.gap2)
            let key = WaveformKey(samples: samples, rect: rect,
                                  slot: WaveformShape.slot(forHeadX: x - MXRPlayerMetrics.waveformInset))
            if key != waveformKey {
                waveformKey = key
                let path = WaveformShape(samples: samples, headSlot: key.slot).path(in: rect).cgPath
                waveformLayer.frame = bounds
                waveformLayer.path = path
                playedWaveformLayer.frame = bounds
                playedWaveformLayer.path = path
            }
            // PLAYER-10: the played waveform ends at the head's leading edge.
            playedClipLayer.frame = CGRect(x: 0, y: 0, width: max(0, x), height: bounds.height)
        } else {
            waveformKey = nil
            waveformLayer.isHidden = true
            playedClipLayer.isHidden = true
            fillLayer.isHidden = !hasPosition
            fillLayer.frame = CGRect(x: inset, y: y, width: travel * progress + head.width, height: head.height)
            fillLayer.cornerRadius = min(Theme.Metric.ControlBar.seekFill.radius ?? Theme.Radius.md,
                                         fillLayer.frame.width / 2, fillLayer.frame.height / 2)
        }

        headLayer.isHidden = !hasPosition
        headLayer.frame = CGRect(x: x, y: y, width: head.width, height: head.height)
        headLayer.cornerRadius = headRadius
    }

    override func layout() {
        super.layout()
        waveformKey = nil
        updateLayers()
    }

    private struct WaveformKey: Equatable {
        let samples: WaveformSamples
        let rect: CGRect
        let slot: Int
    }
}
