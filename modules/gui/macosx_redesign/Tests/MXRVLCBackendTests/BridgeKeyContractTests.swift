import Foundation
import XCTest

/// ARC-14 (interim): Swift reads the bridge through the shared key constants of
/// `MXRBridgeKeys.h`. A key that no Objective-C producer writes is a silent default on the
/// Swift side (the review found `snapshotURL`, `isPictureInPicture`, `external`, ... read but
/// never written). This contract fails as soon as a shared key loses its producer.
final class BridgeKeyContractTests: XCTestCase {
    private static let moduleRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: Self.moduleRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    /// The constant names declared for one key family, e.g. `MXRPlayerKeyState`.
    private func constants(_ type: String, in keys: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "\(type) const (\(type)[A-Za-z]+) =")
        return pattern.matches(in: keys, range: NSRange(keys.startIndex..., in: keys)).compactMap {
            Range($0.range(at: 1), in: keys).map { String(keys[$0]) }
        }
    }

    func testEverySharedPlayerAndOSDKeyHasANativeProducer() throws {
        let keys = try source("Sources/MXRBridgeAPI/MXRBridgeKeys.m")
        let bridgeDirectory = Self.moduleRoot.appendingPathComponent("module/bridge")
        let producers = try FileManager.default.contentsOfDirectory(at: bridgeDirectory, includingPropertiesForKeys: nil)
            .filter { ["m", "inc"].contains($0.pathExtension) }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let names = constants("MXRPlayerKey", in: keys) + constants("MXROSDKey", in: keys)
        XCTAssertGreaterThan(names.count, 40, "the key header was not parsed")
        for name in names {
            // Written as a dictionary key: `Key:value` in a literal or `d[Key] = value`.
            let written = try NSRegularExpression(pattern: "\(name)\\s*(:|\\]\\s*=)")
            XCTAssertNotNil(written.firstMatch(in: producers, range: NSRange(producers.startIndex..., in: producers)),
                            "\(name) is read by Swift but no bridge source writes it")
        }
    }

    func testProductionBridgeHasNoConditionalHeaderGuards() throws {
        let bridgeDirectory = Self.moduleRoot.appendingPathComponent("module/bridge")
        for file in try FileManager.default.contentsOfDirectory(at: bridgeDirectory, includingPropertiesForKeys: nil)
        where file.pathExtension == "m" {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("__has_include(\"MXR"), "\(file.lastPathComponent) guards its own headers")
        }
    }
}
