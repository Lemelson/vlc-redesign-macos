import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
import MXRUI
import SwiftUI

final class SettingsGallery: NSObject, GalleryProvider {
    @MainActor static func galleryEntries() -> [Any] {
        let frames: [(String, String, String)] = [
            ("general", "999:5047", "S49"), ("interface", "3046:10057", "S51"),
            ("privacy", "3062:11911", "S52"), ("controls", "6536:14482", "S53"),
            ("playback", "3062:12552", "S54"), ("video", "3073:14187", "S55"),
            ("audio", "3073:15879", "S56"), ("subtitles", "3180:17989", "S57"),
            ("library", "6542:15251", "S58"), ("network", "6543:15649", "S59"),
            ("performance", "6571:15958", "S60"), ("recording", "6571:16429", "S61"),
            ("extensions", "6575:17137", "S62"),
        ]
        var entries: [GalleryEntry] = frames.map { categoryID, node, screen in
            GalleryEntry(id: "S48.Settings/\(categoryID)", title: "Settings — \(categoryID.capitalized)",
                         size: Theme.Metric.Dialogs.settings.size, figmaNode: node, screens: ["S48", screen, "S63"],
                         notes: "Schema-driven rows. Corrected catalog labels and options may differ from the Figma copy.", renderEngine: .hostingView,
                         figmaDeviations: figmaDeviations[categoryID] ?? []) {
                let app = AppModel.mock(.idle)
                app.settings.select(categoryID: categoryID)
                if categoryID == "performance" { app.settings.expandedAdvanced.insert(categoryID) }
                // 3191:18745 illustrates 50% opacity; VLC's catalog default is fully opaque.
                if categoryID == "subtitles" {
                    app.settings.setValue(.integer(128), for: SettingsRow(option: "freetype-opacity", control: .slider, label: "Text opacity"))
                }
                return MXRSettingsView().appModel(app)
            }
        }
        // D032: every category in the Light theme too (the app's own theme setting wins over
        // `--scheme`, so these set it). General's Light entry is below.
        entries += frames.map(\.0).filter { $0 != "general" }.map { categoryID in
            GalleryEntry(id: "S48.Settings/\(categoryID)-light", title: "Settings — \(categoryID.capitalized) light",
                         size: Theme.Metric.Dialogs.settings.size, screens: ["S48", "S50"], colorScheme: .light, renderEngine: .hostingView) {
                let app = AppModel.mock(.idle)
                app.appearance.setTheme(.light)
                app.settings.select(categoryID: categoryID)
                return MXRSettingsView().appModel(app)
            }
        }
        entries += [
            GalleryEntry(id: "S48.App/settings-light", title: "Settings — over the player, Light theme", size: Theme.Metric.Window.player.size,
                         screens: ["S48", "S50"], colorScheme: .light, renderEngine: .hostingView) {
                let app = AppModel.mock(.pausedEpisode)
                app.appearance.setTheme(.light)
                app.interface.present(.settings(categoryID: nil))
                return ShippingGallery.host(app) { MXRAppView(videoView: PlayerGallery.catVideo(), onPictureInPicture: {}) }
            },
            GalleryEntry(id: "S48.Settings/general-advanced", title: "Settings — General advanced", size: Theme.Metric.Dialogs.settings.size,
                         figmaNode: "3046:9282", screens: ["S48", "S49"], renderEngine: .hostingView,
                         figmaDeviations: figmaDeviations["general-advanced"] ?? []) {
                let app = AppModel.mock(.idle)
                app.settings.expandedAdvanced.insert("general")
                return MXRSettingsView().appModel(app)
            },
            GalleryEntry(id: "S48.Settings/general-light", title: "Settings — General light", size: Theme.Metric.Dialogs.settings.size,
                         screens: ["S48", "S50"], colorScheme: .light, renderEngine: .hostingView) {
                let app = AppModel.mock(.idle)
                app.appearance.setTheme(.light)
                return MXRSettingsView().appModel(app)
            },
            GalleryEntry(id: "S48.Settings/search", title: "Settings — Search all categories", size: Theme.Metric.Dialogs.settings.size,
                         screens: ["S48"], renderEngine: .hostingView) {
                let app = AppModel.mock(.idle)
                app.settings.searchText = "subtitle"
                return MXRSettingsView().appModel(app)
            },
            GalleryEntry(id: "S48.Settings/compact", title: "Settings — 960 × 540 host", size: .init(width: 960, height: 540),
                         screens: ["S48"], renderEngine: .hostingView) {
                MXRSettingsView().appModel(AppModel.mock(.idle))
            },
            GalleryEntry(id: "S48.Settings/narrow", title: "Settings — 480 × 540 host", size: .init(width: 480, height: 540),
                         screens: ["S48"], renderEngine: .hostingView) {
                MXRSettingsView(categoryID: "audio").appModel(AppModel.mock(.idle))
            },
            GalleryEntry(id: "S48.App/settings", title: "Settings — over the player (shipping composition)", size: Theme.Metric.Window.player.size,
                         screens: ["S48", "S49"], notes: "D030/SD-11: MXRAppView presents Settings centred in the window; the layer behind catches clicks and draws nothing (D035).",
                         renderEngine: .hostingView) {
                let app = AppModel.mock(.pausedEpisode)
                app.interface.present(.settings(categoryID: nil))
                return ShippingGallery.host(app) { MXRAppView(videoView: PlayerGallery.catVideo(), onPictureInPicture: {}) }
            },
            GalleryEntry(id: "S48.App/settings-compact", title: "Settings — 960 × 540 window", size: CGSize(width: 960, height: 540),
                         screens: ["S48"], notes: "The dialog shrinks to the window and scrolls; nothing is scaled.", renderEngine: .hostingView) {
                let app = AppModel.mock(.pausedEpisode)
                app.interface.present(.settings(categoryID: "controls"))
                return ShippingGallery.host(app) { MXRAppView(videoView: PlayerGallery.catVideo(windowSize: CGSize(width: 960, height: 540)), onPictureInPicture: {}) }
            },
            GalleryEntry(id: "S48.Settings/developer-mode", title: "Settings — General advanced in developer mode", size: Theme.Metric.Dialogs.settings.size,
                         screens: ["S48", "S49"], renderEngine: .hostingView) {
                let app = AppModel.mock(.idle)
                app.settings.setValue(.bool(true), for: SettingsRow(option: "macosx-redesign-developer-mode", control: .toggle, label: "Developer mode"))
                app.settings.expandedAdvanced.insert("general")
                return MXRSettingsView().appModel(app)
            },
            GalleryEntry(id: "S48.Settings/unavailable-subtitle-features", title: "Settings — Subtitle features the renderer lacks are hidden",
                         size: Theme.Metric.Dialogs.settings.size, screens: ["S48", "S57"],
                         notes: "D035: rows the engine does not provide are hidden, not listed as unavailable.", renderEngine: .hostingView) {
                let app = AppModel.mock(.idle)
                let settings = SettingsModel(backend: MissingSettingsMetadataPreview(base: app.settings.backend,
                    missing: ["macosx-redesign-sub-size-mode", "macosx-redesign-sub-pixel-size",
                              "macosx-redesign-sub-position", "macosx-redesign-sub-ignore-styles"]))
                settings.select(categoryID: "subtitles")
                return MXRSettingsView().environment(settings).appModel(app)
            },
            GalleryEntry(id: "S48.Settings/extensions-populated", title: "Settings — Installed extensions", size: Theme.Metric.Dialogs.settings.size,
                         screens: ["S62"], renderEngine: .hostingView) {
                let mock = MockBackend(scenario: .idle)
                mock.extensions.seedSamples()
                let app = mock.makeAppModel()
                app.settings.select(categoryID: "extensions")
                return MXRSettingsView().appModel(app)
            },
            GalleryEntry(id: "S48.Settings/extensions-unavailable", title: "Settings — Extension operation availability", size: Theme.Metric.Dialogs.settings.size,
                         screens: ["S62"], notes: "D035: operations this build cannot perform (catalog, local management, enabling) are hidden, not explained.", renderEngine: .hostingView) {
                let mock = MockBackend(scenario: .idle)
                mock.extensions.seedSamples()
                let app = mock.makeAppModel()
                app.settings.select(categoryID: "extensions")
                let extensions = ExtensionsModel(backend: UnavailableExtensionOperationsPreview(base: mock.extensions))
                extensions.selection = "vlsub"
                return MXRSettingsView().environment(extensions).appModel(app)
            },
            GalleryEntry(id: "S48.Settings/extensions-on-demand", title: "Settings — Run an on-demand extension", size: Theme.Metric.Dialogs.settings.size,
                         screens: ["S62"], renderEngine: .hostingView) {
                let mock = MockBackend(scenario: .idle)
                let app = mock.makeAppModel()
                app.settings.select(categoryID: "extensions")
                let extensions = ExtensionsModel(backend: UnavailableExtensionOperationsPreview(base: mock.extensions, onDemandID: "run-once"))
                return MXRSettingsView().environment(extensions).appModel(app)
            },
            GalleryEntry(id: "S64.KeyboardShortcuts/default", title: "Keyboard Shortcuts", size: Theme.Metric.Dialogs.keyboardShortcuts.size,
                         figmaNode: "2437:14832", screens: ["S64"], renderEngine: .hostingView) {
                MXRKeyboardShortcutsView().appModel(AppModel.mock(.idle))
            },
            // The shipping state: VLC has no global hotkeys on macOS (D035), so the column is absent.
            GalleryEntry(id: "S64.KeyboardShortcuts/this-mac", title: "Keyboard Shortcuts — this Mac (no Global Hotkey column)",
                         size: Theme.Metric.Dialogs.keyboardShortcuts.size, screens: ["S64"], renderEngine: .hostingView) {
                let b = MockBackend(scenario: .idle).backends
                let backends = Backends(player: b.player, clock: b.clock, queue: b.queue, library: b.library, mediaSources: b.mediaSources,
                                        settings: b.settings, shortcuts: b.shortcuts, dialogs: b.dialogs, extensions: b.extensions,
                                        thumbnails: b.thumbnails, osd: b.osd,
                                        capabilities: BackendCapabilities(supportsGlobalHotkeys: false),
                                        output: b.output, renderers: b.renderers, quitHandler: b.quitHandler)
                let app = AppModel(backends: backends, persistence: .inMemory, settingsCatalog: .bundled, clockTicks: false)
                return MXRKeyboardShortcutsView().appModel(app)
            },
            GalleryEntry(id: "S64.KeyboardShortcuts/edited-conflict", title: "Keyboard Shortcuts — Draft conflict", size: Theme.Metric.Dialogs.keyboardShortcuts.size,
                         screens: ["S64"], renderEngine: .hostingView) {
                let app = AppModel.mock(.idle)
                app.shortcuts.setBinding(KeyBinding(key: "f"), for: "play-pause")
                return MXRKeyboardShortcutsView().appModel(app)
            },
            GalleryEntry(id: "S64.KeyboardShortcuts/search", title: "Keyboard Shortcuts — Search", size: Theme.Metric.Dialogs.keyboardShortcuts.size,
                         screens: ["S64"], renderEngine: .hostingView) {
                let app = AppModel.mock(.idle)
                app.shortcuts.searchText = "volume"
                return MXRKeyboardShortcutsView().appModel(app)
            },
            GalleryEntry(id: "S64.KeyboardShortcuts/compact", title: "Keyboard Shortcuts — 960 × 540 host", size: .init(width: 960, height: 540),
                         screens: ["S64"], renderEngine: .hostingView) {
                MXRKeyboardShortcutsView().appModel(AppModel.mock(.idle))
            },
            GalleryEntry(id: "S64.KeyboardShortcuts/nested-narrow", title: "Keyboard Shortcuts — 470 × 800 nested sheet", size: .init(width: 470, height: 800),
                         screens: ["S64"], renderEngine: .hostingView) {
                let app = AppModel.mock(.idle)
                app.shortcuts.searchText = "Increase volume"
                return MXRKeyboardShortcutsView().appModel(app)
            },
            GalleryEntry(id: "S64.KeyboardShortcuts/narrow-minimum", title: "Keyboard Shortcuts — 320 × 540 host", size: .init(width: 320, height: 540),
                         screens: ["S64"], renderEngine: .hostingView) {
                let app = AppModel.mock(.idle)
                app.shortcuts.searchText = "Increase volume"
                return MXRKeyboardShortcutsView().appModel(app)
            },
        ]
        return entries
    }
}

