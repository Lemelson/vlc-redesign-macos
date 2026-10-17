import AppKit
import MXRCore
import Observation

/// Window preferences live on the native owner, independent of SwiftUI's
/// player/library presentation. Observation installs no idle polling timer.
@MainActor
final class MXRNativeWindowServices: NSObject, NSMenuItemValidation {
    private let model: AppModel
    private weak var window: NSWindow?
    private weak var videoHost: MXRVideoHostView?
    private let onShowWindow: () -> Void
    private let onQuit: () -> Void
    private var statusItem: NSStatusItem?
    private var notice: NSPanel?
    private var noticeTask: Task<Void, Never>?
    private var isRunning = false
    private var suppressStartupRaise = false
    private var wasPlaying = false
    private var mediaID: String?
    private var frameName = ""
    private var resizePolicy = MXRAutoresizePolicy()
    var hasVideo = false

    init(model: AppModel, window: NSWindow, videoHost: MXRVideoHostView,
         onShowWindow: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.model = model
        self.window = window
        self.videoHost = videoHost
        self.onShowWindow = onShowWindow
        self.onQuit = onQuit
        super.init()
    }

    static func preferences(for model: AppModel) -> MXRNativePreferences {
        _ = model.settings.revision
        return MXRNativePreferences { name in
            let key = name.hasPrefix("hotkeys-") ? name : "macosx-redesign-" + name
            switch model.settings.backend.value(for: key) {
            case .bool(let value): return .bool(value)
            case .integer(let value):
                if ["remember-window", "start-minimized", "pause-minimized", "menubar-icon", "reverse-scroll"].contains(name) {
                    return .bool(value != 0)
                }
                return .number(Double(value))
            case .float(let value): return .number(value)
            case .string(let value): return .text(value)
            case nil: return nil
            }
        }
    }

    func start() -> Bool {
        isRunning = true
        suppressStartupRaise = Self.preferences(for: model).startsMinimized
        if !suppressStartupRaise { window?.makeKeyAndOrderFront(nil) }
        observe()
        if suppressStartupRaise {
            // A menu-bar icon is the tray destination. With it disabled, retain
            // a reachable Dock window through normal AppKit miniaturization.
            if statusItem != nil { window?.orderOut(nil) }
            else { window?.makeKeyAndOrderFront(nil); window?.miniaturize(nil) }
        }
        return !suppressStartupRaise
    }

    func stop() {
        isRunning = false
        saveFrame()
        window?.setFrameAutosaveName("")
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        hideNotice()
    }

    func userShowedWindow() { suppressStartupRaise = false; hideNotice() }

    func didMiniaturize() {
        if Self.preferences(for: model).pausesMinimizedVideo, hasVideo, model.player.isPlaying { model.player.pause() }
    }

