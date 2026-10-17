import AppKit
import MXRBridgeAPI
import MXRCore
import SwiftUI

/// One native container survives player/library presentation changes. VLC owns
/// every child of `surface`; SwiftUI controls remain outside that surface.
@MainActor
final class MXRVideoHostView: NSView {
    let surface: NSView
    var onToggleFullscreen: (() -> Void)?
    var onMagnifyFullscreen: ((Bool?) -> Void)?
    private var magnification = MXRFullscreenMagnification()
    var onSingleClick: (() -> Void)?
    /// Read live so changing the mouse preference affects the next click.
    var doubleClickActionEnabled: (() -> Bool)?
    /// Runs first on every click; returns true when the click only closed a popup (D024).
    var onMouseDown: (() -> Bool)?
    var onScroll: ((NSEvent) -> Bool)?
    var onOpenURLs: (([URL]) -> Void)?
    private var clickTask: Task<Void, Never>?

    init(surface: NSView) {
        self.surface = surface
        super.init(frame: surface.frame)
        surface.frame = bounds
        surface.autoresizingMask = [.width, .height]
        addSubview(surface)
        registerForDraggedTypes([.fileURL, .URL])
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        fitSurface()
    }

    // R10: keep the vout surface on the host's bounds whenever the host moves or resizes, not only
    // on the next layout pass, so the picture never keeps a stale frame after a composition change.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fitSurface()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        fitSurface()
    }

    private func fitSurface() {
        // During PiP the same surface belongs to the system controller.
        if surface.superview === self, surface.frame != bounds { surface.frame = bounds }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        clickTask?.cancel()
        if event.clickCount == 1, onMouseDown?() == true { return }
        if event.clickCount >= 2 { onToggleFullscreen?() }
        else if onSingleClick != nil {
            let delay = VideoClickTiming.singleClickDelay(doubleClickEnabled: doubleClickActionEnabled?() ?? true,
                                                         systemInterval: NSEvent.doubleClickInterval)
            if delay == 0 { onSingleClick?(); return }
            clickTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.onSingleClick?()
            }
        } else { super.mouseDown(with: event) }
    }

    override func beginGesture(with event: NSEvent) {
        magnification.begin()
        super.beginGesture(with: event)
    }

    override func magnify(with event: NSEvent) {
        if event.phase == .began { magnification.begin() }
        if let fullscreen = magnification.consume(Double(event.magnification)) {
            onMagnifyFullscreen?(fullscreen)
        }
    }

    override func smartMagnify(with event: NSEvent) { onMagnifyFullscreen?(nil) }

    override func scrollWheel(with event: NSEvent) {
        if onScroll?(event) != true { super.scrollWheel(with: event) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { clickTask?.cancel() }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty else { return false }
        onOpenURLs?(urls)
        return true
    }
}

struct MXRNativeVideoView: NSViewRepresentable {
    let host: MXRVideoHostView
    func makeNSView(context: Context) -> MXRVideoHostView { host }
    func updateNSView(_ nsView: MXRVideoHostView, context: Context) {}
}

/// While VLC takes the pointer (DVD menu, mouse video filter), the surface asks before routing
/// a click: one that only closes a popup never reaches the title (D024, C-06).
extension MXRVideoHostView: MXRVideoSurfaceHost {
    func videoSurfaceClickClosesPopup() -> Bool { onMouseDown?() == true }
}
