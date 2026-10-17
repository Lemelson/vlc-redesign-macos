import AppKit
import MXRCore
import MXRDesign
import SwiftUI

/// The player's menus (S07–S10, S68): the `⋯` app menu with its Open Recent and Profile
/// submenus, and the right-click menu on the video with its submenus. All are design-system
/// popups (D025) built from the same ``AppCommand``s and bindings as the macOS menu bar, with
/// shortcuts in Mac glyphs (D026).
@MainActor
public enum MXRPlayerMenus {
    // MARK: ⋯ menu

    /// Figma `menu` 6062:13354 / `Profiles` 6648:20666, in Figma order.
    public static func appMenu(_ app: AppModel) -> [MXRMenuItem] {
        var items = AppCommand.appMenu.prefix { $0 != nil }.compactMap { $0 }.map { command($0, app) }
        items.append(openRecent(app))
        items.append(.separator)
        items.append(.submenu(app.profiles.menuTitle, icon: .profile) { profiles(app) })
        items += AppCommand.appMenu.drop { $0 != nil }.compactMap { $0 }.map { command($0, app) }
        return items
    }

    /// Open Recent: recent media, newest first, then Clear Menu.
    static func openRecent(_ app: AppModel) -> MXRMenuItem {
        .submenu("Open Recent", icon: .recent) {
            if app.recents.entries.isEmpty {
                MXRMenuItem("No Recent Items", isEnabled: false) {}
            }
            for entry in app.recents.entries {
                MXRMenuItem(entry.media.listTitle) { app.play(entry.media) }
            }
            MXRMenuItem.separator
            MXRMenuItem("Clear Menu", isEnabled: !app.recents.entries.isEmpty) { app.recents.clear() }
        }
    }

    /// S68 (Figma `Profiles`): the profiles with an orange check on the current one, then "+ New".
    static func profiles(_ app: AppModel) -> [MXRMenuItem] {
        let editable = !app.interface.isCustomizing
        var items = app.profiles.profiles.map { profile in
            MXRMenuItem(profile.name, isChecked: profile.id == app.profiles.currentID, isEnabled: editable) {
                MXRProfileEditing.select(profile, in: app)
            }
        }
        items.append(.separator)
        items.append(MXRMenuItem("New", icon: .add, iconTone: .mono, isEnabled: editable,
                                 accessibilityLabel: "New profile") { MXRProfileNaming.askForNewProfile(in: app) })
        return items
    }

    // MARK: Right-click menu

    /// Figma `right-click menu` 6065:13616: transport, Hide UI, the four media submenus, More
    /// Settings, Playlist, Open Media and Quit.
    ///
    /// - Parameter excluding: commands already shown above it (the overflow `⋯` lists the controls
    ///   that did not fit first; their rows are not repeated here).
    public static func videoContextMenu(_ app: AppModel, excluding: Set<AppCommand> = []) -> [MXRMenuItem] {
        var items = AppCommand.contextMenu.filter { $0 != .hideUI && !excluding.contains($0) }.map { command($0, app) }
        items.append(.separator)
        items.append(command(.hideUI, app))
        items.append(.separator)
        items.append(.submenu("Playback", icon: .playback, iconState: .selected) { playback(app) })
        items.append(.submenu("Video", icon: .video) { video(app) })
        items.append(.submenu("Audio", icon: .audio) { audio(app) })
        items.append(.submenu("Subtitle", icon: .subtitles) { subtitles(app) })
        items.append(.separator)
        items.append(.submenu("More Settings", icon: .settings) { moreSettings(app) })
        items.append(.submenu("Playlist", icon: .playlist) { playlist(app) })
        items.append(.submenu("Open Media", icon: .file) { openMedia(app) })
        items.append(command(.quit, app))
        return items
    }

    public static func playback(_ app: AppModel) -> [MXRMenuItem] {
        var items = [AppCommand.playPause, .stop, .jumpBackward10, .jumpForward10, .nextFrame, .toggleABLoop]
            .map { submenuCommand($0, app) }
        items.append(.separator)
        items.append(.submenu("Speed", isEnabled: app.player.canChangeRate) { speeds(app) })
        items.append(.submenu("Sleep Timer") {
            for timer in SleepTimer.allCases {
                MXRMenuItem(timer.title, isChecked: timer == app.player.sleepTimer) { app.player.setSleepTimer(timer) }
            }
        })
        if app.capabilities.hasRenderers { items.append(.submenu("Renderer") { renderers(app) }) }
        return items
    }

