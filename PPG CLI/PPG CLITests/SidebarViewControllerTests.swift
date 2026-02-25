import XCTest
@testable import PPG_CLI

@MainActor
final class SidebarViewControllerTests: XCTestCase {
    private func makeAgent(id: String = "ag-1", status: AgentStatus = .running) -> AgentModel {
        AgentModel(id: id, name: "claude", agentType: "claude", status: status, tmuxTarget: "s:1", prompt: "x", startedAt: "t")
    }

    private func makeWorktree(id: String = "wt-1", agents: [AgentModel] = []) -> WorktreeModel {
        WorktreeModel(id: id, name: "feature", path: "/tmp/wt", branch: "ppg/feature", status: "active", tmuxWindow: "s:1", agents: agents)
    }

    // MARK: - Tree Structure

    func testWorktreeNodeIsExpandable() {
        let vc = SidebarViewController()
        vc.loadViewIfNeeded()
        let node = SidebarNode(.worktree(makeWorktree()))
        XCTAssertTrue(vc.outlineView(vc.outlineView, isItemExpandable: node))
    }

    func testAgentNodeIsNotExpandable() {
        let vc = SidebarViewController()
        vc.loadViewIfNeeded()
        let node = SidebarNode(.agent(makeAgent()))
        XCTAssertFalse(vc.outlineView(vc.outlineView, isItemExpandable: node))
    }

    func testTerminalNodeIsNotExpandable() {
        let vc = SidebarViewController()
        vc.loadViewIfNeeded()
        let session = DashboardSession(projectRoot: "/tmp/test")
        let entry = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        let node = SidebarNode(.terminal(entry))
        XCTAssertFalse(vc.outlineView(vc.outlineView, isItemExpandable: node))
    }

    // MARK: - SidebarNode children

    func testProjectNodeChildrenIncludeWorktrees() {
        let ctx = ProjectContext(projectRoot: "/tmp/test-proj")
        let project = SidebarNode(.project(ctx))
        let wt = SidebarNode(.worktree(makeWorktree()))
        project.children = [wt]
        XCTAssertEqual(project.children.count, 1)
    }

    func testWorktreeNodeChildrenIncludeAgents() {
        let agent = makeAgent()
        let wt = SidebarNode(.worktree(makeWorktree(agents: [agent])))
        let agentNode = SidebarNode(.agent(agent))
        wt.children = [agentNode]
        XCTAssertEqual(wt.children.count, 1)
    }

    // MARK: - SidebarItem identity

    func testSidebarItemIds() {
        let wt = SidebarItem.worktree(makeWorktree(id: "wt-abc"))
        XCTAssertEqual(wt.id, "wt-abc")

        let agent = SidebarItem.agent(makeAgent(id: "ag-xyz"))
        XCTAssertEqual(agent.id, "ag-xyz")
    }

    // MARK: - Status color

    func testStatusColorMapping() {
        XCTAssertEqual(Theme.statusColor(for: .running), .systemGreen)
        XCTAssertEqual(Theme.statusColor(for: .completed), .systemBlue)
        XCTAssertEqual(Theme.statusColor(for: .failed), .systemRed)
        XCTAssertEqual(Theme.statusColor(for: .killed), .systemOrange)
        XCTAssertEqual(Theme.statusColor(for: .lost), .systemGray)
        XCTAssertEqual(Theme.statusColor(for: .waiting), .systemGray)
        XCTAssertEqual(Theme.statusColor(for: .spawning), .systemYellow)
    }

    // MARK: - Callbacks

    func testCallbackPropertiesExist() {
        let vc = SidebarViewController()
        vc.loadViewIfNeeded()
        // Verify callback properties are settable
        vc.onItemSelected = { _ in }
        vc.onAddAgent = { _, _ in }
        vc.onAddTerminal = { _, _ in }
        XCTAssertNotNil(vc.onItemSelected)
        XCTAssertNotNil(vc.onAddAgent)
        XCTAssertNotNil(vc.onAddTerminal)
    }

    func testSelectedWorktreeIdReturnsNilWithNoSelection() {
        let vc = SidebarViewController()
        vc.loadViewIfNeeded()
        XCTAssertNil(vc.selectedWorktreeId())
    }
}
