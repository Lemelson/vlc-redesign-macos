import XCTest
@testable import MXRCore
import MXRMockBackend
@MainActor
final class ModalIsolationTests: XCTestCase {
    func testFullLibraryClearsPopup() {
        let app = MockBackend(scenario: .idle).makeAppModel(clockTicks: false)
        app.interface.toggleQueuePanel(); app.interface.showFullLibrary()
        XCTAssertNil(app.interface.rightPanel); XCTAssertFalse(app.interface.hasTransientPopup)
        XCTAssertFalse(app.interface.dismissTransientPopup()); XCTAssertFalse(app.canPerform(.toggleQueue))
        app.perform(.toggleQueue); XCTAssertNil(app.interface.rightPanel)
    }
    func testModalProtectsDraftAndReturnsToSettings() {
        let app = MockBackend(scenario: .idle).makeAppModel(clockTicks: false)
        app.interface.present(.keyboardShortcuts)
        for command in [AppCommand.openNetworkStream, .openFiles, .playPause, .about, .settings] {
            XCTAssertFalse(app.canPerform(command)); app.perform(command)
            XCTAssertEqual(app.interface.sheet, .keyboardShortcuts); XCTAssertNil(app.interface.fileRequest)
        }
        app.interface.present(.openNetworkStream); XCTAssertEqual(app.interface.sheet, .keyboardShortcuts)
        let media = MediaItem(url: URL(fileURLWithPath: "/tmp/modal-draft.mp4"))
        app.presentOutput(media: media, mode: .convert)
        app.presentNewPlaylist(media: [media])
        app.presentAddSubtitles(media: [media])
        XCTAssertNil(app.interface.pendingOutputSource)
        XCTAssertTrue(app.interface.pendingPlaylistMedia.isEmpty)
        XCTAssertTrue(app.interface.subtitleTargetMedia.isEmpty)
        app.interface.dismissSheet(); app.interface.present(.settings(categoryID: "controls"))
        app.interface.present(.keyboardShortcuts); XCTAssertEqual(app.interface.sheet, .keyboardShortcuts)
        app.interface.dismissSheet(); XCTAssertEqual(app.interface.sheet, .settings(categoryID: "controls"))
        app.interface.dismissSheet(); XCTAssertNil(app.interface.sheet)
        XCTAssertTrue(app.canPerform(.quit))
    }
    /// D026/D040: a dialog blocks the window and menu bar, not the media keys, Control Center or
    /// the status item. Their transport never touches a draft.
    func testSystemTransportWorksBehindDialogButUIDoesNot() {
        let app = MockBackend(scenario: .playingMovie).makeAppModel(clockTicks: false)
        app.interface.present(.openNetworkStream)
        XCTAssertFalse(app.canPerform(.playPause))
        XCTAssertTrue(app.canPerform(.playPause, from: .system))
        let wasPlaying = app.player.isPlaying
        app.perform(.playPause)
        XCTAssertEqual(app.player.isPlaying, wasPlaying, "UI Space behind a dialog must not toggle playback")
        app.perform(.playPause, from: .system)
        XCTAssertNotEqual(app.player.isPlaying, wasPlaying, "the Play/Pause media key works behind a dialog")
        XCTAssertTrue(app.canPerform(.toggleMute, from: .system))
        for command in [AppCommand.openFiles, .openNetworkStream, .settings, .about, .toggleFullscreen, .toggleQueue] {
            XCTAssertFalse(app.canPerform(command, from: .system), command.rawValue)
            app.perform(command, from: .system)
            XCTAssertEqual(app.interface.sheet, .openNetworkStream, command.rawValue)
            XCTAssertNil(app.interface.fileRequest, command.rawValue)
        }
    }
    /// With nothing to play, the Play key would open the library behind the dialog: refused.
    func testSystemPlayWithEmptyQueueIsRefusedBehindDialog() {
        let app = MockBackend(scenario: .idle).makeAppModel(clockTicks: false)
        app.interface.present(.about)
        XCTAssertFalse(app.canPerform(.playPause, from: .system))
        let library = app.interface.library
        app.perform(.playPause, from: .system)
        XCTAssertEqual(app.interface.library, library)
    }
    func testHiddenUIHidesPersistentInformationWithoutClearingPreference() {
        let interface = InterfaceModel()
        interface.showMetadata = true
        XCTAssertTrue(interface.showsPlayerInformation)
        interface.toggleUIHidden()
        XCTAssertFalse(interface.showsPlayerInformation)
        XCTAssertTrue(interface.showMetadata)
        interface.toggleUIHidden()
        XCTAssertTrue(interface.showsPlayerInformation)
        interface.showFullLibrary()
        XCTAssertFalse(interface.showsPlayerInformation)
    }
    func testModalMenuPolicy() {
        for key in ["Command+c", "Command+v", "Command+x", "Command+a", "Command+z", "Command+Shift+z", "Command+q", "Command+w"] {
            XCTAssertTrue(MenuKeyEquivalentPolicy.allows(KeyBinding(vlcString: key)!, isRecording: false, hasModal: true, isEditing: true), key)
        }
        for key in ["Command+n", "Command+o", "Command+f", "Command+Shift+s", "Command+,", "Space"] {
            XCTAssertFalse(MenuKeyEquivalentPolicy.allows(KeyBinding(vlcString: key)!, isRecording: false, hasModal: true, isEditing: true), key)
        }
    }
}