    /// Playback rates, the current one checked (right-click › Playback › Speed and the bar's speed control).
    public static func speeds(_ app: AppModel) -> [MXRMenuItem] {
        AppModel.rateSteps.map { rate in
            MXRMenuItem("\(rate.formatted())×", isChecked: abs(rate - app.player.rate) < 0.001) { app.player.setRate(rate) }
        }
    }

    /// Zoom choices, the current one checked (right-click › Video › Zoom and the bar's zoom control).
    public static func zooms(_ app: AppModel) -> [MXRMenuItem] {
        let current = app.videoEffects.effects.zoom
        return VideoZoom.allCases.map { value in
            MXRMenuItem(value.title, isChecked: value == current) { app.videoEffects.update { $0.zoom = value } }
        }
    }

    /// HDR choices in Figma `HDR Options` 2372:8733 order and titles (the bar's HDR control). The
    /// engine bridge applies only Auto, so it is the checked choice; the manual modes stay visible
    /// but disabled, with the reason below them (D039).
    public static func hdrModes(_ app: AppModel) -> [MXRMenuItem] {
        var items = HDRMode.allCases.map { mode in
            MXRMenuItem(mode.title, isChecked: mode == .auto, isEnabled: mode == .auto) {}
        }
        var reason = MXRMenuItem("Manual modes unavailable", isEnabled: false) {}
        reason.isSecondary = true
        items += [.separator, reason]
        return items
    }

    static func renderers(_ app: AppModel) -> [MXRMenuItem] {
        var items = [MXRMenuItem("This Mac", isChecked: app.renderers.selectedID == nil) {
            do { try app.renderers.select(id: nil) } catch { app.osd.show(error.localizedDescription) }
        }]
        for renderer in app.renderers.items {
            items.append(MXRMenuItem(renderer.name, isChecked: app.renderers.selectedID == renderer.id,
                                     isEnabled: app.player.isAudioOnly ? renderer.canAudio : renderer.canVideo) {
                do { try app.renderers.select(id: renderer.id) } catch { app.osd.show(error.localizedDescription) }
            })
        }
        items.append(.separator)
        items.append(MXRMenuItem(app.renderers.isDiscovering ? "Discovering Cast Devices…" : "Discover Cast Devices",
                                 isEnabled: !app.renderers.isDiscovering) {
            Task { @MainActor in
                do { try await app.renderers.discover() } catch { app.osd.show(error.localizedDescription) }
            }
        })
        return items
    }

    // MARK: Extensions (menu bar View ▸ Extensions)

    /// VLC's extensions menu (C-05): every installed Lua extension. An enabled extension with its
    /// own menu opens it as a submenu (checked, ending in Disable); an on-demand one runs; any other
    /// is a checkable row that enables or disables it. Manage Extensions… opens Settings ▸ Extensions.
    public static func extensions(_ app: AppModel) -> [MXRMenuItem] {
        let model = app.extensions
        var items: [MXRMenuItem] = model.extensions.map { ext in
            if model.availability(for: .run, extensionID: ext.id).isAvailable {
                return MXRMenuItem(ext.title) {
                    Task { @MainActor in
                        do { try await model.runExtension(ext) }
                        catch { app.dialogs.presentError(error, title: "Couldn’t Run “\(ext.title)”") }
                    }
                }
            }
            let canToggle = model.availability(for: .activate, extensionID: ext.id).isAvailable
            let entries = ext.isActivated && ext.hasMenu ? model.menu(for: ext) : []
            guard !entries.isEmpty else {
                return MXRMenuItem(ext.title, isChecked: ext.isActivated, isEnabled: canToggle) {
                    model.setActivated(!ext.isActivated, ext)
                }
            }
            // Read again as the submenu opens: the extension may have changed its menu since.
            var submenu = MXRMenuItem.submenu(ext.title) {
                for entry in model.menu(for: ext) { MXRMenuItem(entry.title) { model.trigger(entry, of: ext) } }
                MXRMenuItem.separator
                MXRMenuItem("Disable", isEnabled: canToggle) { model.setActivated(false, ext) }
            }
            submenu.isChecked = true
            return submenu
        }
        if items.isEmpty { items.append(MXRMenuItem("No Extensions", isEnabled: false) {}) }
        items.append(.separator)
        items.append(MXRMenuItem("Manage Extensions…") { app.interface.present(.settings(categoryID: "extensions")) })
        return items
    }

