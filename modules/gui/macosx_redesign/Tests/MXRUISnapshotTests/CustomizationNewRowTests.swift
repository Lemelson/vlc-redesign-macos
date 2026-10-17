import Foundation
import MXRCore
import MXRMockBackend
@testable import MXRUI
import XCTest

/// "Move to New Row" fills the Customize band above a one-row control bar (D051, 19m26.3 → 19m27.6),
/// the same place a drop on the band puts a control, instead of appending a row below the transport.
@MainActor
final class CustomizationNewRowTests: XCTestCase {
    func testMoveToNewRowStartsTheRowNearestTheVideo() {
        let app = AppModel.mock(.pausedEpisode)
        app.beginCustomizing()
        XCTAssertEqual(app.playerLayout.bottom.count, 1)
        let transport = app.playerLayout.bottom[0]
        let seek = transport.first { $0.control == .seekBar }!

        XCTAssertTrue(MXRLayoutDragPayload.placed(seek).moveToNewRow(app: app))

        XCTAssertEqual(app.playerLayout.bottom.count, 2)
        XCTAssertEqual(app.playerLayout.bottom[0].map(\.control), [.seekBar],
                       "the new row is the band nearest the video, not a row under the transport")
        XCTAssertEqual(app.playerLayout.bottom[1].map(\.id), transport.filter { $0.id != seek.id }.map(\.id))
    }

    func testMoveToNewRowMatchesADropOnTheBand() {
        let byMenu = AppModel.mock(.pausedEpisode)
        let byDrop = AppModel.mock(.pausedEpisode)
        byMenu.beginCustomizing()
        byDrop.beginCustomizing()
        let menu = byMenu.playerLayout.top.first { $0.control == .menu }!
        XCTAssertTrue(MXRLayoutDragPayload.placed(menu).moveToNewRow(app: byMenu))
        XCTAssertTrue(MXRLayoutDragPayload.placed(menu).place(in: .newFirstRow, at: 0, app: byDrop))
        XCTAssertEqual(byMenu.playerLayout, byDrop.playerLayout)
        XCTAssertEqual(byMenu.playerLayout.bottom.first?.first?.control, .menu)
    }

    /// The tile's context menu and VoiceOver actions run these commands: "Move to New Row" must fill
    /// the band, not append a row under the transport.
    func testTheMenuCommandMoveToNewRowFillsTheBand() throws {
        let app = AppModel.mock(.pausedEpisode)
        app.beginCustomizing()
        let transport = app.playerLayout.bottom[0]
        let seek = try XCTUnwrap(transport.first { $0.control == .seekBar })
        let commands = MXRLayoutEditCommand.all(for: seek, app: app)
        XCTAssertEqual(commands.map(\.menuTitle),
                       ["Move to Top Bar", "Move to Control Bar", "Move to New Row", "Remove from Player"])
        XCTAssertEqual(Set(commands.map(\.accessibilityName)).count, commands.count)

        try XCTUnwrap(commands.first { $0.menuTitle == "Move to New Row" }).perform()

        XCTAssertEqual(app.playerLayout.bottom.map { $0.map(\.control) },
                       [[.seekBar], transport.filter { $0.id != seek.id }.map(\.control)])
    }
}
