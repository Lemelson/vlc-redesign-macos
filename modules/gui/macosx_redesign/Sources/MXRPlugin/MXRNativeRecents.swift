import AppKit
import MXRCore

/// The system document list follows the same history policy as the app store.
/// Injecting the note boundary lets the focused harness avoid OS persistence.
@MainActor
enum MXRNativeRecents {
    static func record(_ urls: [URL], model: AppModel,
                       note: (URL) -> Void = { NSDocumentController.shared.noteNewRecentDocumentURL($0) }) {
        guard model.savesRecentPlayback else { return }
        urls.filter { $0.isFileURL && !model.excludesFromHistory(MediaItem(url: $0)) }.forEach(note)
    }
}