    /// - Parameter includesFullscreen: the right-click menu lists Fullscreen here; the menu bar
    ///   has it in View (D034), so its Video menu leaves it out.
    public static func video(_ app: AppModel, includesFullscreen: Bool = true) -> [MXRMenuItem] {
        let effects = app.videoEffects.effects
        var items = tracks(.video, app)
        items.append(.separator)
        items.append(.submenu("Aspect Ratio") {
            for value in VideoEffects.aspectRatioChoices {
                MXRMenuItem(value ?? "Default", isChecked: value == effects.aspectRatio) {
                    app.videoEffects.update { $0.aspectRatio = value }
                }
            }
        })
        items.append(.submenu("Crop") {
            for value in VideoEffects.cropChoices {
                MXRMenuItem(value ?? "Default", isChecked: value == effects.crop) { app.videoEffects.update { $0.crop = value } }
            }
        })
        items.append(.submenu("Zoom") { zooms(app) })
        items.append(.submenu("Deinterlace") {
            for value in DeinterlaceMode.allCases {
                MXRMenuItem(value.title, isChecked: value == effects.deinterlace) {
                    app.videoEffects.update { $0.deinterlace = value }
                }
            }
        })
        items.append(.separator)
        items.append(submenuCommand(.snapshot, app))
        if includesFullscreen { items.append(submenuCommand(.toggleFullscreen, app)) }
        items.append(.separator)
        items.append(MXRMenuItem("Video Settings") { app.interface.showPreferences(for: .video) })
        return items.tidiedSeparators
    }

    public static func audio(_ app: AppModel) -> [MXRMenuItem] {
        var items = tracks(.audio, app)
        items.append(.separator)
        items.append(.submenu("Audio Device", isEnabled: !app.tracks.audioDevices.isEmpty) {
            for device in app.tracks.audioDevices {
                MXRMenuItem(device.name, isChecked: device.id == app.tracks.currentAudioDeviceID) {
                    app.tracks.selectAudioDevice(device)
                }
            }
        })
        items.append(.separator)
        items += [AppCommand.toggleMute, .volumeUp, .volumeDown].map { submenuCommand($0, app) }
        items.append(.separator)
        items.append(MXRMenuItem("Audio Settings") { app.interface.showPreferences(for: .audio) })
        return items.tidiedSeparators
    }

    public static func subtitles(_ app: AppModel) -> [MXRMenuItem] {
        var items = tracks(.subtitle, app)
        items.append(.separator)
        items.append(submenuCommand(.addSubtitleFile, app))
        // VLC's subtitle delay keys (`subdelay-down`/`-up`, one 50 ms step like ``TracksModel/delayStep``)
        // shown beside the rows that do the same, as the other engine-key rows show theirs (D026).
        items.append(MXRMenuItem("Subtitle Earlier", shortcut: app.shortcuts.primaryBinding(for: "subdelay-down"),
                                 isEnabled: app.player.media != nil) { app.tracks.nudgeSubtitleDelay(steps: -1) })
        items.append(MXRMenuItem("Subtitle Later", shortcut: app.shortcuts.primaryBinding(for: "subdelay-up"),
                                 isEnabled: app.player.media != nil) { app.tracks.nudgeSubtitleDelay(steps: 1) })
        items.append(.separator)
        items.append(MXRMenuItem("Subtitle Settings") { app.interface.showPreferences(for: .subtitles) })
        return items.tidiedSeparators
    }

    /// "Disable" and the tracks of a kind, the selected one checked; nothing without tracks.
    static func tracks(_ kind: TrackKind, _ app: AppModel) -> [MXRMenuItem] {
        let list = app.tracks.tracks(of: kind)
        guard !list.isEmpty else { return [] }
        return [MXRMenuItem("Disable", isChecked: app.tracks.isNoneSelected(kind)) { app.tracks.selectNone(kind) }]
            + list.map { track in MXRMenuItem(track.name, isChecked: track.isSelected) { app.tracks.select(track) } }
    }

    static func moreSettings(_ app: AppModel) -> [MXRMenuItem] {
        // Selecting a tab never closes an already open sidebar (P7).
        var items = SidebarTab.allCases.map { tab in
            MXRMenuItem(tab.title, isChecked: app.interface.rightPanel == .sidebar(tab)) {
                app.interface.selectTab(.sidebar(tab))
            }
        }
        items.append(.separator)
        items += [AppCommand.settings, .keyboardShortcuts, .customizePlayer].map { submenuCommand($0, app) }
        return items
    }

