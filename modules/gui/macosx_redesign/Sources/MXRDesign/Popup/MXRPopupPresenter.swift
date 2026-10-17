import AppKit
import Observation
import SwiftUI

/// The one popup presentation of the app (D024, D025): a borderless panel per menu level, child of
/// the anchor's window, with the Figma card drawn by SwiftUI.
///
/// - Opens with a fade and a 6 pt slide from the anchor (0.15 s ease-out), closes with a 0.1 s
///   fade; no motion under Reduce Motion.
/// - Closes on Esc, on a click outside (that click is consumed, so it never also toggles playback),
///   when the app deactivates and when the anchor's window moves, resizes or closes.
/// - Menus: ↑↓ move, → / Return open a submenu, ← closes it, Return or Space choose, typing
///   selects by title; submenus open on hover after ``Theme/Popup/submenuHoverDelay``.
/// - Only one popup tree is open at a time.
@MainActor
@Observable
public final class MXRPopupCenter {
    public static let shared = MXRPopupCenter()

    /// A popup is open.
    public private(set) var isPresenting = false
    /// A popup anchored to a view (a menu dropping from a bar button, a dropdown) is open.
    public private(set) var isPresentingAnchored = false
    /// The ``MXRPopupOwner`` of the open anchored popup: the part of the window it drops from
    /// (``View/mxrPopupOwner(_:)``). The host keeps that part, and only that part, shown while the
    /// popup is open (D023); context menus at the pointer have no owner.
    public private(set) var anchoredOwner: MXRPopupOwner?

    @ObservationIgnored private var session: MXRPopupSession?

    private init() {}

    /// Closes any open popup.
    public func dismissAll(animated: Bool = true) {
        session?.dismiss(animated: animated)
    }

    func begin(_ new: MXRPopupSession) {
        if let session, session !== new { session.dismiss(animated: false) }
        session = new
        isPresenting = true
        isPresentingAnchored = new.isAnchored
        anchoredOwner = new.isAnchored ? new.owner : nil
    }

    func ended(_ old: MXRPopupSession) {
        guard session === old else { return }
        session = nil
        isPresenting = false
        isPresentingAnchored = false
        anchoredOwner = nil
    }
}

/// Names the part of a window that popups anchored inside it belong to (a bar, a panel). Set it
/// with ``SwiftUI/View/mxrPopupOwner(_:)``; read it from ``MXRPopupCenter/anchoredOwner``.
public struct MXRPopupOwner: Hashable, Sendable {
    public let id: String
    public init(_ id: String) { self.id = id }
}

private struct MXRPopupOwnerKey: EnvironmentKey {
    static let defaultValue: MXRPopupOwner? = nil
}

extension EnvironmentValues {
    /// The owner recorded for popups anchored in this view (nil: none).
    public var mxrPopupOwner: MXRPopupOwner? {
        get { self[MXRPopupOwnerKey.self] }
        set { self[MXRPopupOwnerKey.self] = newValue }
    }
}

extension View {
    /// Popups anchored inside this view belong to `owner` while they are open.
    public func mxrPopupOwner(_ owner: MXRPopupOwner?) -> some View {
        environment(\.mxrPopupOwner, owner)
    }
}

/// What a popup level shows.
enum MXRPopupContent {
    case menu(@MainActor () -> [MXRMenuItem])
    case custom(AnyView)
}

/// Environment carried from the anchor into the popup window.
struct MXRPopupEnvironment {
    var colorScheme: ColorScheme
    var accent: Theme.Accent
    var themeMode: Theme.Mode
    var backdropEnabled: Bool
}

/// Appearance phase of one popup level, animated by SwiftUI.
@MainActor
@Observable
final class MXRPopupPhase {
    var arrived = false
    var visible = false
    var slide: MXRPopupSlide = .down
    var animates = true
    /// Height of the scrolling row area when the menu is taller than the screen.
    var scrollHeight: CGFloat?
}

// MARK: - Session

@MainActor
final class MXRPopupSession {
    let isAnchored: Bool
    let owner: MXRPopupOwner?
    private weak var parentWindow: NSWindow?
    private let environment: MXRPopupEnvironment
    private var levels: [MXRPopupLevel] = []
    private var onDismiss: (@MainActor () -> Void)?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var hoverWork: DispatchWorkItem?
    private var typeSelectPrefix = ""
    private var typeSelectTime = Date.distantPast
    private(set) var isDismissing = false

