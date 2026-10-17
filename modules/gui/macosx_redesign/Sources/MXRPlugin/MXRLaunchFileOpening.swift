import Foundation

/// Cocoa repeats command-line file arguments while finishing app launch. VLC
/// already queued them. Suppress only files present in both sources until launch
/// finishes, preserving genuine Finder opens and all later reopen requests.
struct MXRLaunchFileOpening {
    private let startupDuplicates: Set<String>
    private var finishedLaunching = false

    init(arguments: [String], initialQueue: [URL], workingDirectory: URL) {
        let queuedPaths = Set(initialQueue.filter(\.isFileURL).map { $0.standardizedFileURL.path })
        let argumentPaths = Set(arguments.dropFirst().compactMap { argument -> String? in
            if let url = URL(string: argument), url.scheme != nil {
                return url.isFileURL ? url.standardizedFileURL.path : nil
            }
            return URL(fileURLWithPath: argument, relativeTo: workingDirectory).standardizedFileURL.path
        })
        startupDuplicates = queuedPaths.intersection(argumentPaths)
    }

    mutating func applicationDidFinishLaunching() { finishedLaunching = true }

    func urlsToOpen(_ urls: [URL]) -> [URL] {
        guard !finishedLaunching else { return urls }
        return urls.filter { !$0.isFileURL || !startupDuplicates.contains($0.standardizedFileURL.path) }
    }
}
