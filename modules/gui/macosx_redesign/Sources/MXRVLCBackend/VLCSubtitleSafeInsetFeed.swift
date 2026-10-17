// Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later.
import AppKit
import MXRCore

/// Keeps VLC's subtitle safe inset (``PlayerBackend/setSubtitleSafeInset(points:backingScale:)``)
/// in step with the video view. The inset depends on what covers the picture (``covered``, from
/// the window composition), on the picture's letterbox inside the view (its size and the video
/// size) and on the backing scale, since VLC's "sub-margin" counts output pixels. The view's size
/// and the window's backing scale are not observable values, so the feed watches AppKit for them:
/// a resize, a move to a screen with another scale, or a colour-space/backing change re-sends.
@MainActor
public final class SubtitleSafeInsetFeed {
    private weak var view: NSView?
    private let send: @MainActor (_ points: Double, _ backingScale: Double) -> Void
    private let backingScale: @MainActor (NSView) -> Double
    private var observers: [NSObjectProtocol] = []
    private var covered = 0.0
    private var videoSize: CGSize?
    private var sent: (points: Double, scale: Double)?

    /// `backingScale` reads the view's window by default; tests pass their own.
    public init(view: NSView,
                backingScale: @escaping @MainActor (NSView) -> Double = SubtitleSafeInsetFeed.windowBackingScale,
                send: @escaping @MainActor (_ points: Double, _ backingScale: Double) -> Void) {
        self.view = view
        self.send = send
        self.backingScale = backingScale
        view.postsFrameChangedNotifications = true
        let refresh: @Sendable (Notification) -> Void = { [weak self] note in
            let window = (note.object as? NSWindow).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let view = self.view else { return }
                // Window notifications are watched for every window; only the video view's counts.
                if let window, window != view.window.map(ObjectIdentifier.init) { return }
                self.refresh()
            }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main, using: refresh))
        for name in [NSWindow.didChangeBackingPropertiesNotification, NSWindow.didChangeScreenNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main, using: refresh))
        }
    }

    public static func windowBackingScale(_ view: NSView) -> Double {
        Double(view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
    }

    /// Points the overlays cover at the bottom of the video view (0 when nothing covers), and
    /// the size of the video's picture when known.
    public func update(covered: Double, videoSize: CGSize?) {
        self.covered = covered
        self.videoSize = videoSize
        refresh()
    }

    /// Sends the inset again if the geometry or the scale changed since the last send.
    public func refresh() {
        guard let view else { return }
        let bounds = view.bounds
        // The fitted picture is centred, so it is the same in the helper's y-down space.
        let picture = videoSize.map { SubtitleSafeInset.fittedPicture(videoSize: $0, in: bounds) } ?? bounds
        let band = CGRect(x: bounds.minX, y: bounds.height - covered, width: bounds.width, height: covered)
        let points = covered > 0 ? SubtitleSafeInset.points(picture: picture, overlays: [band]) : 0
        let scale = backingScale(view)
        if let sent, sent.points == points, sent.scale == scale { return }
        sent = (points, scale)
        send(points, scale)
    }

    public func invalidate() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
}
