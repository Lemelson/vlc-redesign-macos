import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
import MXRUI
import SwiftUI
import XCTest

/// A-08: the resume toast keeps its Figma size (1919:9580) where it fits and, in a narrow video
/// (640 pt window with the compact library), drops the message instead of truncating it.
@MainActor
final class ContinueWatchingToastTests: XCTestCase {
    private func fittingSize(availableWidth: CGFloat) -> CGSize {
        let app = AppModel.mock(.continueWatching)
        XCTAssertNotNil(app.player.restorePrompt, "the scenario must show the resume prompt")
        let host = NSHostingController(rootView: MXRContinueWatchingToast().appModel(app))
        return host.sizeThatFits(in: CGSize(width: availableWidth, height: 200))
    }

    func testWideVideoShowsTheFigmaToast() {
        let box = Theme.Metric.Dialogs.resumeToast
        let size = fittingSize(availableWidth: 1000)
        XCTAssertEqual(size.width, box.width, accuracy: 0.5)
        XCTAssertEqual(size.height, box.height, accuracy: 0.5)
    }

    func testNarrowVideoKeepsOnlyTheActions() {
        let box = Theme.Metric.Dialogs.resumeToast
        let actions = box.padding.leading + Theme.Metric.Dialogs.resumeContinueButton.width
            + Theme.Spacing.gap10 + Theme.Metric.Dialogs.resumeCloseButton.width + box.padding.trailing
        // The compact library leaves about 350 pt of video at 640 pt (S12.Window/continue-narrow).
        let size = fittingSize(availableWidth: 350)
        XCTAssertLessThanOrEqual(size.width, 350, "the toast must fit the video")
        XCTAssertEqual(size.width, actions, accuracy: 2, "a narrow toast hugs its two actions; anything wider is a truncated message")
        XCTAssertEqual(size.height, box.height, accuracy: 0.5)
    }

    func testVideoNarrowerThanTheActionsStillContainsTheToast() {
        // A 480 pt window (the minimum) with the compact library leaves about 224 pt of video area,
        // less than the 230 pt actions-only toast: the Continue button gives up width instead.
        let box = Theme.Metric.Dialogs.resumeToast
        for width: CGFloat in [224, 180, MXRContinueWatchingToast.minimumWidth] {
            let size = fittingSize(availableWidth: width)
            XCTAssertLessThanOrEqual(size.width, width + 0.5, "the toast must not overflow a \(width) pt video")
            XCTAssertEqual(size.height, box.height, accuracy: 0.5)
        }
    }
}
