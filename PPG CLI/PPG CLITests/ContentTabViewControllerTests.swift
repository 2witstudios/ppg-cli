import XCTest
@testable import PPG_CLI

@MainActor
final class ContentViewControllerTests: XCTestCase {
    private func makeAgent(id: String = "ag-1") -> AgentModel {
        AgentModel(id: id, name: "claude", agentType: "claude", status: .running, tmuxTarget: "s:1", prompt: "x", startedAt: "t")
    }

    func testPlaceholderVisibleInitially() {
        let vc = ContentViewController()
        vc.loadViewIfNeeded()
        XCTAssertFalse(vc.placeholderLabel.isHidden)
        XCTAssertNil(vc.currentEntry)
    }

    func testShowEntryNilShowsPlaceholder() {
        let vc = ContentViewController()
        vc.loadViewIfNeeded()
        vc.showEntry(nil)
        XCTAssertFalse(vc.placeholderLabel.isHidden)
        XCTAssertNil(vc.currentEntry)
    }

    func testShowEntryHidesPlaceholder() {
        let vc = ContentViewController()
        vc.loadViewIfNeeded()
        let session = DashboardSession(projectRoot: "/tmp/test")
        let entry = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        vc.showEntry(.sessionEntry(entry, sessionName: "test"))
        XCTAssertTrue(vc.placeholderLabel.isHidden)
        XCTAssertNotNil(vc.currentEntry)
        XCTAssertEqual(vc.currentEntryId, entry.id)
    }

    func testShowSameEntryIsNoOp() {
        let vc = ContentViewController()
        vc.loadViewIfNeeded()
        let session = DashboardSession(projectRoot: "/tmp/test")
        let entry = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        vc.showEntry(.sessionEntry(entry, sessionName: "test"))
        let firstEntryId = vc.currentEntryId
        // Show same entry again — should be a no-op
        vc.showEntry(.sessionEntry(entry, sessionName: "test"))
        XCTAssertEqual(vc.currentEntryId, firstEntryId)
    }

    func testRemoveEntryShowsPlaceholder() {
        let vc = ContentViewController()
        vc.loadViewIfNeeded()
        let session = DashboardSession(projectRoot: "/tmp/test")
        let entry = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        vc.showEntry(.sessionEntry(entry, sessionName: "test"))
        XCTAssertTrue(vc.placeholderLabel.isHidden)

        vc.removeEntry(byId: entry.id)
        XCTAssertFalse(vc.placeholderLabel.isHidden)
        XCTAssertNil(vc.currentEntry)
    }

    func testRemoveNonCurrentEntryKeepsCurrent() {
        let vc = ContentViewController()
        vc.loadViewIfNeeded()
        let session = DashboardSession(projectRoot: "/tmp/test")
        let e1 = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        let e2 = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        vc.showEntry(.sessionEntry(e1, sessionName: "test"))
        // Show e1, then cache e2 by showing it, then go back to e1
        vc.showEntry(.sessionEntry(e2, sessionName: "test"))
        // Force a different entry to be current
        // Actually, just remove e1 (which is not current since e2 is shown)
        vc.removeEntry(byId: e1.id)
        // e2 should still be current
        XCTAssertEqual(vc.currentEntryId, e2.id)
        XCTAssertTrue(vc.placeholderLabel.isHidden)
    }

    func testTabEntryLabels() {
        let agent = makeAgent(id: "ag-test")
        let agentTab = TabEntry.manifestAgent(agent, sessionName: "s")
        XCTAssertEqual(agentTab.label, "claude")
        XCTAssertEqual(agentTab.id, "ag-test")

        let session = DashboardSession(projectRoot: "/tmp/test")
        let entry = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        let sessionTab = TabEntry.sessionEntry(entry, sessionName: "s")
        XCTAssertEqual(sessionTab.label, entry.label)
        XCTAssertEqual(sessionTab.id, entry.id)
    }

    func testClearStaleViews() {
        let vc = ContentViewController()
        vc.loadViewIfNeeded()
        let session = DashboardSession(projectRoot: "/tmp/test")
        let e1 = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        vc.showEntry(.sessionEntry(e1, sessionName: "test"))

        // Clear with empty valid set — should remove cached view
        vc.clearStaleViews(validIds: [])
        XCTAssertNil(vc.currentEntry)
    }
}
