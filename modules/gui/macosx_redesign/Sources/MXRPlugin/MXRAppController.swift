import AppKit
import MXRBridgeAPI
import MXRCore
import MXRUI
import MXRVLCBackend
import Observation
import SwiftUI

/// Native lifetime owner. Models and the main video surface are built once;
/// SwiftUI changes their presentation without recreating a decoder or vout.
@MainActor
final class MXRAppController: NSObject, NSApplicationDelegate, NSWindowDelegate, MXRVideoSurfaceProvider {
    let model: AppModel
    private let session: VLCBridgeSession
    private var bridge: MXRInterfaceBridge { session.bridge }
    private let surface: MXRVideoSurfaceView
    private let videoHost: MXRVideoHostView
    private let pictureInPicture: MXRPictureInPictureController
    private var window: NSWindow?
    private var mainOutput: MXRVideoOutput?
    private struct AuxiliaryOutput {
        let output: MXRVideoOutput
        let window: NSWindow
        let surface: MXRVideoSurfaceView
    }
    private var auxiliaries: [ObjectIdentifier: AuxiliaryOutput] = [:]
    private var fullscreenRequests: [ObjectIdentifier: Bool] = [:]
    private var fullscreenTransitions: Set<ObjectIdentifier> = []
    private var lastPiPPlaying: Bool?
    /// D055: observers of macOS's fullscreen strip window (menu bar reveal) while the main window is fullscreen.
    private var systemStripObservers: [NSObjectProtocol] = []
    /// D055: samples the strip's frame while fullscreen, so the top bar follows it even when AppKit
    /// posts no notification for the strip window during its reveal animation.
    private var systemStripTracker: MXRSystemStripTracker?
    /// VLC (VLCVideoOutputProvider handleVideoCloseForDisplay): a window that went fullscreen for a
    /// video leaves fullscreen when that video ends; one that was fullscreen before stays.
    private var fullscreenEnteredWithVideo = false
    private var observerToken: Int?
    private var keyMonitor: Any?
    private var menus: MXRNativeMenus?
    private var presentations: MXRNativePresentations?
    private var remoteControl: MXRRemoteControl?
    private var windowServices: MXRNativeWindowServices?
    private var isRunning = false
    private var firstLaunchOnboarding = MXRFirstLaunchOnboarding()
    private var launchFileOpening: MXRLaunchFileOpening

    init(model: AppModel, session: VLCBridgeSession) {
        self.model = model
        self.session = session
        launchFileOpening = MXRLaunchFileOpening(arguments: ProcessInfo.processInfo.arguments,
            initialQueue: model.queue.items.compactMap { URL(string: $0.media.mrl) },
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
        let surface = session.bridge.makeVideoSurface()
        self.surface = surface
        videoHost = MXRVideoHostView(surface: surface)
        pictureInPicture = MXRPictureInPictureController(videoSurface: surface, player: session.player)
        super.init()
        pictureInPicture.returnView = videoHost
        configureVideoHost(videoHost) { [weak self] in self?.toggleFullscreen() }
        videoHost.onOpenURLs = { [weak self] urls in self?.open(urls) }
    }

    static var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "VLC Redesign"
    }

