import XCTest
@testable import LidAssistant

final class AppConfigTests: XCTestCase {
    func testDefaultConfigurationUsesAutoMode() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        XCTAssertEqual(config.mode, "auto")
        XCTAssertTrue(config.services.contains { $0.id == "deepseek" && $0.enabled })
    }

    func testLegacyManualBlockModeMigratesToManual() throws {
        let json = #"{"mode":"manual-block"}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.mode, "manual")
        XCTAssertTrue(config.manualBlock)
    }

    func testLegacyManualAllowModeMigratesToManual() throws {
        let json = #"{"mode":"manual-allow"}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.mode, "manual")
        XCTAssertFalse(config.manualBlock)
    }
}
