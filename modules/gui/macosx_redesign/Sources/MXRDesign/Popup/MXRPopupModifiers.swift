import AppKit
import SwiftUI

extension View {
    /// Presents a design-system menu (D025) anchored to this view while `isPresented` is true.
    ///
    /// ```swift
    /// MXRPlayerIconButton(.more, …) { open.toggle() }
    ///     .mxrPopupMenu(isPresented: $open, style: .appMenu) { appMenuItems() }
    /// ```
    ///
    /// The card follows `style` (Figma `menu`, `context menu`, …), drops under the view (flipping
    /// above near the screen bottom), opens submenus beside it, and closes on choice, Esc or a
    /// click outside, resetting `isPresented`.
    public func mxrPopupMenu(isPresented: Binding<Bool>, placement: MXRPopupPlacement = .below(),
                             style: MXRPopupStyle = .contextMenu, width: CGFloat? = nil,
                             @MXRMenuBuilder items: @escaping @MainActor () -> [MXRMenuItem]) -> some View {
        modifier(MXRPopupModifier(isPresented: isPresented, placement: placement, style: style, width: width,
                                  surface: true, content: { .menu(items) }))
    }

    /// Presents custom content in a design-system popup anchored to this view: same window,
    /// motion and dismissal as menus, no arrow. With a `surface` style the content is padded and
    /// drawn on that card; pass `nil` when the content draws its own card. Close it from inside
    /// with `@Environment(\.mxrDismissPopup)`.
    public func mxrPopup<Content: View>(isPresented: Binding<Bool>, placement: MXRPopupPlacement = .below(),
                                        surface: MXRPopupStyle? = .contextMenu,
                                        @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(MXRPopupModifier(isPresented: isPresented, placement: placement, style: surface ?? .contextMenu,
                                  width: nil, surface: surface != nil, content: { .custom(AnyView(content())) }))
    }

    /// A design-system context menu (D025) opened by a secondary click (or Control-click) on this
    /// view, at the pointer.
    public func mxrContextMenu(style: MXRPopupStyle = .contextMenu, width: CGFloat? = nil,
                               @MXRMenuBuilder items: @escaping @MainActor () -> [MXRMenuItem]) -> some View {
        modifier(MXRContextMenuModifier(style: style, width: width, items: items))
    }
}

/// Reads the anchor view's place on screen and owns the open popup.
@MainActor
final class MXRPopupAnchor {
    weak var view: NSView?
    private(set) var session: MXRPopupSession?

    var screenRect: CGRect? {
        guard let view, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }

    func present(_ content: MXRPopupContent, placement: MXRPopupPlacement, at point: CGPoint? = nil,
                 style: MXRPopupStyle, width: CGFloat?, matchesAnchorWidth: Bool = false, surface: Bool,
                 environment: MXRPopupEnvironment, owner: MXRPopupOwner? = nil,
                 onDismiss: @escaping @MainActor () -> Void) {
        guard let window = view?.window, let anchor = point.map({ CGRect(origin: $0, size: .zero) }) ?? screenRect else {
            onDismiss()
            return
        }
        let width = matchesAnchorWidth ? anchor.width : width
        let placement = placement.resolved(anchor: anchor, window: window.frame)
        session?.dismiss(animated: false)
        let session = MXRPopupSession(parentWindow: window, environment: environment, isAnchored: point == nil,
                                      owner: owner, onDismiss: { [weak self] in
                                          self?.session = nil
                                          onDismiss()
                                      })
        self.session = session
        session.present(content, style: style, width: width, surface: surface, placement: placement, anchor: anchor)
    }

    func dismiss(animated: Bool = true) {
        session?.dismiss(animated: animated)
        session = nil
    }
}