    func start() {
        isRunning = true
        NSApp.delegate = self
        // Both Settings' Clear History and the native Clear Menu use this store.
        model.recents.onCleared = { NSDocumentController.shared.clearRecentDocuments(nil) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        // D022: one 40 pt top bar holds the traffic lights; the content ignores the titlebar safe area.
        MXRWindowControls.configure(window)
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentMinSize = NSSize(width: 480, height: 270)
        window.delegate = self
        let pipAction: (() -> Void)? = pictureInPicture.isAvailable ? { [weak self] in
            self?.pictureInPicture.toggle()
        } : nil
        let scene = MXRAppView(videoView: AnyView(MXRNativeVideoView(host: videoHost)),
                               onPictureInPicture: pipAction, engineVersion: bridge.vlcVersion)
            .appModel(model)
        window.contentView = NSHostingView(rootView: scene)
        window.center()
        self.window = window
        model.interface.windowControlsReserve = MXRWindowControls.leadingReserve(in: window)
        windowServices = MXRNativeWindowServices(model: model, window: window, videoHost: videoHost,
            onShowWindow: { [weak self] in self?.showMainWindow() }, onQuit: { [weak self] in self?.bridge.quit() })
        let shouldShowOnStartup = windowServices?.start() == true
        bridge.videoSurfaceProvider = self
        menus = MXRNativeMenus(model: model, onFullscreen: { [weak self] in self?.toggleFullscreen() },
                               onPictureInPicture: pipAction, canStartPictureInPicture: { [weak self] in
                                   guard let self else { return false }
                                   return self.pictureInPicture.isAvailable && self.surface.isInUse && self.videoHost.window != nil
                               }, onShowWindow: { [weak self] in self?.showMainWindow() },
                               onQuit: { [weak self] in self?.bridge.quit() })
        NSApp.mainMenu = menus?.mainMenu
        presentations = MXRNativePresentations(model: model, window: window)
        remoteControl = MXRRemoteControl(model: model, session: session)
        remoteControl?.start()
        observerToken = session.observePlayer { [weak self] change in
            guard let self else { return }
            self.remoteControl?.refresh()
            let playing = self.model.player.isPlaying
            if self.lastPiPPlaying != playing {
                self.lastPiPPlaying = playing
                self.pictureInPicture.updatePlaying(playing)
            }
            if change == .fullscreen, self.mainOutput == nil, let window = self.window {
                self.requestFullscreen(self.session.player.isFullscreen, for: window)
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRunning, event.window === self.window,
                  let window = self.window,
                  MXRKeyRouting.shouldHandle(firstResponder: window.firstResponder,
                    hasSheet: window.attachedSheet != nil || self.model.interface.sheet != nil,
                    isCapturing: self.model.interface.isCustomizing || self.model.interface.isCapturingShortcut,
                    panelListFocused: self.model.interface.panelListHasKeyboardFocus,
                    binding: KeyBinding(event: event)) else { return event }
            // D024: Esc closes the front-most popup before VLC's leave-fullscreen hotkey sees it.
            if event.keyCode == Self.escapeKeyCode, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
               self.model.interface.dismissTransientPopup() { return nil }
            guard let binding = KeyBinding(event: event) else { return event }
            if let action = self.model.shortcuts.action(for: binding), Self.playActions.contains(action.id),
               self.presentLibraryForEmptyQueue() {
                self.model.shortcuts.onTriggered?(action, binding)
                return nil
            }
            if let action = self.model.shortcuts.action(for: binding), let steps = MXRKeyRouting.volumeSteps(actionID: action.id) {
                self.model.shortcuts.onTriggered?(action, binding)
                let player = self.model.player
                let target = min(max(player.volume + Double(steps) * player.volumeStep, 0), player.maximumVolume)
                player.adjustVolume(steps: steps)
                // D027: the engine OSD is off; the redesign OSD shows the action next to the key.
                self.model.osd.actionPerformed(String(format: "Volume: %ld%%", lround(target * 100)))
                return nil
            }
            return self.model.shortcuts.handle(binding) ? nil : event
        }
        observeWindowState()
        observeSubtitleSafeInset()
        observeWindowControls()
        presentations?.start()
        if shouldShowOnStartup { showMainWindow(); NSApp.activate() }
        // Default interface startup follows VLC's command-line queue setup.
        // Give Finder's pending open callback one main-loop turn as well.
        DispatchQueue.main.async { [weak self] in
            self?.presentLaunchLibrary()
            self?.observeFirstLaunchOnboarding()
        }
    }

    private static let escapeKeyCode: UInt16 = 53
    /// VLC's play and play/pause hotkeys (Space by default).
    private static let playActions: Set<String> = ["play-pause", "play", "key-play-pause", "key-play"]

    /// D029/WT-08: with nothing queued by VLC's command line, Finder or a restored queue, launch
    /// shows the full-window library on Home (the compact library with "Start in compact mode").
    private func presentLaunchLibrary() {
        guard isRunning, model.player.media == nil, model.queue.items.isEmpty,
              model.interface.fileRequest == nil, model.interface.library == .hidden else { return }
        model.library.select(.home)
        model.interface.presentLaunchLibrary(compact: model.startsInCompactMode)
    }

    /// D029/WT-09: Play with an empty queue opens the library on Home instead of an engine error.
    /// Returns false when there is something to play.
    @discardableResult
    private func presentLibraryForEmptyQueue() -> Bool {
        guard model.player.media == nil, model.queue.items.isEmpty, !model.interface.isCustomizing else { return false }
        model.playOrOpenLibrary()
        return true
    }

    /// D022: the traffic lights belong to the top bar. They fade out with it (auto-hidden bars,
    /// Hide UI) and come back with it. In fullscreen macOS owns them.
    private func observeWindowControls() {
        guard isRunning else { return }
        let visible = withObservationTracking {
            model.interface.isTopBarVisible && !model.interface.isUIHidden
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeWindowControls() }
        }
        applyWindowControls(visible: visible)
    }

    private func applyWindowControls(visible: Bool, animated: Bool = true) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
        let target: CGFloat = visible ? 1 : 0
        guard buttons.contains(where: { $0.isHidden == visible || $0.alphaValue != target }) else { return }
        if visible { buttons.forEach { $0.isHidden = false } }
        let animates = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animates ? MXRWindowControls.fadeDuration : 0
            buttons.forEach { $0.animator().alphaValue = target }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Hidden buttons take no clicks; skip when the bar came back during the fade.
                guard let self, !visible, self.model.interface.isTopBarVisible == false || self.model.interface.isUIHidden else { return }
                buttons.forEach { $0.isHidden = true }
            }
        }
    }

    func stop() {
        isRunning = false
        model.recents.onCleared = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let observerToken { session.removeObserver(observerToken) }
        observerToken = nil
        presentations?.stop()
        remoteControl?.stop()
        windowServices?.stop()
        pictureInPicture.invalidate()
        subtitleSafeInsetFeed.invalidate()
        if bridge.videoSurfaceProvider === self { bridge.videoSurfaceProvider = nil }
        for auxiliary in auxiliaries.values {
            auxiliary.window.delegate = nil
            auxiliary.window.orderOut(nil)
        }
        auxiliaries.removeAll()
        mainOutput = nil
        window?.delegate = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        menus = nil
        presentations = nil
        remoteControl = nil
        windowServices = nil
        NSApp.mainMenu = nil
        if NSApp.delegate === self { NSApp.delegate = nil }
    }

    /// Live run 1: subtitles hid under the revealed fullscreen control bar. The composition reports
    /// the points the bar covers at the bottom of the video view; the feed subtracts the picture's
    /// letterbox and re-sends when the video view resizes or its window changes backing scale.
    private func observeSubtitleSafeInset() {
        guard isRunning else { return }
        withObservationTracking {
            let covered = model.interface.subtitleSafeInset
            let video = model.tracks.selectedTrack(of: .video)?.videoSize ?? model.player.media?.videoSize
            subtitleSafeInsetFeed.update(covered: covered, videoSize: video)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSubtitleSafeInset() }
        }
    }

    private lazy var subtitleSafeInsetFeed = SubtitleSafeInsetFeed(view: videoHost) { [weak self] points, scale in
        self?.model.player.backend.setSubtitleSafeInset(points: points, backingScale: scale)
    }

    private func observeWindowState() {
        guard isRunning else { return }
        withObservationTracking {
            window?.title = model.windowTitle
            for auxiliary in auxiliaries.values { auxiliary.window.title = model.windowTitle }
            window?.representedURL = model.player.media.flatMap { URL(string: $0.mrl) }
            switch model.appearance.theme {
            case .dark: window?.appearance = NSAppearance(named: .darkAqua)
            case .light: window?.appearance = NSAppearance(named: .aqua)
            case .system: window?.appearance = nil
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeWindowState() }
        }
    }

    private func observeFirstLaunchOnboarding() {
        guard isRunning else { return }
        let action = withObservationTracking {
            let sheet: MXRFirstLaunchOnboarding.Sheet = switch model.interface.sheet {
            case nil: .none
            case .onboarding: .onboarding
            default: .other
            }
            return firstLaunchOnboarding.update(.init(needsOnboarding: model.needsOnboarding,
                hasMediaOrQueue: model.player.media != nil || !model.queue.items.isEmpty,
                hasFileRequest: model.interface.fileRequest != nil, sheet: sheet,
                hasNativeSheet: window?.attachedSheet != nil))
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeFirstLaunchOnboarding() }
        }
        switch action {
        case .present: model.interface.present(.onboarding)
        case .dismiss:
            if model.interface.sheet == .onboarding { model.interface.dismissSheet() }
        case .none: break
        }
    }

    private func showMainWindow() {
        windowServices?.userShowedWindow()
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func configureVideoHost(_ host: MXRVideoHostView, onFullscreen: @escaping () -> Void) {
        host.onMagnifyFullscreen = { [weak self, weak host] desired in
            guard let self, self.model.canPerform(.toggleFullscreen),
                  !self.model.interface.isCapturingShortcut else { return }
            let fullscreen = host?.window?.styleMask.contains(.fullScreen) == true
            if desired == nil || desired != fullscreen { onFullscreen() }
        }
        host.doubleClickActionEnabled = { [weak self] in
            guard let self else { return false }
            return MXRNativeWindowServices.preferences(for: self.model).doubleClickFullscreen
        }
        host.onToggleFullscreen = { [weak self] in
            guard let self, !self.model.interface.isCustomizing, !self.model.interface.isCapturingShortcut,
                  MXRNativeWindowServices.preferences(for: self.model).doubleClickFullscreen else { return }
            onFullscreen()
        }
        // D024: a click on the video that closes a popup does not also toggle playback.
        host.onMouseDown = { [weak self] in self?.model.interface.dismissTransientPopup() ?? false }
        host.onSingleClick = { [weak self] in
            guard let self, !self.model.interface.isCustomizing, !self.model.interface.isCapturingShortcut else { return }
            switch MXRNativeWindowServices.preferences(for: self.model).singleClick {
            case .playPause: if !self.presentLibraryForEmptyQueue() { self.model.perform(.playPause) }
            case .controls: self.model.interface.areBarsVisible = true
            case .none: break
            }
        }
        var scroll = MXRVideoScrollAccumulator()
        host.onScroll = { [weak self] event in
            guard let self, !self.model.interface.isCustomizing, !self.model.interface.isCapturingShortcut else { return false }
            let preferences = MXRNativeWindowServices.preferences(for: self.model)
            guard let action = scroll.consume(x: event.deltaX, y: event.deltaY, timestamp: event.timestamp,
                natural: event.isDirectionInvertedFromDevice, preferences: preferences) else {
                return abs(event.deltaX) > abs(event.deltaY) ? preferences.horizontalScroll != .none : preferences.verticalScroll != .none
            }
            switch action.mode {
            // D027/R8: the engine OSD is off; the redesign OSD shows the scroll's result.
            case .volume:
                let player = self.model.player
                let target = min(max(player.volume + Double(action.steps) * player.volumeStep, 0), player.maximumVolume)
                player.adjustVolume(steps: action.steps)
                self.model.osd.actionPerformed(String(format: "Volume: %ld%%", lround(target * 100)))
            case .seek:
                let configured = self.model.settings.backend.value(for: "short-jump-size")?.doubleValue ?? 3
                let seconds = configured.isFinite ? min(max(configured, 1), 600) : 3
                guard self.model.player.canSeek else { break }
                let clock = self.model.clock
                var target = clock.time(at: CACurrentMediaTime()) + .seconds(Double(action.steps) * seconds)
                if target < .zero { target = .zero }
                if clock.length > .zero, clock.length < target { target = clock.length }
                self.model.player.jump(by: .seconds(Double(action.steps) * seconds))
                let length = clock.length > .zero ? " / " + clock.length.formatted(.hoursMinutesSeconds) : ""
                self.model.osd.actionPerformed(target.formatted(.hoursMinutesSeconds) + length)
            case .none: break
            }
            return true
        }
    }

    private func open(_ urls: [URL]) {
        // Opening files from Finder, the Dock or the window plays them in the player.
        if model.interface.library == .full { model.interface.library = .hidden }
        model.open(urls: urls)
        MXRNativeRecents.record(urls, model: model)
        showMainWindow()
    }

    private func toggleFullscreen() {
        guard let window else { return }
        if mainOutput != nil { model.perform(.toggleFullscreen) }
        else { requestFullscreen(!window.styleMask.contains(.fullScreen), for: window) }
    }

    private func requestFullscreen(_ fullscreen: Bool, for target: NSWindow) {
        let id = ObjectIdentifier(target)
        // A request is kept only while a transition is (about to be) running; a stale "false" left
        // by a no-op request would otherwise turn the next green-button entry straight back.
        guard !fullscreenTransitions.contains(id) else { fullscreenRequests[id] = fullscreen; return }
        if target.styleMask.contains(.fullScreen) != fullscreen {
            fullscreenRequests[id] = fullscreen
            if fullscreen {
                placeForFullscreen(target)
                target.makeKeyAndOrderFront(nil)
            }
            target.toggleFullScreen(nil)
        } else {
            fullscreenRequests.removeValue(forKey: id)
            output(for: target)?.reportFullscreen(fullscreen)
        }
    }

    private func placeForFullscreen(_ target: NSWindow) {
        _ = model.settings.revision
        guard model.settings.backend.value(for: "macosx-redesign-fullscreen-screen")?.stringValue == "main",
              let primary = NSScreen.screens.first, target.screen !== primary else { return }
        // NSScreen.main follows the key window. The first screen is the primary
        // display with the menu bar, so this preference can cross displays.
        let available = primary.visibleFrame
        let size = NSSize(width: min(target.frame.width, available.width),
                          height: min(target.frame.height, available.height))
        target.setFrame(NSRect(x: available.midX - size.width / 2,
                               y: available.midY - size.height / 2,
                               width: size.width, height: size.height), display: true)
    }

    private func output(for target: NSWindow) -> MXRVideoOutput? {
        if target === window { return mainOutput }
        return auxiliaries.values.first { $0.window === target }?.output
    }

    // MARK: Native app and window callbacks

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        launchFileOpening.applicationDidFinishLaunching()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        let urls = launchFileOpening.urlsToOpen(urls)
        if !urls.isEmpty { open(urls) }
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = launchFileOpening.urlsToOpen(filenames.map { URL(fileURLWithPath: $0) })
        if !urls.isEmpty { open(urls) }
        sender.reply(toOpenOrPrint: .success)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === window {
            pictureInPicture.stop()
            model.player.stop()
            sender.orderOut(nil)
            return false
        }
        if let output = output(for: sender) {
            output.reportClose()
            // VLC's current owner callback records the close report without
            // tearing down the output. Hide this auxiliary window explicitly;
            // its surface remains valid until the engine disables the output.
            sender.orderOut(nil)
            return false
        }
        return true
    }

    func windowDidMiniaturize(_ notification: Notification) {
        if notification.object as? NSWindow === window { windowServices?.didMiniaturize() }
    }

    /// D022/§03: the compact toolbar that sizes the windowed 40 pt top bar would otherwise stay in
    /// fullscreen as an opaque band in its own window, over the video and the top-bar hot zone.
    /// Auto-hiding it leaves the top edge to the SwiftUI bars; macOS reveals it only with the menu bar.
    func window(_ window: NSWindow,
                willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = [])
        -> NSApplication.PresentationOptions {
        window.toolbar == nil ? proposedOptions : proposedOptions.union(.autoHideToolbar)
    }

    func windowWillEnterFullScreen(_ notification: Notification) { beginFullscreenTransition(notification, fullscreen: true) }
    func windowWillExitFullScreen(_ notification: Notification) { beginFullscreenTransition(notification, fullscreen: false) }
    private func beginFullscreenTransition(_ notification: Notification, fullscreen: Bool) {
        guard let target = notification.object as? NSWindow else { return }
        if target === window, fullscreen {
            // macOS shows the traffic lights in its own fullscreen titlebar; the cone moves to the edge.
            applyWindowControls(visible: true, animated: false)
            model.interface.windowControlsReserve = 0
            fullscreenEnteredWithVideo = mainOutput != nil
        }
        if target === window, !fullscreen {
            stopObservingSystemStrip()
            // The windowed 40 pt titlebar comes from the toolbar (D022); it is back before the exit animation.
            target.toolbar?.isVisible = true
        }
        let id = ObjectIdentifier(target)
        fullscreenTransitions.insert(id)
        if fullscreenRequests[id] == nil { fullscreenRequests[id] = fullscreen }
    }
    func windowDidEnterFullScreen(_ notification: Notification) { finishFullscreenTransition(notification, fullscreen: true) }
    func windowDidExitFullScreen(_ notification: Notification) { finishFullscreenTransition(notification, fullscreen: false) }
    private func finishFullscreenTransition(_ notification: Notification, fullscreen: Bool) {
        guard let target = notification.object as? NSWindow else { return }
        let id = ObjectIdentifier(target)
        fullscreenTransitions.remove(id)
        output(for: target)?.reportFullscreen(fullscreen)
        if target === window, fullscreen {
            // D055: like VLC's video windows, no toolbar in fullscreen. macOS then reveals only the
            // menu bar and the titlebar with the traffic lights, and the top bar moves below them.
            target.toolbar?.isVisible = false
            observeSystemStrip(of: target)
        }
        if target === window, !fullscreen {
            stopObservingSystemStrip()
            target.toolbar?.isVisible = true
            model.interface.windowControlsReserve = MXRWindowControls.leadingReserve(in: target)
            applyWindowControls(visible: model.interface.isTopBarVisible && !model.interface.isUIHidden, animated: false)
        }
        let requested = fullscreenRequests.removeValue(forKey: id) ?? fullscreen
        if requested != fullscreen { requestFullscreen(requested, for: target) }
        else if target === window, session.player.isFullscreen != fullscreen || model.player.isFullscreen != fullscreen {
            // WT-M1: the window is the truth for the layout. Setting it through the player model
            // also refreshes the model's snapshot, which vout fullscreen callbacks do not reach.
            model.player.setFullscreen(fullscreen)
        }
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { fullscreenFailed(window) }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { fullscreenFailed(window) }
    private func fullscreenFailed(_ target: NSWindow) {
        fullscreenTransitions.remove(ObjectIdentifier(target))
        fullscreenRequests.removeValue(forKey: ObjectIdentifier(target))
        let actual = target.styleMask.contains(.fullScreen)
        output(for: target)?.reportFullscreen(actual)
        if target === window, !actual {
            stopObservingSystemStrip()
            target.toolbar?.isVisible = true
        }
        if target === window {
            model.player.setFullscreen(actual)
            model.interface.windowControlsReserve = MXRWindowControls.leadingReserve(in: target)
        }
    }

    /// D055: in fullscreen the pointer at the top edge is over macOS's own strip window (menu bar
    /// and titlebar), so this window never sees it. The strip's frame tells how far it covers the
    /// window; the reveal controller pins the top bar and moves it below the strip.
    private func observeSystemStrip(of target: NSWindow) {
        stopObservingSystemStrip()
        // AppKit may create the strip window lazily, at the first reveal, so the strip is looked up
        // again on every sample: the window holding the traffic lights.
        let tracker = MXRSystemStripTracker(
            sample: { [weak target] in target.map(Self.systemStripInset(of:)) ?? 0 },
            report: { [weak self] inset in
                guard let self, self.model.interface.fullscreenSystemInset != inset else { return }
                self.model.interface.fullscreenSystemInset = inset
            })
        systemStripTracker = tracker
        // Notifications, where AppKit posts them, make the reveal immediate; the tracker's timer
        // covers the reveal when it does not.
        let update: @Sendable (Notification) -> Void = { [weak tracker] _ in
            MainActor.assumeIsolated { tracker?.update() }
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.didChangeOcclusionStateNotification] {
            systemStripObservers.append(center.addObserver(forName: name, object: nil, queue: .main, using: update))
        }
        tracker.start()
    }

    private static func systemStripInset(of target: NSWindow) -> Double {
        guard target.styleMask.contains(.fullScreen), let strip = target.standardWindowButton(.closeButton)?.window,
              strip !== target else { return 0 }
        return MXRWindowControls.fullscreenSystemInset(stripFrame: strip.frame, windowFrame: target.frame,
                                                       stripShown: strip.isVisible && strip.occlusionState.contains(.visible))
    }

    private func stopObservingSystemStrip() {
        systemStripTracker?.stop()
        systemStripTracker = nil
        systemStripObservers.forEach(NotificationCenter.default.removeObserver)
        systemStripObservers.removeAll()
        if model.interface.fullscreenSystemInset != 0 { model.interface.fullscreenSystemInset = 0 }
    }

    // MARK: VLC video output callbacks

    func surface(for output: MXRVideoOutput) -> MXRVideoSurfaceView? {
        // A stream job's local copy ("Play locally while streaming") never takes the player surface.
        if mainOutput == nil, !output.isAuxiliary, !surface.isInUse {
            mainOutput = output
            windowServices?.videoStarted(size: output.proposedSize)
            session.log("video output attached to persistent player surface", level: .debug)
            return surface
        }
        let auxiliarySurface = bridge.makeVideoSurface()
        let scale = window?.backingScaleFactor ?? 2
        let proposed = output.proposedSize
        let size = proposed.width >= 16 && proposed.height >= 16
            ? NSSize(width: proposed.width / scale, height: proposed.height / scale)
            : NSSize(width: 480, height: 270)
        let auxiliary = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                 backing: .buffered, defer: false)
        auxiliary.isReleasedWhenClosed = false
        auxiliary.title = model.windowTitle
        auxiliary.collectionBehavior.insert(.fullScreenPrimary)
        auxiliary.delegate = self
        let host = MXRVideoHostView(surface: auxiliarySurface)
        configureVideoHost(host) { [weak self, weak auxiliary] in
            guard let self, let auxiliary else { return }
            self.requestFullscreen(!auxiliary.styleMask.contains(.fullScreen), for: auxiliary)
        }
        auxiliary.contentView = host
        auxiliary.center()
        auxiliary.orderFront(nil)
        auxiliaries[ObjectIdentifier(output)] = AuxiliaryOutput(output: output, window: auxiliary, surface: auxiliarySurface)
        return auxiliarySurface
    }

    func videoOutputDidStop(_ output: MXRVideoOutput) {
        if output === mainOutput {
            pictureInPicture.stop()
            mainOutput = nil
            windowServices?.hasVideo = false
            if let window, window.styleMask.contains(.fullScreen), fullscreenEnteredWithVideo { requestFullscreen(false, for: window) }
        } else if let auxiliary = auxiliaries.removeValue(forKey: ObjectIdentifier(output)) {
            auxiliary.window.delegate = nil
            auxiliary.window.orderOut(nil)
            fullscreenRequests.removeValue(forKey: ObjectIdentifier(auxiliary.window))
            fullscreenTransitions.remove(ObjectIdentifier(auxiliary.window))
        }
    }

    func videoOutput(_ output: MXRVideoOutput, requestsFullscreen fullscreen: Bool) {
        let target = output === mainOutput ? window : auxiliaries[ObjectIdentifier(output)]?.window
        if let target { requestFullscreen(fullscreen, for: target) }
    }
    func videoOutput(_ output: MXRVideoOutput, requestsSize size: CGSize) {
        if output === mainOutput { windowServices?.resizeVideo(to: size); return }
        guard let target = auxiliaries[ObjectIdentifier(output)]?.window,
              !target.styleMask.contains(.fullScreen), size.width > 0, size.height > 0 else { return }
        target.setContentSize(NSSize(width: size.width / target.backingScaleFactor,
                                     height: size.height / target.backingScaleFactor))
    }
    func videoOutput(_ output: MXRVideoOutput, requestsFloatOnTop floatOnTop: Bool) {
        let target = output === mainOutput ? window : auxiliaries[ObjectIdentifier(output)]?.window
        target?.level = floatOnTop ? .floating : .normal
    }
}
