import Foundation
import MXRBridgeAPI
import MXRCore
import SystemConfiguration

@MainActor
final class VLCOutputBackend: OutputBackend {
    private let transport: any VLCServiceTransport
    private let events = EventChannel<Void>()
    init(transport: any VLCServiceTransport) {
        self.transport = transport
        transport.addListener(self) { [weak self] service in if service == .output { self?.events.send(()) } }
    }
    var isAvailable: Bool { transport.snapshot(for: .output).bool("available") }
    var jobs: [OutputJob] { transport.snapshot(for: .output).dictionaries("jobs").compactMap(Self.job) }
    var localHostName: String? { SCDynamicStoreCopyLocalHostName(nil) as String? }
    var profiles: [OutputProfile] { transport.snapshot(for: .output).dictionaries("profiles").compactMap { x in x.string("id").map { OutputProfile(id: $0, title: x.string("title") ?? $0, fileExtension: x.string("fileExtension") ?? "") } } }
    func start(sourceURL: URL, destinationURL: URL?, streamURL: URL?, mode: OutputMode, profile: String, overwrite: Bool) async throws -> OutputJob {
        var args: [String: Any] = ["sourceURL": sourceURL.absoluteString, "mode": mode.rawValue, "profile": profile, "overwrite": overwrite]
        if let destinationURL { args["destinationURL"] = destinationURL.absoluteString }
        if let streamURL { args["streamURL"] = streamURL.absoluteString }
        let result: [String: Any]
        do { result = try await transport.request(.start, service: .output, arguments: args) }
        catch let error as NSError where error.domain == "MXRVLCBridge" && error.code == Int(EEXIST) && destinationURL != nil {
            throw OutputError.destinationExists(destinationURL!)
        }
        guard let job = Self.job(result.dictionary("job")) ?? Self.job(result) else { throw BackendOperationError.invalidInput("VLC did not return the output job.") }
        events.send(())
        return job
    }
    func stop(id: String) throws { try transport.perform(.stop, service: .output, arguments: ["id": id]); events.send(()) }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor () -> Void) { events.add(owner) { _ in handler() } }
    static func job(_ x: [String: Any]) -> OutputJob? {
        guard let id = x.string("id"), let sourceURL = x.url("sourceURL"), let mode = x.string("mode").flatMap(OutputMode.init(rawValue:)),
              let wireState = x.string("state") else { return nil }
        // A state this interface does not know stays visible as a failure instead of dropping the job,
        // which would unlock the form while the engine may still be writing.
        let state = OutputJobState(rawValue: wireState)
        return OutputJob(id: id, sourceURL: sourceURL, destinationURL: x.url("destinationURL"), mode: mode, profile: x.string("profile") ?? "copy",
                         state: state ?? .failed, progress: min(1, max(0, x.double("progress"))),
                         error: state == nil ? "VLC reported an unknown output state (\(wireState))." : x.string("error"))
    }
}
