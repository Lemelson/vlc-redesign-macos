import Foundation

/// A library folder macOS does not let the app read (privacy, TCC), so its files are missing from
/// the library instead of shown. VLC's media library drops what it cannot read without telling
/// anyone; the library shows this so a "Don't Allow" never looks like an empty or broken library
/// (GitHub issue #2).
public struct LibraryAccessProblem: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// ~/Music/Music or ~/Movies/TV: System Settings ▸ Privacy & Security ▸ Media & Apple Music.
        case mediaLibrary
        /// The Photos library package under ~/Pictures: Privacy & Security ▸ Photos.
        case photos
        /// Any other folder (Desktop, Documents, Downloads, external and network volumes): Files & Folders.
        case folder
    }

    public var folder: URL
    public var kind: Kind
    public var id: String { folder.path }

    public init(folder: URL, kind: Kind) {
        self.folder = folder
        self.kind = kind
    }

    /// The pane of System Settings where the user turns access back on.
    public var settingsURL: URL {
        let anchor = switch kind {
        case .mediaLibrary: "Privacy_Media"
        case .photos: "Privacy_Photos"
        case .folder: "Privacy_FilesAndFolders"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}

public enum LibraryAccessCheck {
    /// Containers that macOS guards per app inside ordinary home folders.
    public static func protectedContainers(home: URL) -> [(url: URL, kind: LibraryAccessProblem.Kind)] {
        [(home.appendingPathComponent("Music/Music", isDirectory: true), .mediaLibrary),
         (home.appendingPathComponent("Movies/TV", isDirectory: true), .mediaLibrary),
         (home.appendingPathComponent("Pictures/Photos Library.photoslibrary", isDirectory: true), .photos)]
    }

    /// True unless listing `url` fails with EPERM, the error macOS privacy protection returns.
    /// A missing folder or plain Unix permissions (EACCES) are not a privacy problem.
    public static func isReadable(_ url: URL) -> Bool {
        guard let directory = opendir(url.path) else { return errno != EPERM }
        closedir(directory)
        return true
    }

    /// Problems for the library's root folders: a root the app cannot read at all, or a protected
    /// container inside a root. May block while macOS shows its permission prompt: call it off the
    /// main thread.
    public static func problems(roots: [URL], home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                isReadable: (URL) -> Bool = LibraryAccessCheck.isReadable) -> [LibraryAccessProblem] {
        let containers = protectedContainers(home: home)
        var found: [LibraryAccessProblem] = []
        func add(_ problem: LibraryAccessProblem) {
            if !found.contains(where: { $0.folder.standardizedFileURL == problem.folder.standardizedFileURL }) { found.append(problem) }
        }
        for root in roots where root.isFileURL {
            let rootPath = root.standardizedFileURL.path
            if !isReadable(root) {
                let owner = containers.first { rootPath == $0.url.standardizedFileURL.path || rootPath.hasPrefix($0.url.standardizedFileURL.path + "/") }
                add(LibraryAccessProblem(folder: root, kind: owner?.kind ?? .folder))
                continue
            }
            for container in containers {
                let path = container.url.standardizedFileURL.path
                guard path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") else { continue }
                if !isReadable(container.url) { add(LibraryAccessProblem(folder: container.url, kind: container.kind)) }
            }
        }
        return found
    }
}
