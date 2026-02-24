import XCTest
@testable import PPG_CLI

@MainActor
final class TerminalPaneTests: XCTestCase {
    private func makeAgent() -> AgentModel {
        AgentModel(id: "ag-test", name: "claude", agentType: "claude", status: .running, tmuxTarget: "s:1", prompt: "x", startedAt: "t")
    }

    func testHasTwoSubviews() {
        let pane = TerminalPane(agent: makeAgent(), sessionName: "test")
        XCTAssertEqual(pane.subviews.count, 2)
    }

    func testLabelContainsAgentIdAndStatus() {
        let pane = TerminalPane(agent: makeAgent(), sessionName: "test")
        XCTAssertTrue(pane.label.stringValue.contains("ag-test"))
        XCTAssertTrue(pane.label.stringValue.contains("running"))
    }

    func testLabelFontIsMonospaced() {
        let pane = TerminalPane(agent: makeAgent(), sessionName: "test")
        let descriptor = pane.label.font!.fontDescriptor
        XCTAssertTrue(descriptor.symbolicTraits.contains(.monoSpace))
    }

    func testConstraintsAreActive() {
        let pane = TerminalPane(agent: makeAgent(), sessionName: "test")
        XCTAssertGreaterThan(pane.constraints.count, 0)
    }

    func testTerminateDoesNotCrashWithoutProcess() {
        let pane = TerminalPane(agent: makeAgent(), sessionName: "test")
        pane.terminate()
    }

    func testMouseReportingDisabledForTextSelection() {
        let pane = TerminalPane(agent: makeAgent(), sessionName: "test")
        XCTAssertFalse(pane.terminalView.allowMouseReporting)
    }
}
