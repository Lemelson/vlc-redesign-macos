import Foundation

/// Hardware identifiers stay opaque to the UI: auhal uses numeric AudioObjectID text,
/// while video capture uses AVFoundation's unique device ID.
public struct MediaDevice: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }

    /// Preserve explicit selection; automatically choose only an unambiguous camera.
    public static func captureSelection(currentID: String, devices: [MediaDevice]) -> String {
        currentID.isEmpty && devices.count == 1 ? devices[0].id : currentID
    }
}

public enum MediaDeviceKind: Hashable, Sendable, CaseIterable {
    case audioOutput
    case videoCapture
}