    init(parentWindow: NSWindow, environment: MXRPopupEnvironment, isAnchored: Bool, owner: MXRPopupOwner? = nil,
         onDismiss: (@MainActor () -> Void)?) {
        self.parentWindow = parentWindow
        self.environment = environment
        self.isAnchored = isAnchored
        self.owner = owner
        self.onDismiss = onDismiss
    }

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Shows the root level.
    func present(_ content: MXRPopupContent, style: MXRPopupStyle, width: CGFloat?, surface: Bool,
                 placement: MXRPopupPlacement, anchor: CGRect) {
        guard let parentWindow else { return }
        MXRPopupCenter.shared.begin(self)
        let level = MXRPopupLevel(session: self, content: content, style: style, width: width ?? style.width,
                                  surface: surface, environment: environment)
        levels = [level]
        level.show(in: parentWindow, placement: placement, anchor: anchor, makeKey: true)
        installMonitors()
    }

    // MARK: Dismissal

    func dismiss(animated: Bool, then action: (@MainActor () -> Void)? = nil) {
        guard !isDismissing else { return }
        isDismissing = true
        hoverWork?.cancel()
        removeMonitors()
        if levels.contains(where: { $0.panel.isKeyWindow }), let parentWindow, parentWindow.isVisible {
            parentWindow.makeKey()
        }
        let animate = animated && !Self.reduceMotion
        for level in levels { level.hide(animated: animate) }
        levels.removeAll()
        let finish = onDismiss
        onDismiss = nil
        finish?()
        MXRPopupCenter.shared.ended(self)
        guard let action else { return }
        if animate {
            DispatchQueue.main.asyncAfter(deadline: .now() + Theme.Popup.disappearDuration) { MainActor.assumeIsolated { action() } }
        } else {
            action()
        }
    }

