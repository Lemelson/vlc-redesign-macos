import AppKit
import MXRCore
import MXRUI
import MXRDesign
import Observation

/// The macOS menu bar (S11). It mirrors the in-window menus with the same command registry and
/// live bindings, in the standard Mac order: app, File, Edit, View, Playback, Audio, Video,
/// Window, Help (D025, D026). Items that open a dialog end with "…".
@MainActor
final class MXRNativeMenus: NSObject, NSMenuDelegate, NSMenuItemValidation {
    let mainMenu = MXRMenuBar()
    private let model: AppModel
    private let onFullscreen: () -> Void
    private let onPictureInPicture: (() -> Void)?
    private let onShowWindow: () -> Void
    private let onQuit: () -> Void
    private var commands: [NSMenuItem] = []
    private var fullscreenItem: NSMenuItem?
    private let canStartPictureInPicture: () -> Bool
    private let recents = NSMenu(title: "Open Recent")
    /// Audio, Video, View ▸ Extensions and their submenus: the in-window menu rows (D025).
    private let mirror: MXRNativeMenuMirror
    private let profiles = NSMenu(title: "Profile")

    /// VLC's user documentation (Help menu).
    private static let helpURL = URL(string: "https://docs.videolan.me/vlc-user/")

    init(model: AppModel, onFullscreen: @escaping () -> Void,
         onPictureInPicture: (() -> Void)?, canStartPictureInPicture: @escaping () -> Bool = { false }, onShowWindow: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.model = model
        self.onFullscreen = onFullscreen
        self.onPictureInPicture = onPictureInPicture
        self.canStartPictureInPicture = canStartPictureInPicture
        self.onShowWindow = onShowWindow
        self.onQuit = onQuit
        self.mirror = MXRNativeMenuMirror(isBlocked: { [model] in model.isBehindModal })
        super.init()
        mirror.willUpdate = { [weak self] in self?.refreshCommands() }
        // One window, no tab bar items in View and Window.
        NSWindow.allowsAutomaticWindowTabbing = false
        mainMenu.shouldPerformKeyEquivalent = { [weak self] event in
            guard let self else { return false }
            let keyWindow = NSApp.keyWindow
            let hasModal = self.model.interface.sheet != nil || keyWindow?.attachedSheet != nil
                || keyWindow?.isSheet == true || NSApp.modalWindow != nil
            return MXRKeyRouting.shouldPerformMenuEquivalent(event, firstResponder: keyWindow?.firstResponder,
                                                             isCapturing: self.model.interface.isCapturingShortcut,
                                                             hasModal: hasModal,
                                                             panelListFocused: self.model.interface.panelListHasKeyboardFocus)
        }
        build()
        observeCommands()
    }

