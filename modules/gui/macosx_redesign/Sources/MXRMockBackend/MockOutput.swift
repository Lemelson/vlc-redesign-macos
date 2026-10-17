import Foundation
import MXRCore

// MARK: - Convert and Stream

/// Conversion and streaming as the VLC bridge offers them (MXRMediaServices.m): the same profiles,
/// one job at a time, Stop reports `stopping` until ``finish(_:)`` ends the job. Nothing is written;
/// jobs move only when a test or the Gallery says so.
@MainActor
public final class MockOutput: OutputBackend {
    private let events = EventChannel<Void>()
    public var isAvailable = true { didSet { events.send(()) } }
    public private(set) var jobs: [OutputJob] = []
    public let profiles: [OutputProfile] = [
        OutputProfile(id: "copy", title: "Keep original codecs (MPEG-TS)", fileExtension: "ts"),
        OutputProfile(id: "h264", title: "H.264 video + AAC audio", fileExtension: "mp4"),
        OutputProfile(id: "audio", title: "MP3 audio", fileExtension: "mp3"),
        OutputProfile(id: "aac", title: "AAC audio", fileExtension: "m4a"),
        OutputProfile(id: "wav", title: "WAV audio", fileExtension: "wav"),
    ]
    /// A fixed Bonjour name, so renders of a running HTTP stream do not show the build machine's.
    public var localHostName: String? = "Studio-Mac"
    /// Destinations that already exist; converting to one without `overwrite` fails like VLC (EEXIST).
    public var existingDestinations: Set<URL> = []
    private var nextID = 1

    public init() {}

    public func start(sourceURL: URL, destinationURL: URL?, streamURL: URL?, mode: OutputMode, profile: String, overwrite: Bool) async throws -> OutputJob {
        guard isAvailable else { throw BackendOperationError.unsupported("Conversion and streaming") }
        guard profiles.contains(where: { $0.id == profile }) else { throw BackendOperationError.invalidInput("This output profile is unavailable.") }
        guard !jobs.contains(where: { $0.state.isActive }) else { throw BackendOperationError.invalidInput("Stop the current output job first.") }
        if mode == .convert {
            guard let destinationURL else { throw BackendOperationError.invalidInput("Choose a local output file.") }
            if existingDestinations.contains(destinationURL), !overwrite { throw OutputError.destinationExists(destinationURL) }
        } else if streamURL == nil {
            throw BackendOperationError.invalidInput("Use a UDP, RTP or HTTP URL with an explicit port.")
        }
        // The bridge reports a stream's address as the job's destination.
        let job = OutputJob(id: "mock-output-\(nextID)", sourceURL: sourceURL, destinationURL: mode == .convert ? destinationURL : streamURL,
                            mode: mode, profile: profile, state: .running, progress: 0)
        nextID += 1
        jobs.append(job)
        events.send(())
        return job
    }

    public func stop(id: String) throws {
        guard let index = jobs.firstIndex(where: { $0.id == id && $0.state.isActive }) else {
            throw BackendOperationError.invalidInput("The output job is no longer running.")
        }
        jobs[index].state = .stopping
        events.send(())
    }

    /// A job already in progress when the app model is made (Gallery fixtures).
    public func add(_ job: OutputJob) {
        jobs.append(job)
        events.send(())
    }

    /// Moves a job forward: progress while it runs, then its final state (tests and Gallery).
    public func update(_ id: String, state: OutputJobState, progress: Double? = nil, error: String? = nil) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = state
        if let progress { jobs[index].progress = progress }
        if state == .completed { jobs[index].progress = 1 }
        jobs[index].error = error
        if state == .completed, let destination = jobs[index].destinationURL { existingDestinations.insert(destination) }
        events.send(())
    }

    /// Ends a job the way the bridge does after the engine stopped: a stopped job is cancelled.
    public func finish(_ id: String) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        update(id, state: job.state == .stopping ? .cancelled : .completed)
    }

    public func addListener(_ owner: AnyObject, handler: @escaping @MainActor () -> Void) { events.add(owner) { _ in handler() } }
}

// MARK: - Renderers

/// Chromecast and other renderers as fixtures. Discovery finds ``discoverable`` and then stops
/// discovering; nothing is listed until it runs, like VLC.
@MainActor
public final class MockRenderers: RendererBackend {
    private let events = EventChannel<Void>()
    public private(set) var items: [RendererInfo] = []
    public private(set) var selectedID: String?
    public private(set) var isDiscovering = false
    /// What a discovery finds.
    public var discoverable: [RendererInfo] = []

    public init() {}

    public func discover() async throws {
        isDiscovering = true
        events.send(())
        // Rediscovery keeps the renderer in use, as the bridge does.
        let selected = items.first { $0.id == selectedID }
        items = discoverable
        if let selected, !items.contains(where: { $0.id == selected.id }) { items.append(selected) }
        isDiscovering = false
        events.send(())
    }

    public func select(id: String?) throws {
        guard id == nil || items.contains(where: { $0.id == id }) else { throw BackendOperationError.invalidInput("This renderer is no longer available.") }
        selectedID = id
        events.send(())
    }

    public func addListener(_ owner: AnyObject, handler: @escaping @MainActor () -> Void) { events.add(owner) { _ in handler() } }
}
