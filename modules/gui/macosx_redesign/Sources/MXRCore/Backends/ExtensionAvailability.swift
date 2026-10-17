import Foundation

/// Optional extension operations need live engine availability, including the selected script.
public enum ExtensionOperation: String, CaseIterable, Sendable {
    case searchCatalog, installAddon, removeAddon, installLocal, removeLocal, activate, run

    public var unavailableReason: String {
        switch self {
        case .searchCatalog: "The online extension catalog is unavailable in this VLC build."
        case .installAddon: "Installing extensions from the online catalog is unavailable in this VLC build."
        case .removeAddon: "Removing online catalog add-ons is unavailable in this VLC build."
        case .installLocal: "Adding local Lua extensions is unavailable in this VLC build."
        case .removeLocal: "Removing local Lua extensions is unavailable in this VLC build."
        case .activate: "Extension activation is unavailable in this VLC build."
        case .run: "Running on-demand extensions is unavailable in this VLC build."
        }
    }
}

public enum ExtensionAvailability: Equatable, Sendable {
    case available
    case unavailable(String)

    public var isAvailable: Bool { if case .available = self { true } else { false } }
    public var reason: String? { if case .unavailable(let reason) = self { reason } else { nil } }
}

/// Backends opt into each implemented operation. Missing conformance means unavailable.
/// Notify through ExtensionsBackend.addListener when availability changes.
@MainActor
public protocol ExtensionsAvailabilityBackend: AnyObject {
    func availability(for operation: ExtensionOperation, extensionID: String?) -> ExtensionAvailability
}

/// A trigger-only Lua extension executes once instead of remaining enabled.
@MainActor
public protocol ExtensionRunningBackend: AnyObject {
    func runExtension(id: String) async throws
}