    func videoStarted(size: CGSize) {
        hasVideo = true
        let preferences = Self.preferences(for: model)
        resizeVideo(to: size)
        if suppressStartupRaise {
            if preferences.pausesMinimizedVideo, model.player.isPlaying { model.player.pause() }
        } else if model.player.isPlaying, preferences.raiseOnPlay.shouldRaise(hasVideo: true) {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }

    func resizeVideo(to size: CGSize) {
        guard let window, let videoHost, let content = window.contentView else { return }
        let preferences = Self.preferences(for: model)
        let scale = window.backingScaleFactor
        guard resizePolicy.consume(mode: preferences.autoresize,
            isFullscreen: window.styleMask.contains(.fullScreen),
            hasPlayerLayout: model.interface.library == .hidden,
            validSize: size.width.isFinite && size.height.isFinite && size.width >= 16 && size.height >= 16) else { return }
        content.layoutSubtreeIfNeeded()
        let chrome = NSSize(width: max(0, content.bounds.width - videoHost.bounds.width),
                            height: max(0, content.bounds.height - videoHost.bounds.height))
        let available = (window.screen ?? NSScreen.main)?.visibleFrame.size ?? NSSize(width: 1920, height: 1080)
        window.setContentSize(NSSize(width: min(available.width, max(window.contentMinSize.width, size.width / scale + chrome.width)),
                                     height: min(available.height, max(window.contentMinSize.height, size.height / scale + chrome.height))))
    }

    private func observe() {
        guard isRunning else { return }
        withObservationTracking {
            let preferences = Self.preferences(for: model)
            window?.alphaValue = preferences.windowAlpha
            let nextFrameName = preferences.remembersWindow ? "MacOSXRedesign.MainWindow." + model.profiles.currentID : ""
            if nextFrameName != frameName {
                saveFrame()
                frameName = nextFrameName
                window?.setFrameAutosaveName(frameName)
                if !frameName.isEmpty { window?.setFrameUsingName(frameName) }
            }
            updateStatusItem(enabled: preferences.showsMenubarIcon)
            let playing = model.player.isPlaying
            if playing, !wasPlaying, hasVideo, preferences.pausesMinimizedVideo,
               suppressStartupRaise || window?.isMiniaturized == true {
                model.player.pause()
            } else if playing, !wasPlaying, !suppressStartupRaise,
               preferences.raiseOnPlay.shouldRaise(hasVideo: hasVideo || model.player.media?.kind == .video) {
                window?.makeKeyAndOrderFront(nil)
                NSApp.activate()
            }
            wasPlaying = playing
            if let media = model.player.media, media.id != mediaID {
                mediaID = media.id
                let minimized = window?.isMiniaturized == true || window?.isVisible != true || NSApp.isHidden
                if preferences.trackNotification.shouldShow(isMinimized: minimized), preferences.notificationDuration > 0 {
                    showNotice(media.title, duration: preferences.notificationDuration, minimized: minimized)
                }
            } else if model.player.media == nil { mediaID = nil }
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func saveFrame() {
        if !frameName.isEmpty, let window, !window.styleMask.contains(.fullScreen) { window.saveFrame(usingName: frameName) }
    }

    private func updateStatusItem(enabled: Bool) {
        if !enabled, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        } else if enabled, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let image = NSApp.applicationIconImage.copy() as? NSImage
            image?.size = NSSize(width: 18, height: 18)
            item.button?.image = image
            item.button?.toolTip = MXRAppController.appName
            let menu = NSMenu()
            menu.addItem(withTitle: "Show " + MXRAppController.appName, action: #selector(showWindow(_:)), keyEquivalent: "").target = self
            for command in [AppCommand.playPause, .stop, .previous, .next, .quit] {
                let entry = menu.addItem(withTitle: command.title, action: #selector(runCommand(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = command.rawValue
            }
            item.menu = menu
            statusItem = item
        }
        if let menu = statusItem?.menu, let entry = menu.items.first(where: { ($0.representedObject as? String) == AppCommand.playPause.rawValue }) {
            entry.title = model.player.isPlaying ? "Pause" : "Play"
        }
    }

    @objc private func showWindow(_ sender: NSMenuItem) { onShowWindow(); NSApp.activate() }
    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let command = AppCommand(rawValue: raw),
              model.canPerform(command, from: .system) else { return }
        if command == .quit { onQuit() } else { model.perform(command, from: .system) }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let raw = menuItem.representedObject as? String, let command = AppCommand(rawValue: raw) else { return true }
        return model.canPerform(command, from: .system)
    }

    private func showNotice(_ title: String, duration: Double, minimized: Bool) {
        hideNotice()
        if !minimized {
            let originalDuration = model.osd.duration
            let feedback = model.osd.isFeedbackEnabled
            model.osd.duration = .seconds(duration)
            model.osd.isFeedbackEnabled = true
            model.osd.show(title)
            model.osd.duration = originalDuration
            model.osd.isFeedbackEnabled = feedback
            return
        }
        // A local nonactivating AppKit notice needs no notification permission.
        let text = NSTextField(wrappingLabelWithString: title)
        text.font = .preferredFont(forTextStyle: .headline)
        text.frame = NSRect(x: 16, y: 14, width: 288, height: 44)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 72),
                            styleMask: [.nonactivatingPanel, .hudWindow], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView?.addSubview(text)
        if let screen = window?.screen ?? NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - panel.frame.width - 16,
                                         y: screen.visibleFrame.maxY - panel.frame.height - 16))
        }
        panel.orderFrontRegardless()
        notice = panel
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.hideNotice()
        }
    }

    private func hideNotice() {
        noticeTask?.cancel()
        noticeTask = nil
        notice?.orderOut(nil)
        notice = nil
    }
}