    private func installMonitors() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleMouseDown(event)
        }
        let center = NotificationCenter.default
        let dismissNow: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(animated: false) }
        }
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil,
                                            queue: .main, using: dismissNow))
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.willCloseNotification,
                     NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification,
                     NSWindow.didMiniaturizeNotification] {
            observers.append(center.addObserver(forName: name, object: parentWindow, queue: .main, using: dismissNow))
        }
        if let root = levels.first?.panel {
            observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: root, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.isDismissing else { return }
                    // Another of our windows (a sheet, a dialog) took the keyboard: close like NSMenu.
                    if !self.levels.contains(where: { $0.panel.isKeyWindow }) { self.dismiss(animated: false) }
                }
            })
        }
    }

    private func removeMonitors() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    /// Clicks inside a card pass; any other click closes the popup and is consumed (D024), except a
    /// secondary click, which may open the next context menu where it lands.
    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        if let window = event.window, let level = levels.first(where: { $0.panel === window }) {
            let point = window.convertPoint(toScreen: event.locationInWindow)
            if level.cardFrame.contains(point) { return event }
        }
        let secondary = event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        dismiss(animated: true)
        return secondary ? event : nil
    }

    // MARK: Pointer

    func hover(_ level: MXRPopupLevel, row: Int?) {
        guard !isDismissing, let depth = levels.firstIndex(where: { $0 === level }) else { return }
        let items = level.items
        // Entering a submenu keeps its parent row highlighted and cancels a pending switch.
        if depth > 0 {
            hoverWork?.cancel()
            let parent = levels[depth - 1]
            parent.tracking.highlighted = parent.tracking.expanded
        }
        guard let row, items.indices.contains(row), items[row].isSelectable else {
            // Leaving the card or crossing a separator or disabled row: the row with an open
            // submenu stays highlighted.
            level.tracking.highlighted = level.tracking.expanded
            return
        }
        level.tracking.highlighted = row
        hoverWork?.cancel()
        // Back on the row whose submenu is open: keep it.
        guard level.tracking.expanded != row else { return }
        let work = DispatchWorkItem { [weak self, weak level] in
            MainActor.assumeIsolated {
                guard let self, let level, !self.isDismissing, level.tracking.highlighted == row,
                      let depth = self.levels.firstIndex(where: { $0 === level }) else { return }
                let items = level.items
                guard items.indices.contains(row) else { return }
                if items[row].isSubmenu { self.openSubmenu(of: level, row: row, highlightFirst: false) }
                else { self.closeLevels(after: depth) }
            }
        }
        hoverWork = work
        let hasSubmenu = items[row].isSubmenu || level.tracking.expanded != nil
        if hasSubmenu {
            DispatchQueue.main.asyncAfter(deadline: .now() + Theme.Popup.submenuHoverDelay, execute: work)
        }
    }

    func activate(_ level: MXRPopupLevel, row: Int, viaKeyboard: Bool = false) {
        guard !isDismissing else { return }
        let items = level.items
        guard items.indices.contains(row), items[row].isSelectable else { return }
        switch items[row].kind {
        case .submenu:
            hoverWork?.cancel()
            openSubmenu(of: level, row: row, highlightFirst: viaKeyboard)
        case .action(let action):
            dismiss(animated: true, then: action)
        case .separator:
            break
        }
    }

    func openAccessory(_ level: MXRPopupLevel, row: Int) {
        guard !isDismissing else { return }
        let items = level.items
        guard items.indices.contains(row), let actions = items[row].actions else { return }
        hoverWork?.cancel()
        openLevel(of: level, row: row, content: .menu(actions), highlightFirst: false)
    }

    private func openSubmenu(of level: MXRPopupLevel, row: Int, highlightFirst: Bool) {
        let items = level.items
        guard items.indices.contains(row), case .submenu(let children) = items[row].kind else { return }
        if level.tracking.expanded != row { items[row].onOpen?() }
        openLevel(of: level, row: row, content: .menu(children), highlightFirst: highlightFirst)
    }

    private func openLevel(of level: MXRPopupLevel, row: Int, content: MXRPopupContent, highlightFirst: Bool) {
        guard let depth = levels.firstIndex(where: { $0 === level }), let parentWindow else { return }
        if level.tracking.expanded == row, levels.count > depth + 1 {
            if highlightFirst, let child = levels.last { child.tracking.highlighted = child.firstSelectable }
            return
        }
        closeLevels(after: depth)
        level.tracking.expanded = row
        level.tracking.highlighted = row
        let style = MXRPopupStyle.contextMenu
        let child = MXRPopupLevel(session: self, content: content, style: style, width: style.width,
                                  surface: true, environment: environment)
        levels.append(child)
        let placement = MXRPopupPlacement.beside(row: level.rowFrame(row), parentCard: level.cardFrame,
                                                 topInset: style.padding.top)
        child.show(in: parentWindow, placement: placement, anchor: level.rowFrame(row), makeKey: false)
        if highlightFirst { child.tracking.highlighted = child.firstSelectable }
    }

    /// The level open beside `row` of `level`, if that row's submenu is open.
    func child(of level: MXRPopupLevel, row: Int) -> MXRPopupLevel? {
        guard let depth = levels.firstIndex(where: { $0 === level }), level.tracking.expanded == row,
              levels.count > depth + 1 else { return nil }
        return levels[depth + 1]
    }

    private func closeLevels(after depth: Int) {
        guard levels.count > depth + 1 else { return }
        for level in levels[(depth + 1)...] { level.hide(animated: !Self.reduceMotion) }
        levels.removeSubrange((depth + 1)...)
        levels[depth].tracking.expanded = nil
    }

    // MARK: Keyboard

    /// Keys typed while the popup has the keyboard. Returns true when handled.
    func handleKey(_ event: NSEvent) -> Bool {
        guard !isDismissing, event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 { dismiss(animated: true); return true } // Esc
        // Custom content (text fields, lists) handles its own keys, including ⌘C/⌘V.
        guard let active = keyboardLevel, case .menu = active.content else { return false }
        if flags.contains(.command) {
            // App commands (⌘O, ⌘,) run from the menu bar after the menu closes, like NSMenu.
            dismiss(animated: false)
            return false
        }
        let items = active.items
        switch event.keyCode {
        case 125: move(active, by: 1); return true            // ↓
        case 126: move(active, by: -1); return true           // ↑
        case 115: active.tracking.highlighted = active.firstSelectable; return true // Home
        case 119: active.tracking.highlighted = items.indices.last { items[$0].isSelectable }; return true // End
        case 124:                                              // →
            if let row = active.tracking.highlighted, items.indices.contains(row), items[row].isSubmenu {
                activate(active, row: row, viaKeyboard: true)
            }
            return true
        case 123:                                              // ←
            if let depth = levels.firstIndex(where: { $0 === active }), depth > 0 {
                closeLevels(after: depth - 1)
            }
            return true
        case 36, 76, 49:                                       // Return, Enter, Space
            if let row = active.tracking.highlighted { activate(active, row: row, viaKeyboard: true) }
            return true
        default:
            guard flags.isSubset(of: [.shift, .capsLock]), let typed = event.characters, !typed.isEmpty,
                  typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return false }
            typeSelect(typed, in: active)
            return true
        }
    }

    /// The deepest level the keyboard is in: the last level with a highlighted row.
    private var keyboardLevel: MXRPopupLevel? {
        levels.last { $0.tracking.highlighted != nil && $0.tracking.highlighted != $0.tracking.expanded } ?? levels.first
    }

    private func move(_ level: MXRPopupLevel, by step: Int) {
        let items = level.items
        let selectable = items.indices.filter { items[$0].isSelectable }
        guard !selectable.isEmpty else { return }
        if let depth = levels.firstIndex(where: { $0 === level }) { closeLevels(after: depth) }
        guard let current = level.tracking.highlighted, let position = selectable.firstIndex(of: current) else {
            level.tracking.highlighted = step > 0 ? selectable.first : selectable.last
            return
        }
        let next = min(max(position + step, 0), selectable.count - 1)
        level.tracking.highlighted = selectable[next]
    }

    private func typeSelect(_ typed: String, in level: MXRPopupLevel) {
        let now = Date()
        typeSelectPrefix = now.timeIntervalSince(typeSelectTime) > Theme.Popup.typeSelectTimeout
            ? typed.lowercased() : typeSelectPrefix + typed.lowercased()
        typeSelectTime = now
        let items = level.items
        if let match = items.indices.first(where: { items[$0].isSelectable && items[$0].title.lowercased().hasPrefix(typeSelectPrefix) }) {
            level.tracking.highlighted = match
        }
    }
}