    public static func playlist(_ app: AppModel) -> [MXRMenuItem] {
        let repeatTitle = switch app.queue.repeatMode {
        case .off: "Repeat"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
        return [
            MXRMenuItem("Show Queue", shortcut: app.keyBinding(for: .toggleQueue), isChecked: app.interface.isQueuePanelOpen) {
                app.perform(.toggleQueue)
            },
            MXRMenuItem(repeatTitle, shortcut: app.keyBinding(for: .toggleRepeat), isChecked: app.queue.repeatMode != .off) {
                app.perform(.toggleRepeat)
            },
            submenuCommand(.toggleShuffle, app),
            .separator,
            addToPlaylist(app, isEnabled: app.player.media != nil && app.capabilities.hasMediaLibrary,
                          newPlaylist: { if let media = app.player.media { app.presentNewPlaylist(media: [media]) } },
                          media: { app.player.media.map { [$0] } ?? [] },
                          onError: { title, error in app.dialogs.presentError(error, title: title) }),
            MXRMenuItem("Add Files to Queue…") { app.interface.request(.addFilesToQueue) },
            MXRMenuItem("Clear Queue", isEnabled: !app.queue.isEmpty) { app.queue.clear() },
        ]
    }

    // MARK: Add to Playlist (shared)

    /// The "Add to Playlist" submenu of every menu that adds media to a playlist: the library rows,
    /// the queue, the mini player and the player's Playlist submenu (PNL-03). Playlists load when
    /// the submenu opens, not while its rows are built.
    static func addToPlaylist(_ app: AppModel, title: String = "Add to Playlist", icon: MXRIcon.Name? = nil,
                              isEnabled: Bool = true,
                              newPlaylist: @escaping @MainActor () -> Void,
                              media: @escaping @MainActor () async -> [MediaItem],
                              onError: @escaping @MainActor (_ title: String, _ error: Error) -> Void) -> MXRMenuItem {
        .submenu(title, icon: icon, isEnabled: isEnabled, onOpen: { app.library.loadPlaylistsIfNeeded() }) {
            playlistItems(app, newPlaylist: newPlaylist, media: media, onError: onError)
        }
    }

    /// "New Playlist…", a separator, then one row per playlist. `media` is resolved when a row is
    /// chosen; a failure reports through `onError` with the title "Couldn’t Add to “name”".
    static func playlistItems(_ app: AppModel, newPlaylist: @escaping @MainActor () -> Void,
                              media: @escaping @MainActor () async -> [MediaItem],
                              onError: @escaping @MainActor (_ title: String, _ error: Error) -> Void) -> [MXRMenuItem] {
        var items = [MXRMenuItem("New Playlist…", icon: .add, action: newPlaylist)]
        if !app.library.playlists.isEmpty { items.append(.separator) }
        items += app.library.playlists.map { playlist in
            MXRMenuItem(playlist.name, icon: .playlist) {
                Task { @MainActor in
                    let chosen = await media()
                    guard !chosen.isEmpty else { return }
                    do { try await app.library.add(chosen, toPlaylist: playlist) }
                    catch { onError("Couldn’t Add to “\(playlist.name)”", error) }
                }
            }
        }
        return items
    }

    /// The compact bar's `⋯`: the controls that did not fit, each with its bar icon and the same
    /// enabled state and action as the bar button (CTL-02), then the right-click menu without the
    /// rows already listed.
    public static func overflowMenu(_ controls: [PlayerControl], commands: [AppCommand] = [], app: AppModel,
                             onPictureInPicture: (() -> Void)? = nil) -> [MXRMenuItem] {
        let shown = Set(controls.compactMap(\.command) + commands)
        var items = overflow(controls, app: app, onPictureInPicture: onPictureInPicture)
        items += commands.map { command($0, app) }
        items.append(.separator)
        items += videoContextMenu(app, excluding: shown)
        return items.tidiedSeparators
    }

    static func overflow(_ controls: [PlayerControl], app: AppModel, onPictureInPicture: (() -> Void)? = nil) -> [MXRMenuItem] {
        controls.compactMap { control -> MXRMenuItem? in
            var item: MXRMenuItem
            switch control {
            case .playbackSpeed: item = .submenu(control.title, isEnabled: app.player.canChangeRate) { speeds(app) }
            case .hdr: item = .submenu(control.title) { hdrModes(app) }
            case .zoom: item = .submenu(control.title) { zooms(app) }
            case .pictureInPicture:
                // The bar button's rule; behind a dialog it waits like the menu bar's item (D040).
                let available = !app.player.isAudioOnly && app.player.media != nil
                    && (onPictureInPicture != nil || app.capabilities.pictureInPicture != .unsupported)
                item = MXRMenuItem(control.title, isChecked: app.player.isPictureInPicture,
                                   isEnabled: available && !app.isBehindModal) {
                    if let onPictureInPicture { onPictureInPicture() }
                    else { app.player.setPictureInPicture(!app.player.isPictureInPicture) }
                }
            case .properties:
                item = MXRMenuItem(control.title, isEnabled: app.player.media != nil) {
                    if let media = app.player.media { app.interface.present(.mediaInfo(media)) }
                }
            case .replay:
                item = MXRMenuItem(control.title, isEnabled: app.player.canSeek && app.canPerform(.playPause)) {
                    app.player.seek(to: .zero); app.player.play()
                }
            case .playlists:
                item = MXRMenuItem(control.title, isEnabled: app.canPerform(.toggleLibrary)) {
                    app.library.select(.playlists); app.interface.library = .compact
                }
            case .chapters:
                item = MXRMenuItem(control.title, isChecked: app.interface.rightPanel == .queue(.chapters),
                                   isEnabled: app.canPerform(.toggleQueue)) { app.interface.toggleQueuePanel(.chapters) }
            case .bookmarks:
                item = MXRMenuItem(control.title, isChecked: app.interface.rightPanel == .queue(.bookmarks),
                                   isEnabled: app.canPerform(.toggleQueue)) { app.interface.toggleQueuePanel(.bookmarks) }
            default:
                guard let command = control.command else { return nil }
                item = self.command(command, app)
                if control == .record, !app.capabilities.hasRecording { item.isEnabled = false }
            }
            item.icon = control.barIcon
            return item
        }
    }

    static func openMedia(_ app: AppModel) -> [MXRMenuItem] {
        [AppCommand.openFiles, .openFolder, .openNetworkStream, .openDisc, .openCaptureDevice, .openFromClipboard]
            .map { submenuCommand($0, app) } + [openRecent(app)]
    }

    // MARK: Rows

    /// A command row with its two-tone icon, live title, binding and on/off state.
    static func command(_ command: AppCommand, _ app: AppModel) -> MXRMenuItem {
        let playing = command == .playPause && app.player.isPlaying
        // Figma's Hide UI row uses the mono `ui` artwork (6075:14088), the slashed frame.
        return MXRMenuItem(playing ? "Pause" : command.title, icon: playing ? .pause : command.playerIcon,
                           iconTone: command == .hideUI ? .mono : .twoTone,
                           shortcut: app.keyBinding(for: command), isChecked: isOn(command, app),
                           isEnabled: app.canPerform(command)) { app.perform(command) }
    }

    /// Submenu rows are text only, like Figma's profile submenu; the icon slot holds the check.
    static func submenuCommand(_ command: AppCommand, _ app: AppModel) -> MXRMenuItem {
        var item = self.command(command, app)
        item.icon = nil
        return item
    }

    static func isOn(_ command: AppCommand, _ app: AppModel) -> Bool {
        switch command {
        case .hideUI: app.interface.isUIHidden
        case .toggleFullscreen: app.player.isFullscreen
        case .toggleMute: app.player.isMuted
        case .record: app.player.isRecording
        case .toggleShuffle: app.queue.isShuffled
        case .toggleABLoop: app.player.abLoop != .off
        default: false
        }
    }

    /// Space between the `⋯` button and its menu: the rest of the 40 pt top bar under the 28 pt
    /// button, then the popup gap, so the menu hangs just under the bar (video 13m08).
    static var appMenuGap: CGFloat {
        (Theme.Metric.Window.topBar.height - MXRPlayerMetrics.headerIcon.height) / 2 + Theme.Popup.anchorGap
    }
}

extension View {
    /// The `⋯` app menu dropping from this view (S07, S08, S68).
    public func mxrAppMenu(isPresented: Binding<Bool>) -> some View {
        modifier(MXRAppMenuModifier(isPresented: isPresented))
    }

