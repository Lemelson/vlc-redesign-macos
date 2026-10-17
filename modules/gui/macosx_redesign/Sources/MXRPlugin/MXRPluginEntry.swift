// MXRPluginEntry.swift: C entry points called by module/MXRIntf.m (ARCHITECTURE.md §2.4).
//
// Declared to Objective-C in module/MXRSwiftEntry.h. Both run on the main thread: MXRSwiftStart
// from the setup block MXROpenIntf schedules before [NSApp run], MXRSwiftStop from MXRCloseIntf.

import AppKit
import MXRBridgeAPI
import MXRCore
import MXRVLCBackend

@MainActor
enum PluginRuntime {
    static var adapters: VLCBackends?
    static var app: MXRAppController?
}

/// Builds the Swift side. `interfaceBridge` is an unretained `MXRInterfaceBridge *`.
/// Returns 0 on success.
@_cdecl("MXRSwiftStart")
public func MXRSwiftStart(_ interfaceBridge: UnsafeMutableRawPointer) -> Int32 {
    // The Objective-C bootstrap guarantees main-thread execution. Pass the address as a
    // Sendable integer across assumeIsolated's closure boundary under Swift 6.
    let bridgeAddress = UInt(bitPattern: interfaceBridge)
    return MainActor.assumeIsolated {
        guard PluginRuntime.adapters == nil else { return 1 }

        // In the plugin, resources come from VLC.app/Contents/Resources, never Bundle.module
        // (ARCHITECTURE.md §7.6, CORE_API.md §5).
        MXRResources.allowsBundleModuleFallback = false

        let pointer = UnsafeMutableRawPointer(bitPattern: bridgeAddress)!
        let bridge = Unmanaged<MXRInterfaceBridge>.fromOpaque(pointer).takeUnretainedValue()
        let adapters = VLCBackends(bridge: bridge)
        let session = adapters.session
        let model = AppModel(backends: adapters.backends)
        let app = MXRAppController(model: model, session: session)
        PluginRuntime.adapters = adapters
        PluginRuntime.app = app
        app.start()
        session.log("Swift interface started (VLC \(bridge.vlcVersion))", level: .debug)
        return 0
    }
}

/// Tears the Swift side down and drops every reference to the bridge.
@_cdecl("MXRSwiftStop")
public func MXRSwiftStop() {
    MainActor.assumeIsolated {
        PluginRuntime.app?.stop()
        PluginRuntime.adapters?.invalidate()
        PluginRuntime.app = nil
        PluginRuntime.adapters = nil
    }
}