struct MXRPopupModifier: ViewModifier {
    @Binding var isPresented: Bool
    let placement: MXRPopupPlacement
    let style: MXRPopupStyle
    let width: CGFloat?
    var matchesAnchorWidth = false
    let surface: Bool
    let content: @MainActor () -> MXRPopupContent
    @State private var anchor = MXRPopupAnchor()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.mxrAccent) private var accent
    @Environment(\.mxrThemeMode) private var themeMode
    @Environment(\.mxrNativeBackdropEnabled) private var backdropEnabled
    @Environment(\.mxrPopupOwner) private var owner

    func body(content view: Content) -> some View {
        view
            .background(MXRPopupAnchorRepresentable(anchor: anchor))
            .onChange(of: isPresented, initial: true) { _, presented in
                if presented {
                    anchor.present(content(), placement: placement, style: style, width: width,
                                   matchesAnchorWidth: matchesAnchorWidth, surface: surface,
                                   environment: MXRPopupEnvironment(colorScheme: colorScheme, accent: accent,
                                                                    themeMode: themeMode, backdropEnabled: backdropEnabled),
                                   owner: owner, onDismiss: { isPresented = false })
                } else {
                    anchor.dismiss()
                }
            }
            .onDisappear { anchor.dismiss(animated: false) }
    }
}

private struct MXRContextMenuModifier: ViewModifier {
    let style: MXRPopupStyle
    let width: CGFloat?
    let items: @MainActor () -> [MXRMenuItem]
    @State private var anchor = MXRPopupAnchor()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.mxrAccent) private var accent
    @Environment(\.mxrThemeMode) private var themeMode
    @Environment(\.mxrNativeBackdropEnabled) private var backdropEnabled

    func body(content: Content) -> some View {
        let environment = MXRPopupEnvironment(colorScheme: colorScheme, accent: accent, themeMode: themeMode,
                                              backdropEnabled: backdropEnabled)
        content
            .overlay {
                MXRContextClickRepresentable(anchor: anchor) { [anchor, style, width, items] point in
                    // Like NSMenu, a context menu with no rows does not open.
                    guard !items().isEmpty else { return }
                    anchor.present(.menu(items), placement: .pointer(point), at: point, style: style, width: width,
                                   surface: true, environment: environment, onDismiss: {})
                }
            }
            .onDisappear { anchor.dismiss(animated: false) }
    }
}

// MARK: - AppKit anchors

private struct MXRPopupAnchorRepresentable: NSViewRepresentable {
    let anchor: MXRPopupAnchor

    func makeNSView(context: Context) -> MXRPassThroughView {
        let view = MXRPassThroughView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: MXRPassThroughView, context: Context) { anchor.view = view }
}

/// Marks the anchor's frame; never takes events.
final class MXRPassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func accessibilityIsIgnored() -> Bool { true }
}

private struct MXRContextClickRepresentable: NSViewRepresentable {
    let anchor: MXRPopupAnchor
    let onContextClick: @MainActor (CGPoint) -> Void

    func makeNSView(context: Context) -> MXRContextClickView {
        let view = MXRContextClickView()
        anchor.view = view
        view.onContextClick = onContextClick
        return view
    }

    func updateNSView(_ view: MXRContextClickView, context: Context) {
        anchor.view = view
        view.onContextClick = onContextClick
    }
}

/// Takes only secondary clicks (right click, Control-click); every other event reaches the views
/// below, so the video keeps its click, double-click and drag behaviour.
final class MXRContextClickView: NSView {
    var onContextClick: (@MainActor (CGPoint) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent, Self.isContextClick(event) else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityIsIgnored() -> Bool { true }

    override func rightMouseDown(with event: NSEvent) { open(event) }

    override func mouseDown(with event: NSEvent) {
        if Self.isContextClick(event) { open(event) } else { super.mouseDown(with: event) }
    }

    override func menu(for event: NSEvent) -> NSMenu? { nil }

    private func open(_ event: NSEvent) {
        guard let window else { return }
        onContextClick?(window.convertPoint(toScreen: event.locationInWindow))
    }

    static func isContextClick(_ event: NSEvent) -> Bool {
        event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
    }
}
