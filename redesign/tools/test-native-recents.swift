// First build MXRCore and MXRMockBackend with SwiftPM, then from the repo root:
// native_recents_build=/path/to/swiftpm/arm64-apple-macosx/debug
// swiftc -parse-as-library -swift-version 6 -I "$native_recents_build/Modules" \
//   modules/gui/macosx_redesign/Sources/MXRPlugin/MXRNativeRecents.swift \
//   redesign/tools/test-native-recents.swift "$native_recents_build"/MXRCore.build/*.o \
//   "$native_recents_build"/MXRMockBackend.build/*.o -o /private/tmp/mxr-native-recents-test
// /private/tmp/mxr-native-recents-test
// This harness never writes macOS recent documents: its system boundary is injected.
import AppKit
import MXRCore
import MXRMockBackend

@main
struct NativeRecentsTests {
    @MainActor
    static func main() {
        let mock = MockBackend(scenario: .idle)
        let model = AppModel(backends: mock.backends, persistence: .inMemory, clockTicks: false)
        let ordinary = URL(fileURLWithPath: "/tmp/Example.mp4")
        let excluded = URL(string: "file:///tmp/My%20Secr%C3%A9t.mp4")!
        let excludedFolder = URL(fileURLWithPath: "/tmp/PRIVATE", isDirectory: true)
        let allowedFolder = URL(fileURLWithPath: "/tmp/Movies", isDirectory: true)
        let namedParent = URL(fileURLWithPath: "/tmp/private/Public.mp4")
        let remote = URL(string: "https://example.com/Example.mp4")!
        var recorded: [URL] = []

        mock.settings.setValue(.bool(false), for: "save-recentplay", apply: .nextMedia)
        MXRNativeRecents.record([ordinary, allowedFolder], model: model) { recorded.append($0) }
        precondition(recorded.isEmpty, "Disabled history cannot write files or folders to macOS recents")

        mock.settings.setValue(.bool(true), for: "save-recentplay", apply: .nextMedia)
        mock.settings.setValue(.string(" secret , PRIVATE, ,"), for: "macosx-redesign-history-exclude", apply: .nextMedia)
        MXRNativeRecents.record([ordinary, excluded, remote, excludedFolder, allowedFolder, namedParent],
                               model: model) { recorded.append($0) }
        precondition(recorded == [ordinary, allowedFolder, namedParent],
                     "Native recents follow the app's decoded filename policy and preserve eligible selection order")

        mock.settings.setValue(.string("example"), for: "macosx-redesign-history-exclude", apply: .nextMedia)
        MXRNativeRecents.record([ordinary], model: model) { recorded.append($0) }
        precondition(recorded.count == 3, "Live exclusion edits affect subsequent native opens")

        mock.player.load(MediaItem(url: namedParent))
        precondition(!model.recents.entries.isEmpty)
        var systemClearCount = 0
        model.recents.onCleared = {
            precondition(model.recents.entries.isEmpty, "The app's clear completes before notifying the system")
            systemClearCount += 1
        }
        // Native Clear Menu takes this direct route; Settings uses the AppModel
        // action handler wired to its real SettingsModel instead.
        model.recents.clear()
        precondition(model.recents.entries.isEmpty && systemClearCount == 1)
        mock.player.load(MediaItem(url: allowedFolder))
        precondition(!model.recents.entries.isEmpty)
        let clearHistory = model.settings.catalog.allRows.first { $0.action == "clear-history" }!
        model.settings.perform(clearHistory)
        precondition(model.recents.entries.isEmpty && systemClearCount == 2)
        model.recents.onCleared = nil
        model.recents.clear()
        precondition(systemClearCount == 2, "Native teardown disconnects the system boundary")
        print("PASS: native recent-document privacy, live exclusions, and shared Clear History/Clear Menu")
    }
}
