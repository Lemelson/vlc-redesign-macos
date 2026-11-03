import Foundation
import MXRBridgeAPI
import XCTest
@testable import MXRVLCBackend

/// Live crash (final5/live/7-library, VLC-2026-10-17-085212.ips): dismissing an engine dialog sent
/// its id as a String. -[MXRDialogServices performCommand:] reads `[args[@"id"] unsignedLongLongValue]`,
/// which NSString does not implement, so an NSInvalidArgumentException unwound through a MainActor
/// task. AppKit swallowed it, Swift's executor tracking was left pointing at a dead frame, and the
/// next SwiftUI tooltip hit-test (MainActor.assumeIsolated) crashed on it.
@MainActor
final class DialogBridgeArgumentTests: XCTestCase {
    func testEveryDialogAnswerSendsAnIDTheObjectiveCBridgeCanRead() throws {
        let transport = DialogWireTransport()
        let backend = VLCDialogBackend(transport: transport)
        let id: UInt64 = 7
        backend.dismiss(id: id)
        backend.postAction(id: id, action: 1)
        backend.postLogin(id: id, username: "u", password: "p", store: false)
        XCTAssertEqual(transport.sent.map(\.0), [.dismiss, .postAction, .postLogin])
        for (command, arguments) in transport.sent {
            // Exactly what the ObjC side receives: the Swift dictionary bridged to NSDictionary.
            let bridged = arguments as NSDictionary
            let value = try XCTUnwrap(bridged["id"] as AnyObject?, "\(command.rawValue) sends an id")
            XCTAssertTrue(value.responds(to: NSSelectorFromString("unsignedLongLongValue")),
                          "\(command.rawValue): the bridge messages unsignedLongLongValue; \(type(of: value)) would raise")
            XCTAssertEqual((value as? NSNumber)?.uint64Value, id)
        }
    }
}

@MainActor
private final class DialogWireTransport: VLCServiceTransport {
    var capabilities: [String: Any] { [:] }
    var sent: [(MXRBridgeCommand, [String: Any])] = []
    func snapshot(for service: MXRBridgeService) -> [String: Any] { [:] }
    func perform(_ command: MXRBridgeCommand, service: MXRBridgeService, arguments: [String: Any]) throws {
        if service == .dialogs { sent.append((command, arguments)) }
    }
    func request(_ request: MXRBridgeRequest, service: MXRBridgeService, arguments: [String: Any]) async throws -> [String: Any] { [:] }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MXRBridgeService) -> Void) {}
    func log(_ error: Error) {}
    func report(_ error: Error) {}
}
