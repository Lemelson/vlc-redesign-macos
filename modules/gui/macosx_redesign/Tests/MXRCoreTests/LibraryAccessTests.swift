import Foundation
import Testing
@testable import MXRCore

/// GitHub issue #2: a folder macOS blocks must be reported, not silently dropped from the library.
struct LibraryAccessTests {
    let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    func url(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

    @Test func blockedMusicLibraryInsideARootIsReported() {
        let problems = LibraryAccessCheck.problems(roots: [url("/Users/someone/Music")], home: home,
            exists: { _ in true }, isReadable: { $0.path != "/Users/someone/Music/Music" })
        #expect(problems == [LibraryAccessProblem(folder: url("/Users/someone/Music/Music"), kind: .mediaLibrary)])
        #expect(problems[0].settingsURL.absoluteString.hasSuffix("Privacy_Media"))
    }

    @Test func readableOrMissingContainersAreNotProblems() {
        #expect(LibraryAccessCheck.problems(roots: [url("/Users/someone/Music")], home: home,
                                            exists: { _ in true }, isReadable: { _ in true }).isEmpty)
        #expect(LibraryAccessCheck.problems(roots: [url("/Users/someone/Movies")], home: home,
                                            exists: { _ in false }, isReadable: { _ in false } ).count == 1)
    }

    @Test func blockedRootIsReportedWithItsPane() {
        let photos = LibraryAccessCheck.problems(roots: [url("/Users/someone/Pictures/Photos Library.photoslibrary/originals")],
            home: home, exists: { _ in true }, isReadable: { _ in false })
        #expect(photos.map(\.kind) == [.photos])
        let desktop = LibraryAccessCheck.problems(roots: [url("/Users/someone/Desktop")], home: home,
            exists: { _ in true }, isReadable: { _ in false })
        #expect(desktop.map(\.kind) == [.folder])
        #expect(desktop[0].settingsURL.absoluteString.hasSuffix("Privacy_FilesAndFolders"))
    }

    @Test func containersOutsideTheRootsAreNotRead() {
        var read: [String] = []
        _ = LibraryAccessCheck.problems(roots: [url("/Users/someone/Movies/Films")], home: home,
            exists: { _ in true }, isReadable: { read.append($0.path); return true })
        #expect(read == ["/Users/someone/Movies/Films"])
    }

    @Test func missingFolderIsNotAPrivacyProblem() {
        #expect(LibraryAccessCheck.isReadable(URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")))
    }
}