// MARK: - Level

@MainActor
final class MXRPopupLevel {
    let content: MXRPopupContent
    let style: MXRPopupStyle
    let width: CGFloat
    let tracking = MXRMenuTracking()
    let phase = MXRPopupPhase()
    let panel = MXRPopupPanel()
    private(set) var cardFrame: CGRect = .zero
    private weak var session: MXRPopupSession?
    private var placement: MXRPopupPlacement = .below()
    private var anchor: CGRect = .zero
    private weak var parentWindow: NSWindow?
    private var hosting: MXRPopupHostingView?

    init(session: MXRPopupSession, content: MXRPopupContent, style: MXRPopupStyle, width: CGFloat, surface: Bool,
         environment: MXRPopupEnvironment) {
        self.session = session
        self.content = content
        self.style = style
        self.width = width
        let root = MXRPopupLevelView(level: self, surface: surface)
            .environment(\.colorScheme, environment.colorScheme)
            .environment(\.mxrThemeMode, environment.themeMode)
            .mxrAccent(environment.accent)
            .mxrNativeBackdropEnabled(environment.backdropEnabled)
            .environment(\.mxrPopupInOwnWindow, true)
            .environment(\.mxrDismissPopup, MXRDismissPopupAction { [weak session] in session?.dismiss(animated: true) })
        let hosting = MXRPopupHostingView(rootView: AnyView(root))
        hosting.onContentSizeChange = { [weak self] in
            guard let self, let hosting = self.hosting else { return }
            // Re-place only when the card's size really changed (items added or removed).
            let margin = style.outerMargin
            let size = hosting.fittingSize
            if abs(size.width - margin * 2 - cardFrame.width) > 0.5 || abs(size.height - margin * 2 - cardFrame.height) > 0.5,
               phase.scrollHeight == nil {
                refit()
            }
        }
        self.hosting = hosting
        if case .menu = content {
            hosting.menuLevel = self
            tracking.onHighlight = { [weak self] row in self?.announceHighlight(row) }
        }
        panel.contentView = hosting
        panel.appearance = NSAppearance(named: environment.colorScheme == .dark ? .darkAqua : .aqua)
        panel.keyHandler = { [weak session] event in session?.handleKey(event) ?? false }
        panel.onCancel = { [weak session] in session?.dismiss(animated: true) }
    }

    var items: [MXRMenuItem] {
        if case .menu(let provider) = content { provider() } else { [] }
    }

