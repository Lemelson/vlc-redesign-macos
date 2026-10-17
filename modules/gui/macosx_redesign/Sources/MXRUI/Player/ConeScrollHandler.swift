import AppKit
import MXRCore
import SwiftUI

extension View {
    /// Wheel and trackpad scrolling over this view adjust the volume (S04). Pure SwiftUI: the pointer
    /// position comes from hover tracking and one local monitor consumes only wheel events while the
    /// pointer is over the view, so there is no AppKit view in the tree (the image-engine gallery
    /// renders the cone as it ships, B-02). The gesture follows the same direction as the video
    /// surface: natural scrolling and the "reverse-scroll" preference each invert it once (B-03).
    func mxrConeScroll(enabled: Bool, reversed: @escaping @MainActor () -> Bool,
                       adjust: @escaping @MainActor (Int) -> Void) -> some View {
        modifier(ConeScrollModifier(enabled: enabled, reversed: reversed, adjust: adjust))
    }
}

private struct ConeScrollModifier: ViewModifier {
    let enabled: Bool
    let reversed: @MainActor () -> Bool
    let adjust: @MainActor (Int) -> Void
    @State private var monitor = ConeScrollMonitor()

    func body(content: Content) -> some View {
        content
            .onHover { monitor.hovered = $0 }
            .onAppear {
                // The closures read the app model at event time; they need no refresh.
                monitor.reversed = reversed
                monitor.adjust = adjust
                monitor.install()
            }
            .onDisappear { monitor.remove() }
            .onChange(of: enabled, initial: true) { _, value in monitor.enabled = value }
    }
}

/// Owns the local wheel monitor of one cone. Events pass through unless the pointer is over the cone
/// and scrolling it is enabled.
@MainActor final class ConeScrollMonitor {
    var hovered = false { didSet { if !hovered { input.reset() } } }
    var enabled = false { didSet { if !enabled { input.reset() } } }
    var reversed: @MainActor () -> Bool = { false }
    var adjust: @MainActor (Int) -> Void = { _ in }
    private var input = ConeScrollInput()
    private var token: Any?

    func install() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
        input.reset()
    }

    func handle(_ event: NSEvent) -> Bool {
        guard hovered else { return false }
        return input.handle(delta: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                            natural: event.isDirectionInvertedFromDevice, reversed: reversed(), enabled: enabled,
                            ended: event.phase == .ended || event.phase == .cancelled,
                            adjust: adjust)
    }
}

/// The same routing predicate is used for monitor input and its modal-isolation tests.
@MainActor enum ConeScrollAvailability {
    static func isEnabled(in app: AppModel) -> Bool {
        app.canPerform(.volumeUp) && app.interface.isControlBarVisible && !app.interface.isUIHidden
            && !app.interface.isCustomizing && app.interface.library != .full && !app.player.isPictureInPicture
    }

    /// The "Reverse scroll direction" preference shared with the video surface (MXRNativePreferences).
    static func isReversed(in app: AppModel) -> Bool {
        app.settings.backend.value(for: "macosx-redesign-reverse-scroll")?.boolValue ?? false
    }
}

struct ConeScrollInput {
    private var remainder: CGFloat = 0
    mutating func reset() { remainder = 0 }
    /// Disabled input passes through and cannot leave partial motion for a later surface.
    /// `natural` is the device's natural-scrolling inversion and `reversed` the user's preference:
    /// each flips the physical gesture once, like ``MXRVideoScrollAccumulator`` on the video, so the
    /// same swipe makes the volume louder over the cone and over the picture.
    mutating func handle(delta: CGFloat, precise: Bool, natural: Bool = false, reversed: Bool = false,
                         enabled: Bool, ended: Bool, adjust: (Int) -> Void) -> Bool {
        guard enabled else { reset(); return false }
        let direction: CGFloat = (natural ? -1 : 1) * (reversed ? -1 : 1)
        remainder += (precise ? delta / 10 : delta) * direction
        let steps = Int(remainder)
        if steps != 0 { remainder -= CGFloat(steps); adjust(steps) }
        if ended { reset() }
        return true
    }
}
