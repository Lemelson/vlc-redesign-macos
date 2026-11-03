import Foundation
import MXRBridgeAPI
import MXRCore

/// Sparkle through the Objective-C bridge (D059). Sparkle owns the values: its permission
/// question and update window change them too, and the sink reports every change.
@MainActor
final class VLCUpdaterBackend: NSObject, UpdaterBackend, MXRUpdaterEventSink {
    private let bridge: MXRUpdaterBridge
    private let events = EventChannel<Void>()

    init(bridge: MXRUpdaterBridge) {
        self.bridge = bridge
        super.init()
        bridge.sink = self
    }

    var automaticallyChecks: Bool {
        get { bridge.automaticallyChecksForUpdates }
        set { bridge.automaticallyChecksForUpdates = newValue }
    }
    var automaticallyInstalls: Bool {
        get { bridge.automaticallyDownloadsUpdates }
        set { bridge.automaticallyDownloadsUpdates = newValue }
    }
    var canCheckForUpdates: Bool { bridge.canCheckForUpdates }
    var lastCheckDate: Date? { bridge.lastUpdateCheckDate }
    func checkForUpdates() { bridge.checkForUpdates() }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor () -> Void) { events.add(owner) { _ in handler() } }
    func updaterDidChange() { events.send(()) }
}
