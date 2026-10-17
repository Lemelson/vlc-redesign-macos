import Foundation

/// Failures for optional engine operations must reach the calling dialog.
public enum BackendOperationError: LocalizedError {
    case unsupported(String)
    case invalidInput(String)
    public var errorDescription: String? {
        switch self { case .unsupported(let feature): "\(feature) is unavailable in this VLC build."; case .invalidInput(let text): text }
    }
}

/// Opening with per-input options is required for capture, conversion and streaming.
@MainActor
public protocol QueueInputOptionsBackend: AnyObject {
    /// Replaces the queue with `media` and plays `media[index]`. `inputOptions` apply to every
    /// item; `startPaused` only to the started one, so the next items play when the queue
    /// advances to them ("Start playing when opened" off, SET-02).
    func playNow(_ media: [MediaItem], startAt index: Int, inputOptions: [String], startPaused: Bool) throws
}

extension QueueInputOptionsBackend {
    public func playNow(_ media: [MediaItem], startAt index: Int, inputOptions: [String]) throws {
        try playNow(media, startAt: index, inputOptions: inputOptions, startPaused: false)
    }
}

/// Optional maintenance operations which require platform/engine integration.
@MainActor
public protocol SettingsMaintenanceBackend: AnyObject {
    var configurationDirectory: URL? { get }
    /// VLC's per-user data folder (VLC_USERDATA_DIR); user Lua extensions live in `lua/extensions`.
    var userDataDirectory: URL? { get }
}

@MainActor
public protocol LocalExtensionRemovalBackend: AnyObject {
    func removeExtension(id: String) async throws
}