    /// The right-click menu of the video (S09, S10).
    public func mxrVideoContextMenu() -> some View {
        modifier(MXRVideoContextMenuModifier())
    }
}

private struct MXRAppMenuModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.mxrPopupMenu(isPresented: $isPresented,
                             placement: .awayFromWindowEdge(.leading, gap: MXRPlayerMenus.appMenuGap),
                             style: .appMenu) { [app] in MXRPlayerMenus.appMenu(app) }
    }
}

private struct MXRVideoContextMenuModifier: ViewModifier {
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.mxrContextMenu(style: .rightClickMenu) { [app] in MXRPlayerMenus.videoContextMenu(app) }
    }
}

/// A control-bar control that drops a design-system choice menu (D025): playback speed, HDR and
/// zoom. The menu opens above the control with the current value checked; while it is open the
/// control bar stays shown (``MXRPopupCenter/anchoredOwner``, D023).
public struct MXRPlayerBarMenu<Label: View>: View {
    public enum Kind: Sendable { case speed, hdr, zoom }

    @Environment(AppModel.self) private var app
    private let kind: Kind
    private let label: Label
    @State private var isOpen = false

    public init(_ kind: Kind, @ViewBuilder label: () -> Label) {
        self.kind = kind
        self.label = label()
    }

    public var body: some View {
        Button { isOpen.toggle() } label: { label.contentShape(.rect) }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .mxrPopupMenu(isPresented: $isOpen, placement: .above(.center), style: .textMenu) { [app, kind] in
                switch kind {
                case .speed: MXRPlayerMenus.speeds(app)
                case .hdr: MXRPlayerMenus.hdrModes(app)
                case .zoom: MXRPlayerMenus.zooms(app)
                }
            }
            .help(title)
            .accessibilityLabel(title)
    }

