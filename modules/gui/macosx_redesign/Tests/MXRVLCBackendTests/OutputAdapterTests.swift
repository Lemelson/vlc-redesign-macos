import Foundation
import MXRBridgeAPI
import MXRCore
@testable import MXRVLCBackend
import XCTest

/// The output adapter against what MXRMediaServices.m writes (J-05, J-03).
@MainActor
final class OutputAdapterTests: XCTestCase {
    /// Every state string the bridge assigns to `record[@"state"]`.
    static let bridgeStates = ["queued", "running", "stopping", "finishing", "completed", "cancelled", "failed"]

    private func record(_ state: String) -> [String: Any] {
        ["id": "job", "sourceURL": "file:///tmp/in.mp4", "destinationURL": "file:///tmp/out.mp4", "mode": "convert",
         "profile": "h264", "state": state, "progress": 0.5]
    }

    func testEveryBridgeStateDecodesAndStopKeepsTheJobActive() throws {
        for state in Self.bridgeStates {
            let job = try XCTUnwrap(VLCOutputBackend.job(record(state)), "\(state) must decode")
            XCTAssertEqual(job.state.rawValue, state)
            XCTAssertNil(job.error)
        }
        // After Stop the engine is still closing the output: the form must stay locked.
        XCTAssertTrue(try XCTUnwrap(VLCOutputBackend.job(record("stopping"))).state.isActive)
        XCTAssertFalse(try XCTUnwrap(VLCOutputBackend.job(record("cancelled"))).state.isActive)
        XCTAssertEqual(Set(OutputJobState.allCases.map(\.rawValue)), Set(Self.bridgeStates))
    }

    func testUnknownStateStaysVisibleAsAFailure() throws {
        let job = try XCTUnwrap(VLCOutputBackend.job(record("paused")), "a job is never dropped for its state")
        XCTAssertEqual(job.state, .failed)
        XCTAssertEqual(job.error, "VLC reported an unknown output state (paused).")
    }

    func testExistingDestinationBecomesATypedError() async {
        let transport = OutputTransport()
        transport.failure = NSError(domain: "MXRVLCBridge", code: Int(EEXIST), userInfo: [NSLocalizedDescriptionKey: "The output file already exists."])
        let backend = VLCOutputBackend(transport: transport)
        let destination = URL(fileURLWithPath: "/tmp/movie.mp3")
        do {
            _ = try await backend.start(sourceURL: URL(fileURLWithPath: "/tmp/movie.mp4"), destinationURL: destination, streamURL: nil,
                                        mode: .convert, profile: "audio", overwrite: false)
            XCTFail("an existing destination must not start")
        } catch {
            XCTAssertEqual(error as? OutputError, .destinationExists(destination))
        }
        XCTAssertEqual(transport.lastArguments["overwrite"] as? Bool, false)
    }
}

@MainActor
private final class OutputTransport: VLCServiceTransport {
    var failure: Error?
    var lastArguments: [String: Any] = [:]
    var capabilities: [String: Any] { [:] }
    func snapshot(for service: MXRBridgeService) -> [String: Any] { [:] }
    func perform(_ command: MXRBridgeCommand, service: MXRBridgeService, arguments: [String: Any]) throws {}
    func request(_ request: MXRBridgeRequest, service: MXRBridgeService, arguments: [String: Any]) async throws -> [String: Any] {
        lastArguments = arguments
        if let failure { throw failure }
        return [:]
    }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MXRBridgeService) -> Void) {}
    func log(_ error: Error) {}
    func report(_ error: Error) {}
}
