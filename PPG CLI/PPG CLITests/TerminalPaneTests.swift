import XCTest
@testable import PPG_CLI

@MainActor
final class TerminalPaneTests: XCTestCase {
    private func makeAgent() -> AgentModel {
        AgentModel(id: "ag-test", name: "claude", agentType: "claude", status: .running, tmuxTarget: "s:1", prompt: "x", startedAt: "t")
    }

    func testNoSubviewsBeforeWindowAttachment() {
        let pane = TerminalPane(agent: makeAgent(), sessionName: "test")
        // Terminal view is lazy — nothing added until viewDidMoveToWindow
        XCTAssertEqual(pane.subviews.count, 0)
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

    func testNoConstraintsBeforeWindowAttachment() {
        let pane = TerminalPane(agent: makeAgent(), sessionName: "test")
        // Terminal view is lazy — no constraints until viewDidMoveToWindow
        XCTAssertTrue(pane.constraints.isEmpty)
    }

    func testTerminateDoesNotCrashWithoutProcess() {
        let pane = TerminalPane(agent: makeAgent(), sessionName: "test")
        pane.terminate()
    }

    func testTerminalViewNilBeforeWindowAttachment() {
        let pane = TerminalPane(agent: makeAgent(), sessionName: "test")
        // No terminal view exists before window attachment.
        // The mouse reporting guarantee is enforced by ScrollableTerminalView.init
        // which sets allowMouseReporting = false.
        XCTAssertNil(pane.terminalView)
    }
}
