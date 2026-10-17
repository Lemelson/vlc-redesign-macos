import Foundation
import MXRBridgeAPI
@testable import MXRVLCBackend
import XCTest

final class TypedServiceWireContractTests: XCTestCase {
    func testNamedWireValuesPreserveExistingLibraryQueueOutputContract() {
        XCTAssertEqual(MXRBridgeService.library.rawValue, "library")
        XCTAssertEqual(MXRBridgeService.output.rawValue, "output")
        XCTAssertEqual(MXRBridgeCommand.playNow.rawValue, "playNow")
        XCTAssertEqual(MXRBridgeCommand.setFavorite.rawValue, "setFavorite")
        XCTAssertEqual(MXRBridgeRequest.removeFromPlaylist.rawValue, "removeFromPlaylist")
        XCTAssertEqual(MXRBridgeRequest.start.rawValue, "start")
    }

    func testDynamicSettingsTopicHasAnExplicitFactoryAndRoundTripsItsName() {
        let service = MXRBridgeService.settingOption("macosx-redesign-key-play")
        XCTAssertEqual(service.rawValue, "settings:macosx-redesign-key-play")
        XCTAssertEqual(service.settingOptionName, "macosx-redesign-key-play")
        XCTAssertNil(MXRBridgeService.settings.settingOptionName)
    }
}
