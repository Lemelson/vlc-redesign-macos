import Foundation
@testable import MXRGalleryCatalog
import XCTest

/// Critic P2: GalleryPaths' search for the repository marker never ended above some start
/// directories (deletingLastPathComponent() keeps returning "/../.."), so a package copy outside
/// the repository hung FigmaDeviationTests for 36+ minutes instead of asking for MXR_REPO_ROOT.
final class GalleryPathsLocateTests: XCTestCase {
    func testMarkerSearchEndsAtTheFileSystemRoot() {
        let marker = "no-such-marker-\(UUID().uuidString)/figma_file.json"
        var starts = [URL(fileURLWithPath: "/", isDirectory: true), FileManager.default.temporaryDirectory,
                      URL(fileURLWithPath: #filePath).deletingLastPathComponent()]
        if let executable = Bundle.main.executableURL { starts.append(executable.deletingLastPathComponent()) }
        let done = expectation(description: "every search ends")
        let found = Found()
        let searched = starts
        // Off the test's thread, so a search that never ends fails the test instead of hanging it.
        Thread.detachNewThread {
            found.set(searched.compactMap { GalleryPaths.ancestor(of: $0, containing: marker)?.path })
            done.fulfill()
        }
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 10), .completed, "the marker search must stop at /")
        XCTAssertEqual(found.value, [], "no start has the marker above it")
    }

    func testFindsTheRepository() throws {
        let env = ProcessInfo.processInfo.environment["MXR_REPO_ROOT"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        let start = env ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        guard let root = GalleryPaths.ancestor(of: start, containing: "redesign/design/figma/figma_file.json") else {
            throw XCTSkip("no repository above \(start.path) (isolated package copy); set MXR_REPO_ROOT")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "src/libvlc-module.c").path))
    }
}

private final class Found: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String]?
    func set(_ value: [String]) { lock.withLock { paths = value } }
    var value: [String]? { lock.withLock { paths } }
}