    var firstSelectable: Int? { items.firstIndex(where: \.isSelectable) }

    // MARK: Accessibility (PLAYER-07)

    private var accessibilityRows: [Int: MXRMenuAccessibilityItem] = [:]

    /// The `AXMenu` of this level (its hosting view), nil for custom content.
    var accessibilityMenu: NSView? { hosting?.menuLevel === self ? hosting : nil }

    /// The `AXMenuItem` children, one per non-separator row, reused while the rows stay.
    func accessibilityItems() -> [MXRMenuAccessibilityItem] {
        let items = items
        accessibilityRows = accessibilityRows.filter { items.indices.contains($0.key) }
        return items.indices.compactMap { row in
            guard !items[row].isSeparator else { accessibilityRows[row] = nil; return nil }
            let element = accessibilityRows[row] ?? MXRMenuAccessibilityItem(level: self, row: row, item: items[row])
            accessibilityRows[row] = element
            element.update(items[row], parent: accessibilityMenu, submenu: openChild(of: row)?.accessibilityMenu)
            return element
        }
    }

    func openChild(of row: Int) -> MXRPopupLevel? { session?.child(of: self, row: row) }

    /// Keyboard and pointer highlight moves VoiceOver's cursor like NSMenu's selection.
    private func announceHighlight(_ row: Int?) {
        guard let hosting, hosting.window != nil, let row else { return }
        guard let element = accessibilityItems().first(where: { $0.row == row }) else { return }
        NSAccessibility.post(element: hosting, notification: .selectedChildrenChanged)
        NSAccessibility.post(element: element, notification: .focusedUIElementChanged)
    }

    /// The row's frame on screen, from the Figma row heights.
    func rowFrame(_ row: Int) -> CGRect {
        let top = style.rowTop(row, in: items)
        return CGRect(x: cardFrame.minX + style.padding.leading, y: cardFrame.maxY - top - style.row.height,
                      width: cardFrame.width - style.padding.horizontal, height: style.row.height)
    }

    func show(in parent: NSWindow, placement: MXRPopupPlacement, anchor: CGRect, makeKey: Bool) {
        self.placement = placement
        self.anchor = anchor
        parentWindow = parent
        phase.animates = !MXRPopupSession.reduceMotion
        refit()
        panel.acceptsKey = makeKey
        parent.addChildWindow(panel, ordered: .above)
        panel.level = .popUpMenu
        if makeKey { panel.makeKeyAndOrderFront(nil) } else { panel.orderFront(nil) }
        if !phase.animates { phase.arrived = true; phase.visible = true }
        if let menu = accessibilityMenu { NSAccessibility.post(element: menu, notification: NSAccessibility.Notification(rawValue: "AXMenuOpened")) }
    }

    func hide(animated: Bool) {
        let panel = panel
        if let menu = accessibilityMenu { NSAccessibility.post(element: menu, notification: NSAccessibility.Notification(rawValue: "AXMenuClosed")) }
        tracking.onHighlight = nil
        let close = {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            panel.contentView = nil
        }
        guard animated, phase.visible else { close(); return }
        withAnimation(.easeOut(duration: Theme.Popup.disappearDuration)) { phase.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + Theme.Popup.disappearDuration) { MainActor.assumeIsolated { close() } }
    }

    /// Sizes the card from its content and places it on the anchor's screen.
    private func refit() {
        guard let hosting else { return }
        let margin = style.outerMargin
        phase.scrollHeight = nil
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        size.width -= margin * 2
        size.height -= margin * 2
        let screen = Self.screen(containing: anchor) ?? parentWindow?.screen ?? NSScreen.main
        let fullscreen = parentWindow?.styleMask.contains(.fullScreen) == true
        let visible = screen.map { fullscreen ? $0.frame : $0.visibleFrame } ?? CGRect(origin: .zero, size: size)
        let fit = placement.fit(size: size, anchor: anchor, visible: visible)
        if fit.isClipped { phase.scrollHeight = fit.frame.height - style.padding.vertical }
        phase.slide = fit.slide
        cardFrame = fit.frame
        panel.setFrame(fit.frame.insetBy(dx: -margin, dy: -margin), display: true)
    }

    private static func screen(containing rect: CGRect) -> NSScreen? {
        let point = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.screens.max { $0.frame.intersection(rect).area < $1.frame.intersection(rect).area }
    }

