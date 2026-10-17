import MXRCore
import MXRMockBackend
@testable import MXRUI
import XCTest

@MainActor
final class ProfileDeletionTests: XCTestCase {
    /// Deleting a profile also forgets its player layouts, so a later profile never inherits them.
    func testDeletingAProfileRemovesItsLayouts() {
        let app = AppModel.mock(.pausedEpisode)
        let doomed = app.profiles.create(name: "Temporary")
        let kept = app.profiles.profiles.first { $0.id != doomed.id }!
        for kind in LayoutStore.Kind.allCases {
            app.layouts.beginEditing(profileID: doomed.id, kind: kind)
            app.layouts.updateDraft { $0.remove($0.allItems[0].id) }
            app.layouts.commit()
            XCTAssertNotEqual(app.layouts.layout(profileID: doomed.id, kind: kind), kind == .music ? .music : .video)
        }
        app.layouts.beginEditing(profileID: kept.id, kind: .video)
        app.layouts.updateDraft { $0.remove($0.allItems[0].id) }
        app.layouts.commit()
        let keptLayout = app.layouts.layout(profileID: kept.id, kind: .video)

        XCTAssertTrue(MXRProfileEditing.delete(doomed, in: app))
        XCTAssertFalse(app.profiles.profiles.contains { $0.id == doomed.id })
        XCTAssertEqual(app.layouts.layout(profileID: doomed.id, kind: .video), .video)
        XCTAssertEqual(app.layouts.layout(profileID: doomed.id, kind: .music), .music)
        XCTAssertEqual(app.layouts.layout(profileID: kept.id, kind: .video), keptLayout, "Other profiles keep theirs")
    }
}
