import AppKit
import MXRCore
import MXRDesign
import SwiftUI

extension View {
    /// Presents ``InterfaceModel/sheet`` the way the design shows dialogs (SD-11, spec-part2 §14 A):
    /// centred in the window over a click-catching layer that draws nothing, one at a time, never as a stacked
    /// sheet. Esc and ⌘W close the dialog (a draft is discarded, as Cancel does). Each dialog lays
    /// out in the space it gets; nothing is scaled down.
    public func mxrDialogPresentation(engineVersion: String? = nil) -> some View {
        modifier(MXRDialogPresentation(engineVersion: engineVersion))
    }
}

private struct MXRDialogPresentation: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let engineVersion: String?

    func body(content: Content) -> some View {
        let isModal = app.interface.sheet != nil
        content
            // Behind a dialog the player and library leave VoiceOver and the keyboard focus order;
            // the scrim already blocks the mouse. Not `.disabled`, which dims the chrome under the scrim
            // (player buttons draw at 40 % when disabled); text fields are kept out by DialogKeyLoopGuard.
            .accessibilityHidden(isModal)
            .environment(\.mxrKeyboardFocusSuspended, isModal)
            // Add Subtitles choices come back for every new item of a remembered folder (SD-18).
            .mxrRememberedSubtitles()
            .overlay {
                GeometryReader { geometry in
                    ZStack {
                        if let sheet = app.interface.sheet {
                            scrim(for: sheet)
                                .transition(.opacity)
                            MXRDialogFrame(sheet: sheet, container: geometry.size, engineVersion: engineVersion)
                                .id(sheet.id)
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: Theme.DialogMotion.enterScale)))
                                .accessibilityAddTraits(.isModal)
                            closeKeys(for: sheet)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .ignoresSafeArea()
                .animation(.easeOut(duration: app.interface.sheet == nil ? Theme.DialogMotion.disappearDuration : Theme.DialogMotion.appearDuration), value: app.interface.sheet?.id)
            }

    }

    /// The layer between the window and the dialog. It catches clicks but draws nothing: the video
    /// shows no dimming behind a dialog (06m02.47 and 17m40.9 read the bars and the picture at the
    /// same brightness as before it opened; spec-part1 §06), Figma never uses BG/B2 Transparent, and
    /// a macOS sheet does not dim its window either (D035).
    private func scrim(for sheet: AppSheet) -> some View {
        Color.clear
            .contentShape(Rectangle())
            // Modal: clicks never reach the player. Menu-like and read-only dialogs close on an outside click.
            .onTapGesture { if sheet.closesOnOutsideClick { close() } }
            .accessibilityHidden(true)
    }

    /// Esc and ⌘W. Disabled while a shortcut field records keys, so Esc cancels the recording instead.
    @ViewBuilder
    private func closeKeys(for sheet: AppSheet) -> some View {
        if !app.interface.isCapturingShortcut {
            ZStack {
                Button("Close", action: close).keyboardShortcut(.cancelAction)
                Button("Close Dialog", action: close).keyboardShortcut("w", modifiers: .command)
            }
            .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private func close() {
        if app.interface.sheet == .onboarding { app.completeOnboarding(); return }
        app.interface.dismissSheet()
    }
}

/// One dialog at its design size, shrunk to the window when the window is smaller (never scaled).
struct MXRDialogFrame: View {
    let sheet: AppSheet
    let container: CGSize
    let engineVersion: String?

    /// The space a dialog may take, centred in the window. Vertically it keeps the top bar's height
    /// clear at both edges, so a shrunk dialog never runs under the traffic lights (S48 compact) and
    /// stays centred; a design-size dialog in a 1080 window (867 pt Settings) is unaffected.
    static func available(in container: CGSize) -> CGSize {
        CGSize(width: max(0, container.width - Theme.Metric.panelInset * 2),
               height: max(0, container.height - max(Theme.Metric.topBarHeight, Theme.Metric.panelInset) * 2))
    }

    var body: some View {
        let available = Self.available(in: container)
        let preferred = sheet.preferredSize
        Group {
            if sheet == .profiles {
                content.frame(maxHeight: min(preferred.height, available.height))
            } else if case .mediaInfo = sheet {
                // As tall as its content (S65), at most the window.
                content.frame(width: min(preferred.width, available.width)).frame(maxHeight: min(preferred.height, available.height))
            } else {
                content.frame(width: min(preferred.width, available.width), height: min(preferred.height, available.height))
            }
        }
        .mxrShadow(Theme.Effect.menuShadow)
        .background { DialogKeyLoopGuard() }
    }

    @ViewBuilder
    private var content: some View {
        switch sheet {
        case .settings(let category): MXRSettingsView(categoryID: category)
        case .keyboardShortcuts: MXRKeyboardShortcutsView()
        case .addSubtitles(let scope, let source): MXRAddSubtitlesView(scope: scope, source: source)
        case .openNetworkStream: MXRNetworkStreamView()
        case .newPlaylist: MXRNewPlaylistView()
        case .openDisc: MXRDiscView()
        case .openCaptureDevice: MXRCaptureView()
        case .convert: MXRConvertView()
        case .stream: MXRStreamView()
        case .about: MXRAboutView(version: engineVersion)
        case .onboarding: MXROnboardingView()
        case .profiles: MXRProfilesView()
        case .mediaInfo(let media): MXRMediaInfoView(media: media)
        }
    }
}

@MainActor
extension AppSheet {
    /// The Figma frame of each dialog.
    var preferredSize: CGSize {
        switch self {
        case .settings: Theme.Metric.Dialogs.settings.size
        case .keyboardShortcuts: Theme.Metric.Dialogs.keyboardShortcuts.size
        case .addSubtitles: Theme.Metric.Dialogs.addSubtitles.size
        case .openNetworkStream: Theme.Metric.Dialogs.openNetworkStream.size
        case .newPlaylist: Theme.Metric.Dialogs.newPlaylist.size
        case .profiles: MXRProfilesView.preferredSize
        case .onboarding: MXROnboardingView.preferredSize
        case .stream: MXRStreamView.preferredSize
        case .openDisc: MXRDiscView.preferredSize
        case .openCaptureDevice: MXRCaptureView.preferredSize
        case .mediaInfo: MXRMediaInfoView.maximumSize
        default: Theme.Metric.DialogForms.formSize
        }
    }

    /// Menu-like and read-only dialogs close on a click outside them; forms with input do not.
    var closesOnOutsideClick: Bool {
        switch self {
        case .profiles, .about, .mediaInfo: true
        default: false
        }
    }
}

/// Keeps the keyboard inside the dialog. AppKit's key-view loop spans the whole window, so without
/// this Tab could move from the dialog into a text field behind the scrim (library, queue or panel
/// search) and type there. While the dialog is up, every control behind it refuses first responder,
/// so it leaves the key-view loop at the source and cannot take the keyboard at all (F-08); the
/// controls get it back when the last dialog of the window closes. A field that had focus when the
/// dialog opened gives it up. As a fallback for a field created behind the dialog after it opened,
/// a Tab that still lands outside is carried on until it reaches a key view inside it.
///
/// "Inside" is membership, not geometry (F-08): the dialog and the content behind it share one
/// hosting view, whose subviews AppKit draws in order, so SwiftUI keeps them in z-order. This guard
/// is the dialog's backmost platform view; a key view is inside when it sits in the guard's subview
/// or a later one, wherever it is on screen. A field behind the scrim lies under the dialog's
/// rectangle in a small window and is still outside; a dialog field scrolled out of view is inside.
struct DialogKeyLoopGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> GuardView { GuardView() }
    func updateNSView(_ nsView: GuardView, context: Context) {}

    final class GuardView: NSView {
        private var monitor: Any?
        /// The controls behind the dialog this guard made refuse first responder.
        private var suspended = NSHashTable<NSControl>.weakObjects()
        /// The window this guard suspends controls in (kept to hand them over when it leaves).
        private weak var suspendedWindow: NSWindow?
        /// Guards in a window; a crossfade between two dialogs briefly has two.
        private static let live = NSHashTable<GuardView>.weakObjects()

        /// Only marks the dialog's place in the z-order; clicks go to the dialog's controls.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { releaseBackground(); return }
            Self.live.add(self)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, event.window === self.window, event.keyCode == 48 else { return }
                    // Before AppKit handles the Tab: a field created behind the dialog since it
                    // opened leaves the loop too.
                    self.suspendBackground()
                    let backwards = event.modifierFlags.contains(.shift)
                    Task { @MainActor [weak self] in self?.keepFocusInside(backwards: backwards) }
                }
                return event
            }
            suspendBackground()
            Task { @MainActor [weak self] in
                self?.suspendBackground()
                self?.keepFocusInside(backwards: nil)
            }
        }

        /// Takes every control behind the dialog out of the key-view loop.
        func suspendBackground() {
            guard let window, let root = window.contentView else { return }
            suspendedWindow = window
            let dialogs = Self.live.allObjects.filter { $0.window === window }
            suspend(in: root, dialogs: dialogs)
        }

        /// `dialogs`: every guard up in the window; a control inside any of them stays focusable.
        private func suspend(in view: NSView, dialogs: [GuardView]) {
            if view === self || dialogs.contains(where: { $0.isInside(view) }) { return }
            if let control = view as? NSControl, !control.refusesFirstResponder {
                control.refusesFirstResponder = true
                suspended.add(control)
            }
            for subview in view.subviews { suspend(in: subview, dialogs: dialogs) }
        }

        /// Gives the controls back, or hands them to another dialog still up in the same window.
        private func releaseBackground() {
            Self.live.remove(self)
            let controls = suspended.allObjects
            suspended.removeAllObjects()
            if let window = suspendedWindow, let successor = Self.live.allObjects.first(where: { $0.window === window }) {
                for control in controls {
                    if successor.isInside(control) { control.refusesFirstResponder = false } else { successor.suspended.add(control) }
                }
                successor.suspendBackground()
            } else {
                for control in controls { control.refusesFirstResponder = false }
            }
            suspendedWindow = nil
        }

        /// The view that holds the keyboard: a field editor stands for its text field.
        private static func keyView(of responder: NSResponder?) -> NSView? {
            if let editor = responder as? NSTextView, editor.isFieldEditor { return editor.delegate as? NSView }
            guard let view = responder as? NSView, view is NSControl || view is NSTextView else { return nil }
            return view
        }

        /// Whether `view` belongs to the dialog: it shares an ancestor with this guard and is drawn
        /// in front of it (the guard's own branch or a later sibling branch).
        func isInside(_ view: NSView) -> Bool {
            if view.isDescendant(of: self) { return true }
            var guardBranch: NSView = self
            var container = superview
            while let candidate = container, !view.isDescendant(of: candidate) {
                guardBranch = candidate
                container = candidate.superview
            }
            guard let container else { return false }
            var viewBranch = view
            while let parent = viewBranch.superview, parent !== container { viewBranch = parent }
            if viewBranch === guardBranch { return true }
            let order = container.subviews
            guard let guardIndex = order.firstIndex(of: guardBranch), let viewIndex = order.firstIndex(of: viewBranch) else { return false }
            return viewIndex > guardIndex
        }

        /// `backwards` nil: the dialog just opened, so a key view behind it simply resigns.
        func keepFocusInside(backwards: Bool?) {
            guard let window, var view = Self.keyView(of: window.firstResponder), !isInside(view) else { return }
            guard let backwards else { window.makeFirstResponder(nil); return }
            var visited = Set<ObjectIdentifier>()
            while visited.insert(ObjectIdentifier(view)).inserted {
                if backwards { window.selectKeyView(preceding: view) } else { window.selectKeyView(following: view) }
                guard let next = Self.keyView(of: window.firstResponder) else { return }
                if isInside(next) { return }
                view = next
            }
            window.makeFirstResponder(nil)
        }
    }
}
