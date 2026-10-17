import Foundation
import Observation

public enum OutputMode: String, Sendable { case convert, stream }
/// The states the bridge writes (MXRMediaServices.m): `stopping` after Stop until the engine has
/// closed the output, `finishing` after the input ended until the file is in place.
public enum OutputJobState: String, Sendable, CaseIterable {
    case queued, running, stopping, finishing, completed, cancelled, failed
    /// The engine still owns the job: the form stays locked and the main button stops it.
    public var isActive: Bool { [.queued, .running, .stopping, .finishing].contains(self) }
}
public struct OutputJob: Identifiable, Hashable, Sendable {
    public var id: String
    public var sourceURL: URL
    public var destinationURL: URL?
    public var mode: OutputMode
    public var profile: String
    public var state: OutputJobState
    public var progress: Double
    public var error: String?
    public init(id: String, sourceURL: URL, destinationURL: URL? = nil, mode: OutputMode, profile: String, state: OutputJobState, progress: Double, error: String? = nil) {
        self.id = id; self.sourceURL = sourceURL; self.destinationURL = destinationURL; self.mode = mode; self.profile = profile; self.state = state; self.progress = progress; self.error = error
    }
}
public enum OutputError: LocalizedError, Equatable, Sendable {
    /// The conversion would replace a file the user did not confirm replacing (`overwrite` false).
    case destinationExists(URL)
    public var errorDescription: String? {
        switch self { case .destinationExists(let url): "“\(url.lastPathComponent)” already exists." }
    }
}
public struct OutputProfile: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var fileExtension: String
    public init(id: String, title: String, fileExtension: String) { self.id = id; self.title = title; self.fileExtension = fileExtension }
}
@MainActor public protocol OutputBackend: AnyObject {
    var jobs: [OutputJob] { get }
    var profiles: [OutputProfile] { get }
    var isAvailable: Bool { get }
    /// This Mac's Bonjour name (`name` in `name.local`), which other devices open an HTTP stream
    /// at; nil when it is unknown.
    var localHostName: String? { get }
    func start(sourceURL: URL, destinationURL: URL?, streamURL: URL?, mode: OutputMode, profile: String, overwrite: Bool) async throws -> OutputJob
    func stop(id: String) throws
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor () -> Void)
}
@MainActor @Observable public final class OutputModel {
    public private(set) var jobs: [OutputJob] = []
    public var profiles: [OutputProfile] { backend?.profiles ?? [] }
    public var isAvailable: Bool { backend?.isAvailable ?? false }
    public var localHostName: String? { backend?.localHostName }
    @ObservationIgnored private let backend: (any OutputBackend)?
    public init(backend: (any OutputBackend)?) {
        self.backend = backend
        jobs = backend?.jobs ?? []
        backend?.addListener(self) { [weak self] in self?.jobs = self?.backend?.jobs ?? [] }
    }
    @discardableResult public func start(sourceURL: URL, destinationURL: URL? = nil, streamURL: URL? = nil, mode: OutputMode, profile: String, overwrite: Bool = false) async throws -> OutputJob {
        guard let backend else { throw BackendOperationError.unsupported("Conversion and streaming") }
        let job = try await backend.start(sourceURL: sourceURL, destinationURL: destinationURL, streamURL: streamURL, mode: mode, profile: profile, overwrite: overwrite)
        jobs = backend.jobs
        return job
    }
    public func stop(id: String) throws {
        guard let backend else { throw BackendOperationError.unsupported("Conversion and streaming") }
        try backend.stop(id: id)
        jobs = backend.jobs
    }
}

/// Where a conversion writes, and whether VLC may replace a file already there (J-03). Only the
/// name the user confirmed in the save panel, or with Replace, may be replaced without asking: a
/// format change renames the destination, so the new name is not confirmed, and a finished file
/// is the user's, so converting to it again asks first.
public struct ConversionDestination: Equatable, Sendable {
    public private(set) var url: URL?
    private var confirmed: URL?
    public init(url: URL? = nil) { self.url = url }

    /// The save panel returned `url`; it already asked about replacing an existing file.
    public mutating func choose(_ url: URL) { self.url = url; confirmed = url }
    /// The format changed: the destination keeps its name with the format's extension.
    public mutating func changeExtension(to fileExtension: String) {
        url = url.map { $0.deletingPathExtension().appendingPathExtension(fileExtension) }
    }
    /// The user chose Replace for `url` after VLC reported that it exists.
    public mutating func confirmReplacing(_ url: URL) { confirmed = url }
    /// The conversion finished: the file in place is the user's now.
    public mutating func completed() { confirmed = nil }
    /// VLC may replace an existing file at the destination.
    public var mayReplace: Bool { url != nil && url == confirmed }
}