    private func build() {
        let app = addMenu(MXRAppController.appName)
        add(.about, to: app)
        app.addItem(.separator())
        add(.settings, to: app)
        add(.keyboardShortcuts, to: app)
        profiles.delegate = self
        addSubmenu(profiles, to: app)
        app.addItem(.separator())
        let services = NSMenu(title: "Services")
        addSubmenu(services, to: app)
        NSApp.servicesMenu = services
        app.addItem(.separator())
        app.addItem(withTitle: "Hide \(MXRAppController.appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        add(.quit, to: app)

        let file = addMenu("File")
        for command in [AppCommand.openFiles, .openFolder, .openNetworkStream, .openDisc, .openCaptureDevice, .openFromClipboard] {
            add(command, to: file)
        }
        recents.delegate = self
        addSubmenu(recents, to: file)
        file.addItem(.separator())
        for command in [AppCommand.convert, .stream] { add(command, to: file) }
        file.addItem(.separator())
        add(.addSubtitleFile, to: file)
        file.addItem(.separator())
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let edit = addMenu("Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        // Library search is ⌥⌘F: VLC keeps ⌘F for fullscreen (D040).
        let find = NSMenu(title: "Find")
        addSubmenu(find, to: edit)
        let searchLibrary = find.addItem(withTitle: "Search Library", action: #selector(searchLibrary(_:)), keyEquivalent: "f")
        searchLibrary.keyEquivalentModifierMask = [.command, .option]
        searchLibrary.target = self

        let view = addMenu("View")
        for command in [AppCommand.toggleLibrary, .showFullLibrary, .toggleQueue, .toggleSettingsSidebar] { add(command, to: view) }
        view.addItem(.separator())
        add(.hideUI, to: view)
        add(.customizePlayer, to: view)
        view.addItem(.separator())
        // VLC's extensions menu (C-05): installed Lua extensions and their own menus.
        // Each opening asks VLC for the extensions' current menus (VLC's own UIs call
        // extension_GetMenu as the menu opens); the open menu follows the reply.
        let extensions = NSMenu(title: "Extensions")
        mirror.mirror(extensions, rows: { [model] in MXRPlayerMenus.extensions(model) },
                      onOpen: { [model] in model.extensions.refresh() })
        addSubmenu(extensions, to: view)
        view.addItem(.separator())
        // The toggleFullScreen: action keeps AppKit from inserting a second "Enter Full Screen".
        let fullscreen = view.addItem(withTitle: "Enter Full Screen", action: #selector(toggleFullScreen(_:)), keyEquivalent: "")
        fullscreen.target = self
        fullscreenItem = fullscreen

        let playback = addMenu("Playback")
        let playbackGroups: [[AppCommand]] = [[.playPause, .stop, .previous, .next], [.jumpBackward10, .jumpForward10],
                                              [.faster, .slower, .normalRate], [.nextFrame, .toggleABLoop],
                                              [.toggleRepeat, .toggleShuffle], [.record, .addBookmark]]
        for (index, group) in playbackGroups.enumerated() {
            if index > 0 { playback.addItem(.separator()) }
            for command in group { add(command, to: playback) }
        }
        let audio = addMenu("Audio")
        mirror.mirror(audio) { [model] in MXRPlayerMenus.audio(model) }
        let video = addMenu("Video")
        // Full Screen lives in View with VLC's ⌘F (D034), so the Video menu leaves it out.
        mirror.mirror(video, rows: { [model] in MXRPlayerMenus.video(model, includesFullscreen: false) },
                 finish: { [weak self] menu in self?.finishVideoMenu(menu) })

        let windows = addMenu("Window")
        windows.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windows.addItem(.separator())
        windows.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windows

        let help = addMenu("Help")
        help.addItem(withTitle: "VLC Help", action: #selector(openHelp(_:)), keyEquivalent: "?").target = self
        add(.keyboardShortcuts, to: help)
        NSApp.helpMenu = help
        refreshCommands()
    }

    private func addMenu(_ title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.delegate = self
        addSubmenu(menu, to: mainMenu)
        return menu
    }
    private func addSubmenu(_ menu: NSMenu, to parent: NSMenu) {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        parent.addItem(item)
    }
    private func add(_ command: AppCommand, to menu: NSMenu) {
        let item = menu.addItem(withTitle: Self.title(command, playing: false), action: #selector(runCommand(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = command.rawValue
        commands.append(item)
    }

    /// Mac menu titles: "…" for items that open a window or dialog, the app name in About and Quit.
    private static func title(_ command: AppCommand, playing: Bool) -> String {
        switch command {
        case .playPause: playing ? "Pause" : "Play"
        case .about: "About \(MXRAppController.appName)"
        case .quit: "Quit \(MXRAppController.appName)"
        case .openFiles: "Open File(s)…"
        case .openFolder: "Open Folder…"
        case .openNetworkStream: "Open Network Stream…"
        case .openDisc: "Open Disc…"
        case .openCaptureDevice: "Open Capture Device…"
        case .convert: "Convert…"
        case .stream: "Stream…"
        case .settings: "Settings…"
        case .keyboardShortcuts: "Keyboard Shortcuts…"
        case .manageProfiles: "Manage Profiles…"
        case .addBookmark: "Add Bookmark"
        case .toggleRepeat: "Repeat"
        default: command.title
        }
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let command = AppCommand(rawValue: raw) else { return }
        guard model.canPerform(command) else { return }
        if command == .quit { onQuit() }
        else if command == .toggleFullscreen { onFullscreen() }
        else { model.perform(command) }
    }
    @objc private func toggleFullScreen(_ sender: Any?) {
        guard model.canPerform(.toggleFullscreen) else { return }
        onFullscreen()
    }
    @objc private func togglePictureInPicture(_ sender: NSMenuItem) {
        guard !model.isBehindModal, model.player.isPictureInPicture || canStartPictureInPicture() else { return }
        onPictureInPicture?()
    }
    @objc private func searchLibrary(_ sender: NSMenuItem) {
        guard model.canPerform(.toggleLibrary) else { return }
        if model.interface.library == .hidden { model.interface.library = .compact }
        model.library.searchFieldRequested = true
        onShowWindow()
    }
    @objc private func openHelp(_ sender: NSMenuItem) {
        if let url = Self.helpURL { NSWorkspace.shared.open(url) }
    }
    @objc private func openRecent(_ sender: NSMenuItem) {
        guard model.canPerform(.openFiles), let id = sender.representedObject as? String,
              let entry = model.recents.entries.first(where: { $0.id == id }) else { return }
        model.play(entry.media)
        onShowWindow()
    }
    @objc private func clearRecents(_ sender: NSMenuItem) { if model.canPerform(.openFiles) { model.recents.clear() } }
    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard model.canPerform(.manageProfiles), !model.interface.isCustomizing,
              let id = sender.representedObject as? String,
              let profile = model.profiles.profiles.first(where: { $0.id == id }) else { return }
        model.profiles.select(profile)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleFullScreen(_:)) { return model.canPerform(.toggleFullscreen) }
        if menuItem.action == #selector(togglePictureInPicture(_:)) {
            menuItem.state = model.player.isPictureInPicture ? .on : .off
            return !model.isBehindModal && (model.player.isPictureInPicture || canStartPictureInPicture())
        }
        if menuItem.action == #selector(selectProfile(_:)) { return model.canPerform(.manageProfiles) && !model.interface.isCustomizing }
        if menuItem.action == #selector(openRecent(_:)) { return model.canPerform(.openFiles) }
        if menuItem.action == #selector(searchLibrary(_:)) { return model.canPerform(.toggleLibrary) }
        if menuItem.action == #selector(clearRecents(_:)) { return model.canPerform(.openFiles) && !model.recents.entries.isEmpty }
        guard let raw = menuItem.representedObject as? String, let command = AppCommand(rawValue: raw) else { return true }
        return model.canPerform(command)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshCommands()
        if menu === profiles {
            profiles.removeAllItems()
            for profile in model.profiles.profiles {
                let item = profiles.addItem(withTitle: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = profile.id
                item.state = profile.id == model.profiles.currentID ? .on : .off
            }
            profiles.addItem(.separator())
            let manage = profiles.addItem(withTitle: Self.title(.manageProfiles, playing: false), action: #selector(runCommand(_:)), keyEquivalent: "")
            manage.target = self
            manage.representedObject = AppCommand.manageProfiles.rawValue
            return
        }
        guard menu === recents else { return }
        recents.removeAllItems()
        for entry in model.recents.entries {
            let item = recents.addItem(withTitle: entry.media.listTitle, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id
        }
        if !model.recents.entries.isEmpty { recents.addItem(.separator()) }
        recents.addItem(withTitle: "Clear Menu", action: #selector(clearRecents(_:)), keyEquivalent: "").target = self
    }

    /// The Video menu's own rows after the shared ones: Subtitles and Picture in Picture.
    private func finishVideoMenu(_ menu: NSMenu) {
        let subtitles = NSMenu(title: "Subtitles")
        mirror.mirror(subtitles) { [model] in MXRPlayerMenus.subtitles(model) }
        mirror.adopt(subtitles, in: menu)
        addSubmenu(subtitles, to: menu)
        if onPictureInPicture != nil {
            let pip = menu.addItem(withTitle: "Picture in Picture", action: #selector(togglePictureInPicture(_:)), keyEquivalent: "")
            pip.target = self
            pip.state = model.player.isPictureInPicture ? .on : .off
        }
    }

    private func refreshCommands() {
        for item in commands {
            guard let raw = item.representedObject as? String, let command = AppCommand(rawValue: raw) else { continue }
            item.title = Self.title(command, playing: model.player.isPlaying)
            item.state = switch command {
            case .hideUI: model.interface.isUIHidden ? .on : .off
            case .toggleMute: model.player.isMuted ? .on : .off
            case .record: model.player.isRecording ? .on : .off
            case .toggleShuffle: model.queue.isShuffled ? .on : .off
            case .toggleRepeat: model.queue.repeatMode == .off ? .off : (model.queue.repeatMode == .one ? .mixed : .on)
            case .toggleABLoop: model.player.abLoop == .off ? .off : .on
            default: .off
            }
            apply(model.keyBinding(for: command), to: item)
            if command == .quit, item.keyEquivalent.isEmpty { item.keyEquivalent = "q"; item.keyEquivalentModifierMask = .command }
        }
        if let fullscreenItem {
            fullscreenItem.state = model.player.isFullscreen ? .on : .off
            fullscreenItem.title = model.player.isFullscreen ? "Exit Full Screen" : "Enter Full Screen"
            apply(model.keyBinding(for: .toggleFullscreen), to: fullscreenItem)
        }
    }

    private func apply(_ binding: KeyBinding?, to item: NSMenuItem) { MXRNativeMenuMirror.apply(binding, to: item) }

    private func observeCommands() {
        withObservationTracking {
            refreshCommands()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeCommands() }
        }
    }
}

@MainActor
final class MXRMenuBar: NSMenu {
    var shouldPerformKeyEquivalent: ((NSEvent) -> Bool)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // NSMenu declares this override nonisolated, but AppKit invokes it
        // synchronously on its main event loop. Keep the unchecked handoff
        // confined to this call; assumeIsolated checks the executor at runtime.
        let invocation = KeyEquivalentInvocation(menu: self, event: event)
        return MainActor.assumeIsolated { invocation.perform() }
    }

    private func performOnMainActor(with event: NSEvent) -> Bool {
        guard shouldPerformKeyEquivalent?(event) != false else { return false }
        return super.performKeyEquivalent(with: event)
    }

    private struct KeyEquivalentInvocation: @unchecked Sendable {
        let menu: MXRMenuBar
        let event: NSEvent

        @MainActor func perform() -> Bool { menu.performOnMainActor(with: event) }
    }
}
