import XCTest
@testable import PPG_CLI

final class AppSettingsManagerTests: XCTestCase {

    // MARK: - Defaults

    func testDefaultAgentCommand() {
        XCTAssertEqual(AppSettingsManager.defaultAgentCommand, "claude --dangerously-skip-permissions")
    }

    func testDefaultRefreshInterval() {
        XCTAssertEqual(AppSettingsManager.defaultRefreshInterval, 2.0)
    }

    func testDefaultAppearance() {
        XCTAssertEqual(AppSettingsManager.defaultAppearance, "dark")
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

// MARK: - Agent command priority logic
// Tests the resolution logic that ProjectContext.agentCommand uses:
//   CLI override > AppSettingsManager > hardcoded default

final class AgentCommandPriorityTests: XCTestCase {

    /// Mirrors the resolution logic in ProjectContext.agentCommand
    private func resolveAgentCommand(cliCommand: String, settingsCommand: String) -> String {
        if !cliCommand.isEmpty { return cliCommand }
        if !settingsCommand.isEmpty { return settingsCommand }
        return AppSettingsManager.defaultAgentCommand
    }

    func testCLIOverrideTakesPriority() {
        let result = resolveAgentCommand(cliCommand: "custom-agent --flag", settingsCommand: "settings-agent")
        XCTAssertEqual(result, "custom-agent --flag",
                       "CLI --agent-command should take priority over settings")
    }

    func testSettingsUsedWhenCLIEmpty() {
        let result = resolveAgentCommand(cliCommand: "", settingsCommand: "settings-agent --custom")
        XCTAssertEqual(result, "settings-agent --custom",
                       "Should use settings command when CLI override is empty")
    }

    func testFallsBackToDefaultWhenBothEmpty() {
        let result = resolveAgentCommand(cliCommand: "", settingsCommand: "")
        XCTAssertEqual(result, AppSettingsManager.defaultAgentCommand,
                       "Should fall back to hardcoded default when both CLI and settings are empty")
    }

    func testCLIOverrideUsedEvenWhenSettingsEmpty() {
        let result = resolveAgentCommand(cliCommand: "my-agent", settingsCommand: "")
        XCTAssertEqual(result, "my-agent")
    }
}
