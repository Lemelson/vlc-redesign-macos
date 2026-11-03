import Foundation
import XCTest

/// Source files the contract tests read. Package files are found next to this file, so they also
/// resolve in an isolated copy of the package. VLC's own sources (`src/…`) live in the repository
/// above the package: `$MXR_REPO_ROOT`, else the directories above the package; a copy outside the
/// repository skips those tests with the reason instead of failing on a missing file.
enum TestSourceFiles {
    /// modules/gui/macosx_redesign.
    static let packageDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func package(_ relative: String) -> URL { packageDirectory.appendingPathComponent(relative) }

    /// A file of the VLC repository (e.g. "src/libvlc-module.c").
    static func repository(_ relative: String) throws -> URL {
        let marker = "src/libvlc-module.c"
        var starts: [URL] = []
        if let env = ProcessInfo.processInfo.environment["MXR_REPO_ROOT"], !env.isEmpty {
            starts.append(URL(fileURLWithPath: env, isDirectory: true))
        }
        starts.append(packageDirectory)
        for start in starts {
            if let root = ancestor(of: start, containing: marker) { return root.appendingPathComponent(relative) }
        }
        throw XCTSkip("VLC's \(marker) is not above \(packageDirectory.path); set MXR_REPO_ROOT to the repository")
    }

    /// The nearest directory at or above `start` that contains `marker`; stops at the file system root.
    static func ancestor(of start: URL, containing marker: String) -> URL? {
        var dir = start.standardizedFileURL
        while true {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(marker).path) { return dir }
            let parent = dir.deletingLastPathComponent().standardizedFileURL
            if parent.path == dir.path || dir.path == "/" { return nil }
            dir = parent
        }
    }
}