    // Row callbacks from the SwiftUI card.
    func hover(_ row: Int?) { session?.hover(self, row: row) }
    func activate(_ row: Int) { session?.activate(self, row: row) }
    func openAccessory(_ row: Int) { session?.openAccessory(self, row: row) }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

/// The SwiftUI root of one popup window.
private struct MXRPopupLevelView: View {
    let level: MXRPopupLevel
    let surface: Bool

    var body: some View {
        let phase = level.phase
        Group {
            switch level.content {
            case .menu(let provider):
                MXRMenuCardContent(items: provider(), style: level.style, width: level.width,
                                   scrollHeight: phase.scrollHeight,
                                   highlighted: level.tracking.highlighted, expanded: level.tracking.expanded,
                                   onHover: { level.hover($0) }, onActivate: { level.activate($0) },
                                   onAccessory: { level.openAccessory($0) })
                    // The AppKit AXMenu of the hosting view stands in for the drawn rows.
                    .accessibilityHidden(true)
            case .custom(let view):
                if surface {
                    view.padding(level.style.padding)
                        .frame(minWidth: level.width, alignment: .leading)
                        .background { MXRPopupSurface(style: level.style) }
                } else {
                    view
                }
            }
        }
        .fixedSize()
        .opacity(phase.visible ? 1 : 0)
        .offset(phase.arrived ? .zero : phase.slide.startOffset(Theme.Popup.slideDistance))
        .padding(level.style.outerMargin)
        .onAppear {
            guard phase.animates else { return }
            withAnimation(.easeOut(duration: Theme.Popup.appearDuration)) {
                phase.arrived = true
                phase.visible = true
            }
        }
    }
}

// MARK: - Window

/// Borderless, non-activating panel that carries one popup card.
final class MXRPopupPanel: NSPanel {
    var acceptsKey = false
    var keyHandler: ((NSEvent) -> Bool)?
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) != true { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Hosting view that takes the first click (submenus are never key) and reports size changes.
final class MXRPopupHostingView: NSHostingView<AnyView> {
    var onContentSizeChange: (() -> Void)?
    private var isCheckScheduled = false

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        sizingOptions = [.intrinsicContentSize]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Set for a menu level: the view is that level's `AXMenu` (PLAYER-07).
    weak var menuLevel: MXRPopupLevel?

    override func isAccessibilityElement() -> Bool { menuLevel != nil || super.isAccessibilityElement() }
    override func accessibilityRole() -> NSAccessibility.Role? { menuLevel != nil ? .menu : super.accessibilityRole() }
    override func accessibilityChildren() -> [Any]? {
        guard let menuLevel else { return super.accessibilityChildren() }
        return menuLevel.accessibilityItems()
    }
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        guard let menuLevel else { return super.accessibilityHitTest(point) }
        let items = menuLevel.accessibilityItems()
        guard let row = items.first(where: { $0.accessibilityFrame().contains(point) }) else { return self }
        return row.accessibilityHitTest(point) ?? row
    }
    override var accessibilityFocusedUIElement: Any? {
        guard let menuLevel else { return super.accessibilityFocusedUIElement }
        return menuLevel.accessibilityItems().first { $0.isAccessibilityFocused() } ?? self
    }
    override func accessibilityFrame() -> NSRect {
        guard let menuLevel else { return super.accessibilityFrame() }
        return menuLevel.cardFrame
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard window != nil, !isCheckScheduled else { return }
        isCheckScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.isCheckScheduled = false
                self?.onContentSizeChange?()
            }
        }
    }
}

// MARK: - Dismiss action

/// Closes the popup that contains the view (custom popup content, e.g. after a choice).
public struct MXRDismissPopupAction: Sendable {
    private let action: @MainActor @Sendable () -> Void
    init(_ action: @escaping @MainActor @Sendable () -> Void) { self.action = action }
    @MainActor public func callAsFunction() { action() }
}

private struct MXRDismissPopupKey: EnvironmentKey {
    static let defaultValue = MXRDismissPopupAction {}
}

extension EnvironmentValues {
    /// Closes the enclosing design-system popup (no-op elsewhere). Use in `.mxrPopup` content the
    /// way `\.dismiss` is used in a popover.
    public var mxrDismissPopup: MXRDismissPopupAction {
        get { self[MXRDismissPopupKey.self] }
        set { self[MXRDismissPopupKey.self] = newValue }
    }
}
