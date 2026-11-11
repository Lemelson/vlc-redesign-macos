import Foundation
import Testing
@testable import MXRCore

/// GitHub issue #2: a folder macOS blocks must be reported, not silently dropped from the library.
struct LibraryAccessTests {
    let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    func url(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

    @Test func blockedMusicLibraryInsideARootIsReported() {
        let problems = LibraryAccessCheck.problems(roots: [url("/Users/someone/Music")], home: home,
            isReadable: { $0.path != "/Users/someone/Music/Music" })
        #expect(problems == [LibraryAccessProblem(folder: url("/Users/someone/Music/Music"), kind: .mediaLibrary)])
        #expect(problems[0].settingsURL.absoluteString.hasSuffix("Privacy_Media"))
    }

    @Test func readableContainersAreNotProblems() {
        #expect(LibraryAccessCheck.problems(roots: [url("/Users/someone/Music")], home: home,
                                            isReadable: { _ in true }).isEmpty)
    }

    @Test func blockedRootIsReportedWithItsPane() {
        let photos = LibraryAccessCheck.problems(roots: [url("/Users/someone/Pictures/Photos Library.photoslibrary/originals")],
            home: home, isReadable: { _ in false })
        #expect(photos.map(\.kind) == [.photos])
        let desktop = LibraryAccessCheck.problems(roots: [url("/Users/someone/Desktop")], home: home,
            isReadable: { _ in false })
        #expect(desktop.map(\.kind) == [.folder])
        #expect(desktop[0].settingsURL.absoluteString.hasSuffix("Privacy_FilesAndFolders"))
    }

    @Test func containersOutsideTheRootsAreNotRead() {
        var read: [String] = []
        _ = LibraryAccessCheck.problems(roots: [url("/Users/someone/Movies/Films")], home: home,
            isReadable: { read.append($0.path); return true })
        #expect(read == ["/Users/someone/Movies/Films"])
    }

    /// A container is checked with opendir alone: macOS may refuse even stat() on a blocked folder,
    /// so a fileExists pre-check skipped exactly the folders it was meant to report. Missing ones
    /// (ENOENT) are still not problems.
    @Test func missingContainersOnDiskAreNotProblems() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("mxr-access-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Music"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(LibraryAccessCheck.problems(roots: [home], home: home).isEmpty)
    }

    @Test func missingFolderIsNotAPrivacyProblem() {
        #expect(LibraryAccessCheck.isReadable(URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")))
    }
}