    private var title: String {
        switch kind {
        case .speed: "Playback Speed"
        case .hdr: "HDR"
        case .zoom: "Zoom"
        }
    }
}

/// The compact control bar's `⋯`: controls that do not fit, then the right-click menu.
public struct MXRPlayerOverflowButton: View {
    @Environment(AppModel.self) private var app
    private let commands: [AppCommand]
    private let controls: [PlayerControl]
    private let onPictureInPicture: (() -> Void)?
    @State private var isOpen = false

    public init(commands: [AppCommand]) { self.commands = commands; controls = []; onPictureInPicture = nil }
    public init(controls: [PlayerControl], onPictureInPicture: (() -> Void)? = nil) {
        self.controls = controls; self.onPictureInPicture = onPictureInPicture; commands = []
    }

    public var body: some View {
        Button { isOpen.toggle() } label: {
            MXRIcon(.more).frame(width: Theme.Metric.ControlBar.iconButton.width,
                                 height: Theme.Metric.ControlBar.iconButton.height)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .mxrPopupMenu(isPresented: $isOpen, placement: .above(.trailing), style: .rightClickMenu) { [app, commands, controls, onPictureInPicture] in
            MXRPlayerMenus.overflowMenu(controls, commands: commands, app: app, onPictureInPicture: onPictureInPicture)
        }
        .help("More playback controls")
        .accessibilityLabel("More playback controls")
    }
}

/// The `⋯` menu drawn as a card, exactly as it opens in the player (gallery S07).
public struct MXRAppMenuView: View {
    @Environment(AppModel.self) private var app
    private let expanded: Int?
    public init(expandedRow: Int? = nil) { expanded = expandedRow }
    public var body: some View {
        MXRMenuCard(items: MXRPlayerMenus.appMenu(app), style: .appMenu, expanded: expanded)
    }
}

/// The right-click menu drawn as a card, exactly as it opens over the video (gallery S09).
public struct MXRVideoContextMenuView: View {
    @Environment(AppModel.self) private var app
    public init() {}
    public var body: some View {
        MXRMenuCard(items: MXRPlayerMenus.videoContextMenu(app), style: .rightClickMenu)
    }
}

/// Names a new profile ("+ New" in the profile submenu) in a sheet on the player window.
@MainActor
enum MXRProfileNaming {
    static func askForNewProfile(in app: AppModel) {
        guard !app.interface.isCustomizing else { return }
        let alert = NSAlert()
        alert.messageText = "New Profile"
        alert.informativeText = "The new profile starts with the current layout and settings."
        let field = NSTextField(string: "")
        field.placeholderString = "Profile name"
        field.frame = NSRect(x: 0, y: 0, width: Theme.Metric.Menus.profilesSubmenu.width, height: Theme.Metric.textFieldHeight)
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            MXRProfileEditing.save(name: field.stringValue, replacing: nil, in: app)
        }
        if let window = NSApp.mainWindow ?? NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }
}

