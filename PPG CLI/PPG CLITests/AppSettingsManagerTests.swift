import XCTest
@testable import PPG_CLI

final class AppSettingsManagerTests: XCTestCase {

    // MARK: - Defaults

    func testDefaultRefreshInterval() {
        XCTAssertEqual(AppSettingsManager.defaultRefreshInterval, 2.0)
    }

    func testDefaultShell() {
        XCTAssertEqual(AppSettingsManager.defaultShell, "/bin/zsh")
    }

    func testDefaultHistoryLimit() {
        XCTAssertEqual(AppSettingsManager.defaultHistoryLimit, 50000)
    }

    func testDefaultTerminalFont() {
        XCTAssertEqual(AppSettingsManager.defaultTerminalFont, "Menlo")
    }

    func testDefaultTerminalFontSize() {
        XCTAssertEqual(AppSettingsManager.defaultTerminalFontSize, 13.0)
    }
}
