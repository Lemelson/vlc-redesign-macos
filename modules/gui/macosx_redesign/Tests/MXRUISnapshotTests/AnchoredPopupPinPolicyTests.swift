import AppKit
import MXRCore
@testable import MXRDesign
import MXRMockBackend
@testable import MXRUI
import XCTest

/// D023: a popup dropped from a bar keeps that bar shown, and only that bar. Driven through a real
/// popup session (``MXRPopupAnchor``/``MXRPopupCenter``), not a hand-set flag.
@MainActor
final class AnchoredPopupPinPolicyTests: XCTestCase {
    private func playingApp() -> AppModel {
        let app = MockBackend(scenario: .playingEpisode).makeAppModel(clockTicks: false)
        app.player.play()
        app.interface.library = .hidden
        app.interface.rightPanel = nil
        return app
    }

    private func inputs(_ app: AppModel) -> PlayerChromeReveal.Inputs {
        var inputs = PlayerChromeReveal.Inputs(app: app)
        // Only the popup varies here; the other pins are covered by their own tests.
        inputs.playing = true
        inputs.customizing = false
        inputs.libraryShown = false
        inputs.sheetShown = false
        inputs.appMenuOpen = false
        inputs.panelOpen = false
        return inputs
    }

    /// Opens a real anchored popup from a view in a window, as `.mxrPopupMenu` does.
    private func present(owner: MXRPopupOwner?, pointer: Bool = false) -> (MXRPopupAnchor, NSWindow) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSView(frame: CGRect(x: 100, y: 20, width: 40, height: 40))
        window.contentView?.addSubview(view)
        let anchor = MXRPopupAnchor()
        anchor.view = view
        let environment = MXRPopupEnvironment(colorScheme: .dark, accent: .orange, themeMode: .dark, backdropEnabled: false)
        anchor.present(.menu({ [MXRMenuItem("1×") {}] }), placement: .above(.center),
                       at: pointer ? CGPoint(x: 120, y: 40) : nil, style: .textMenu, width: nil, surface: true,
                       environment: environment, owner: owner, onDismiss: {})
        return (anchor, window)
    }

    func testControlBarPopupPinsOnlyTheControlBarUntilDismissed() {
        let app = playingApp()
        XCTAssertFalse(inputs(app).pins(.top))
        XCTAssertFalse(inputs(app).pins(.control))

        let (anchor, window) = present(owner: .playerControlBar)
        XCTAssertEqual(MXRPopupCenter.shared.anchoredOwner, .playerControlBar)
        XCTAssertTrue(inputs(app).pins(.control), "The speed/zoom/overflow menu keeps its bar reachable")
        XCTAssertFalse(inputs(app).pins(.top), "It does not also hold the top bar")

        anchor.dismiss(animated: false)
        XCTAssertNil(MXRPopupCenter.shared.anchoredOwner)
        XCTAssertFalse(inputs(app).pins(.control), "Dismissing the popup releases its pin")
        window.close()
    }

    func testTopBarPopupPinsOnlyTheTopBar() {
        let app = playingApp()
        let (anchor, window) = present(owner: .playerTopBar)
        XCTAssertTrue(inputs(app).pins(.top))
        XCTAssertFalse(inputs(app).pins(.control))
        anchor.dismiss(animated: false)
        XCTAssertFalse(inputs(app).pins(.top))
        window.close()
    }

    /// Dropdowns in panels and context menus at the pointer belong to no bar.
    func testUnownedAndPointerPopupsPinNoBar() {
        let app = playingApp()
        var (anchor, window) = present(owner: nil)
        XCTAssertTrue(MXRPopupCenter.shared.isPresentingAnchored)
        XCTAssertFalse(inputs(app).pins(.top))
        XCTAssertFalse(inputs(app).pins(.control))
        anchor.dismiss(animated: false)
        window.close()

        (anchor, window) = present(owner: .playerControlBar, pointer: true)
        XCTAssertTrue(MXRPopupCenter.shared.isPresenting)
        XCTAssertNil(MXRPopupCenter.shared.anchoredOwner, "A context menu at the pointer is not anchored to a bar")
        XCTAssertFalse(inputs(app).pins(.control))
        anchor.dismiss(animated: false)
        window.close()
    }
}