@MainActor
private final class UnavailableExtensionOperationsPreview: ExtensionsBackend, ExtensionsAvailabilityBackend, ExtensionRunningBackend {
    let base: any ExtensionsBackend
    let onDemandID: String?
    private var runCount = 0
    private let events = EventChannel<ExtensionsEvent>()
    init(base: any ExtensionsBackend, onDemandID: String? = nil) { self.base = base; self.onDemandID = onDemandID }
    var extensions: [ExtensionInfo] {
        guard let onDemandID else { return base.extensions }
        return base.extensions + [ExtensionInfo(id: onDemandID, title: "On-demand script", summary: runCount == 0 ? "Runs once when requested." : "Executed \(runCount) times.")]
    }
    func availability(for operation: ExtensionOperation, extensionID: String?) -> ExtensionAvailability {
        switch operation {
        case .activate: extensionID == onDemandID && onDemandID != nil ? .unavailable("This extension runs on demand and cannot be enabled.") : .available
        case .run: extensionID == onDemandID && onDemandID != nil ? .available : .unavailable(operation.unavailableReason)
        case .installLocal, .removeLocal: .unavailable("The user extension folder is not writable.")
        default: .unavailable(operation.unavailableReason)
        }
    }
    func activate(id: String) { base.activate(id: id) }
    func deactivate(id: String) { base.deactivate(id: id) }
    func menu(forExtension id: String) -> [ExtensionMenuItem] { base.menu(forExtension: id) }
    func triggerMenu(extensionID: String, itemID: UInt16) { base.triggerMenu(extensionID: extensionID, itemID: itemID) }
    func searchAddons(_ text: String) async throws -> [AddonInfo] { try await base.searchAddons(text) }
    func installAddon(id: String) async throws { try await base.installAddon(id: id) }
    func removeAddon(id: String) async throws { try await base.removeAddon(id: id) }
    func installExtension(fileURL: URL) async throws { try await base.installExtension(fileURL: fileURL) }
    func runExtension(id: String) async throws {
        guard id == onDemandID else { throw BackendOperationError.invalidInput("Select an on-demand extension to run.") }
        runCount += 1
        events.send(.activationChanged(id))
    }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (ExtensionsEvent) -> Void) {
        base.addListener(owner, handler: handler)
        events.add(owner, handler: handler)
    }
}

/// Keeps stored values while withholding an unimplemented capability's metadata.
/// This exercises the same unavailable parent/dependent state as the native settings service.
@MainActor
private final class MissingSettingsMetadataPreview: SettingsBackend {
    let base: any SettingsBackend
    let missing: Set<String>
    init(base: any SettingsBackend, missing: Set<String>) { self.base = base; self.missing = missing }
    func option(named name: String) -> SettingOption? { missing.contains(name) ? nil : base.option(named: name) }
    func value(for name: String) -> SettingValue? { base.value(for: name) }
    func setValue(_ value: SettingValue, for name: String, apply: SettingsApply) { base.setValue(value, for: name, apply: apply) }
    func resetValue(for name: String) { base.resetValue(for: name) }
    func resetAll() { base.resetAll() }
    func save() { base.save() }
    func dynamicChoices(for name: String) async -> [SettingChoice] { await base.dynamicChoices(for: name) }
    var allOptionNames: [String] { base.allOptionNames.filter { !missing.contains($0) } }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (SettingsEvent) -> Void) { base.addListener(owner, handler: handler) }
}
