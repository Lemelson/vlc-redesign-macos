import Foundation
import AVFoundation
import MXRCore
import MXRBridgeAPI

/// VLC configuration (ARC-15). The schema (every option's type, range, texts and choices) is read
/// once, at startup: the plugin bank does not change while the app runs. Writing a setting never re-reads the
/// configuration: the bridge reports `settings:<name>` for the one option it changed, and only that
/// value is fetched. A bare `settings` event (reset, effects, bindings) refreshes the values once,
/// coalesced after the current main-loop turn.
@MainActor
final class VLCSettingsBackend: SettingsBackend, SettingsMaintenanceBackend {
    private let transport: any VLCServiceTransport
    /// Cameras only: audio outputs are the engine's own list (below).
    private let deviceDiscovery: @Sendable (MediaDeviceKind) -> [MediaDevice]
    private var values: [String: Any] = [:]
    private var schema: [String: SettingOption] = [:]
    private var configurationPath: String?
    private var userDataPath: String?
    private var pendingRefresh: Task<Void, Never>?
    private let events = EventChannel<SettingsEvent>()

    init(transport: any VLCServiceTransport, deviceDiscovery: @escaping @Sendable (MediaDeviceKind) -> [MediaDevice] = VLCDeviceDiscovery.list) {
        self.transport = transport
        self.deviceDiscovery = deviceDiscovery
        let snapshot = transport.snapshot(for: .settings)
        values = snapshot.dictionary("values")
        configurationPath = snapshot.string("configurationDirectory")
        userDataPath = snapshot.string("userDataDirectory")
        rebuildSchema(snapshot.dictionaries("options"))
        transport.addListener(self) { [weak self] service in self?.serviceChanged(service) }
    }

    var allOptionNames: [String] { schema.keys.sorted() }
    var configurationDirectory: URL? { Self.directory(configurationPath) }
    var userDataDirectory: URL? { Self.directory(userDataPath) }
    private static func directory(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return path.hasPrefix("/") ? URL(fileURLWithPath: path, isDirectory: true) : URL(string: path)
    }
    func option(named name: String) -> SettingOption? { schema[name] }
    func value(for name: String) -> SettingValue? { VLCWire.scalar(values[name], type: schema[name]?.type) }

    func setValue(_ value: SettingValue, for name: String, apply: SettingsApply) {
        let timing: String = switch apply { case .nextMedia: "next-media"; case .restart: "restart"; case .live(let scope): scope }
        transport.command(.set, service: .settings, arguments: ["name": name, "value": VLCWire.foundation(value), "apply": timing])
    }
    func resetValue(for name: String) { transport.command(.reset, service: .settings, arguments: ["name": name]) }
    func resetAll() {
        transport.command(.resetAll, service: .settings)
        refreshValues()
    }
    func save() { transport.command(.save, service: .settings) }
    func availableDevices(for kind: MediaDeviceKind) async -> [MediaDevice] {
        if kind == .audioOutput {
            // The "Output device" row writes `auhal-audio-device`, whose values are the ids auhal
            // reports (aout_DevicesList: the system default "0", device ids, encoded variants).
            // Listing the same engine choices keeps the ids and the shown devices in step (C-11).
            return transport.snapshot(for: .playerDevices).dictionaries(MXRPlayerKey.audioDevices).compactMap { item in
                item.string(MXRPlayerKey.ID).map { MediaDevice(id: $0, name: item.string(MXRPlayerKey.name) ?? $0) }
            }
        }
        let discover = deviceDiscovery
        return await Task.detached(priority: .userInitiated) { discover(kind) }.value
    }

    func dynamicChoices(for name: String) async -> [SettingChoice] {
        do {
            let result = try await transport.request(.dynamicChoices, service: .settings, arguments: ["name": name])
            return Self.parseChoices(result.dictionaries("choices"), type: schema[name]?.type)
        } catch { transport.report(error); return schema[name]?.choices ?? [] }
    }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (SettingsEvent) -> Void) { events.add(owner, handler: handler) }

    // MARK: Change events

    private func serviceChanged(_ service: MXRBridgeService) {
        if service == .playerDevices {
            events.send(.devicesChanged)
        } else if service == .settingsSaveFailed {
            transport.report(NSError(domain: "MXRSettingsPersistence", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Your settings were not saved to disk. Check that the configuration folder is writable and save again."]))
        } else if service == .settings {
            scheduleRefresh()
        } else if let name = service.settingOptionName {
            refreshValue(name)
        }
    }

    private func refreshValue(_ name: String) {
        let fresh = transport.snapshot(for: .settingOption(name))["value"]
        guard !Self.same(values[name], fresh) else { return }
        values[name] = fresh
        events.send(.valueChanged(name))
    }

    private func scheduleRefresh() {
        guard pendingRefresh == nil else { return }
        // The task body runs after the current main-actor turn, so a burst of events coalesces.
        pendingRefresh = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            self.pendingRefresh = nil
            self.refreshValues()
        }
    }

    private func refreshValues() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        apply(values: transport.snapshot(for: .settingsValues).dictionary("values"))
    }

    private func apply(values new: [String: Any]) {
        let old = values
        values = new
        let changed = Set(old.keys).union(new.keys).filter { !Self.same(old[$0], new[$0]) }
        if changed.count > 20 { events.send(.reloaded) }
        else { for key in changed.sorted() { events.send(.valueChanged(key)) } }
    }

    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        NSDictionary(dictionary: ["v": a ?? NSNull()]).isEqual(to: ["v": b ?? NSNull()])
    }

    // MARK: Schema

    private static func parseChoices(_ list: [[String: Any]], type: SettingOptionType?) -> [SettingChoice] {
        list.compactMap { item in VLCWire.scalar(item["value"], type: type).map { SettingChoice(value: $0, title: item.string("title") ?? $0.description) } }
    }

    private func rebuildSchema(_ options: [[String: Any]]) {
        schema = Dictionary(options.compactMap { item -> (String, SettingOption)? in
            guard let name = item.string("name") else { return nil }
            let typeName = item.string("type") ?? "string"
            let type = SettingOptionType(rawValue: typeName == "file" ? "loadFile" : typeName) ?? .string
            let initial = VLCWire.scalar(item["defaultValue"], type: type) ?? .string("")
            let minimum = (item["min"] as? NSNumber)?.doubleValue, maximum = (item["max"] as? NSNumber)?.doubleValue
            let range: ClosedRange<Double>? = if let minimum, let maximum, minimum <= maximum { minimum...maximum } else { nil }
            return (name, SettingOption(name: name, type: type, defaultValue: initial, range: range,
                                        choices: Self.parseChoices(item.dictionaries("choices"), type: type),
                                        text: item.string("text"), longText: item.string("longText"), module: item.string("module")))
        }, uniquingKeysWith: { first, _ in first })
    }
}

/// Device/framework objects remain entirely on the worker; only Sendable IDs and names escape.
private enum VLCDeviceDiscovery {
    static func list(_ kind: MediaDeviceKind) -> [MediaDevice] {
        guard kind == .videoCapture else { return [] }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video, position: .unspecified)
        return discovery.devices.map { MediaDevice(id: $0.uniqueID, name: $0.localizedName) }
    }
}
