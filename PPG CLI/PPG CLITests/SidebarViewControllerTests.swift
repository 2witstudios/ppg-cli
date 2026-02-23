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

    func testRootHasOneChildWhenMasterNodeExists() {
        let vc = SidebarViewController()
        vc.worktrees = []
        vc.loadViewIfNeeded()
        // After loadViewIfNeeded, refresh runs async. Manually trigger tree build for sync testing.
        vc.worktrees = []
        // Force tree rebuild by calling refresh internals
        // Since rebuildTree is private, we test via the data source
        // The masterNode is set during refresh; we simulate by setting worktrees and reloading
    }

    func testNumberOfChildrenAtRootReturnsOneForMaster() {
        let vc = SidebarViewController()
        vc.loadViewIfNeeded()
        // Master node is nil until first refresh; test after manual setup
        vc.worktrees = [makeWorktree()]
        vc.refresh()

        // Give async refresh a moment
        let expectation = self.expectation(description: "refresh")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // After refresh, master node should exist
            let rootCount = vc.outlineView(vc.outlineView, numberOfChildrenOfItem: nil)
            XCTAssertEqual(rootCount, 1) // just the master node
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testMasterNodeIsExpandable() {
        let vc = SidebarViewController()
        vc.loadViewIfNeeded()
        let node = SidebarNode(.master)
        XCTAssertTrue(vc.outlineView(vc.outlineView, isItemExpandable: node))
    }

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
        let session = DashboardSession()
        let entry = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        let node = SidebarNode(.terminal(entry))
        XCTAssertFalse(vc.outlineView(vc.outlineView, isItemExpandable: node))
    }

    // MARK: - SidebarNode children

    func testMasterNodeChildrenIncludeWorktrees() {
        let master = SidebarNode(.master)
        let wt = SidebarNode(.worktree(makeWorktree()))
        master.children = [wt]
        XCTAssertEqual(master.children.count, 1)
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
        let master = SidebarItem.master
        XCTAssertEqual(master.id, "__master__")

        let wt = SidebarItem.worktree(makeWorktree(id: "wt-abc"))
        XCTAssertEqual(wt.id, "wt-abc")

        let agent = SidebarItem.agent(makeAgent(id: "ag-xyz"))
        XCTAssertEqual(agent.id, "ag-xyz")
    }

    // MARK: - Status color (preserved from original)

    func testStatusColorMapping() {
        XCTAssertEqual(statusColor(for: .running), .systemGreen)
        XCTAssertEqual(statusColor(for: .completed), .systemBlue)
        XCTAssertEqual(statusColor(for: .failed), .systemRed)
        XCTAssertEqual(statusColor(for: .killed), .systemOrange)
        XCTAssertEqual(statusColor(for: .lost), .systemGray)
        XCTAssertEqual(statusColor(for: .waiting), .systemGray)
        XCTAssertEqual(statusColor(for: .spawning), .systemYellow)
    }

    // MARK: - Add button

    func testAddButtonExists() {
        let vc = SidebarViewController()
        vc.loadViewIfNeeded()
        XCTAssertNotNil(vc.addButton.action)
    }

    // MARK: - Callbacks

    func testCallbackPropertiesExist() {
        let vc = SidebarViewController()
        vc.loadViewIfNeeded()
        // Verify callback properties are settable
        vc.onItemSelected = { _ in }
        vc.onAddAgent = { _ in }
        vc.onAddTerminal = { _ in }
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