/// Figma shadows exclude the translucent interior (`showShadowBehindNode=false`).
struct PlayerOutsideShadow: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: radius).fill(Theme.Effect.menuShadow.color.color)
                .mxrShadow(Theme.Effect.menuShadow)
                .mask {
                    Rectangle().padding(-Theme.Effect.menuShadow.blur)
                        .overlay { RoundedRectangle(cornerRadius: radius).blendMode(.destinationOut) }
                        .compositingGroup()
                }
        }
    }
}

extension MXRPopupOwner {
    /// Popups dropped from the top bar keep only the top bar shown (D023).
    static let playerTopBar = MXRPopupOwner("player.topBar")
    /// Popups dropped from the control bar (speed, HDR, zoom, overflow `⋯`) keep only it shown.
    static let playerControlBar = MXRPopupOwner("player.controlBar")
}

extension PlayerChromeReveal.Bar {
    /// The bar an anchored popup belongs to, from ``MXRPopupCenter/anchoredOwner``.
    init?(owner: MXRPopupOwner?) {
        switch owner {
        case .playerTopBar?: self = .top
        case .playerControlBar?: self = .control
        default: return nil
        }
    }
}

extension PlayerControl {
    /// The control's icon on the bar, also used for its row in the overflow `⋯` (one mapping).
    var barIcon: MXRIcon.Name {
        switch self {
        case .sidebarToggle: .sidebarLeft
        case .fullscreen: .fullscreen
        case .previous: .previous
        case .next: .next
        case .audioTracks: .audio
        case .subtitleTracks: .subtitles
        case .playbackSettings, .rightSidebar: .playbackSettings
        case .queue: .lists
        case .forward10: .forward10Sec
        case .backward10: .backward10Sec
        case .forward15: .forward15Sec
        case .backward15: .backward15Sec
        case .stop: .stop
        case .repeatMode: .repeatRight
        case .shuffle: .shuffleRight
        case .record: .record
        case .snapshot: .snapshot
        case .quit: .quit
        case .settings: .settings
        case .goHome: .home
        case .favorite: .favorite
        case .bookmark: .bookmark
        case .playbackSpeed: .speed
        case .hdr: .hdr
        case .zoom: .zoom
        case .pictureInPicture: .pip
        case .properties: .info
        case .replay: .replay
        case .playlists: .playlist
        case .chapters: .chapters
        case .bookmarks: .bookmarks
        default: .blank
        }
    }
}

extension AppCommand {
    var playerIcon: MXRIcon.Name {
        switch self {
        case .openFiles: .file
        case .openFolder: .folder
        case .openNetworkStream, .stream: .streaming
        case .openDisc: .disc
        case .openCaptureDevice: .captureDevice
        case .openFromClipboard: .link
        case .convert: .swap
        case .keyboardShortcuts: .hotkeys
        case .customizePlayer: .paint
        case .settings: .settings
        case .about: .info
        case .playPause: .playback
        case .stop: .stop
        case .previous: .previous
        case .next: .next
        case .record: .record
        case .hideUI: .ui
        case .quit: .quit
        case .jumpBackward10: .backward10Sec
        case .jumpForward10: .forward10Sec
        case .jumpBackward15: .backward15Sec
        case .jumpForward15: .forward15Sec
        case .snapshot: .snapshot
        case .toggleFullscreen: .fullscreen
        case .toggleRepeat: .repeatRight
        case .toggleShuffle: .shuffleRight
        case .toggleQueue: .queue
        case .toggleLibrary: .sidebar
        case .showFullLibrary: .home
        case .toggleSettingsSidebar: .sidebarRight
        case .addBookmark: .bookmark
        case .favoriteCurrent: .favorite
        case .showSubtitleTracks: .subtitles
        case .showAudioTracks: .audio
        case .addSubtitleFile: .subtitles
        case .faster, .slower, .normalRate: .speed
        case .toggleMute, .volumeUp, .volumeDown: .volumeHigh
        default: .blank
        }
    }
}
