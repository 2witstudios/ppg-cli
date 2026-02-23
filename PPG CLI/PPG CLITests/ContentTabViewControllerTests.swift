import XCTest
@testable import PPG_CLI

@MainActor
final class ContentTabViewControllerTests: XCTestCase {
    private func makeAgent(id: String = "ag-1") -> AgentModel {
        AgentModel(id: id, name: "claude", agentType: "claude", status: .running, tmuxTarget: "s:1", prompt: "x", startedAt: "t")
    }

    func testPlaceholderVisibleInitially() {
        let vc = ContentTabViewController()
        vc.loadViewIfNeeded()
        XCTAssertFalse(vc.placeholderLabel.isHidden)
        XCTAssertTrue(vc.segmentedControl.isHidden)
    }

    func testShowTabsWithEmptyArrayShowsPlaceholder() {
        let vc = ContentTabViewController()
        vc.loadViewIfNeeded()
        vc.showTabs(for: [])
        XCTAssertFalse(vc.placeholderLabel.isHidden)
        XCTAssertTrue(vc.segmentedControl.isHidden)
        XCTAssertEqual(vc.selectedIndex, -1)
    }

    func testShowTabsWithEntriesHidesPlaceholder() {
        let vc = ContentTabViewController()
        vc.loadViewIfNeeded()
        let session = DashboardSession()
        let entry = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        vc.showTabs(for: [.sessionEntry(entry)])
        XCTAssertTrue(vc.placeholderLabel.isHidden)
        XCTAssertFalse(vc.segmentedControl.isHidden)
        XCTAssertEqual(vc.tabs.count, 1)
        XCTAssertEqual(vc.selectedIndex, 0)
    }

    func testSegmentedControlMatchesTabCount() {
        let vc = ContentTabViewController()
        vc.loadViewIfNeeded()
        let session = DashboardSession()
        let e1 = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        let e2 = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        vc.showTabs(for: [.sessionEntry(e1), .sessionEntry(e2)])
        XCTAssertEqual(vc.segmentedControl.segmentCount, 2)
    }

    func testAddTabAppends() {
        let vc = ContentTabViewController()
        vc.loadViewIfNeeded()
        let session = DashboardSession()
        let e1 = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        vc.showTabs(for: [.sessionEntry(e1)])
        XCTAssertEqual(vc.tabs.count, 1)

        let e2 = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        vc.addTab(.sessionEntry(e2))
        XCTAssertEqual(vc.tabs.count, 2)
        XCTAssertEqual(vc.selectedIndex, 1) // selects the new tab
    }

    func testRemoveTabUpdatesState() {
        let vc = ContentTabViewController()
        vc.loadViewIfNeeded()
        let session = DashboardSession()
        let e1 = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        let e2 = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        vc.showTabs(for: [.sessionEntry(e1), .sessionEntry(e2)])
        XCTAssertEqual(vc.tabs.count, 2)

        vc.removeTab(at: 0)
        XCTAssertEqual(vc.tabs.count, 1)
        XCTAssertEqual(vc.selectedIndex, 0)
    }

    func testRemoveLastTabShowsPlaceholder() {
        let vc = ContentTabViewController()
        vc.loadViewIfNeeded()
        let session = DashboardSession()
        let e1 = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        vc.showTabs(for: [.sessionEntry(e1)])
        vc.removeTab(at: 0)
        XCTAssertEqual(vc.tabs.count, 0)
        XCTAssertFalse(vc.placeholderLabel.isHidden)
        XCTAssertEqual(vc.selectedIndex, -1)
    }

    func testSelectTabMatchingId() {
        let vc = ContentTabViewController()
        vc.loadViewIfNeeded()
        let session = DashboardSession()
        let e1 = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        let e2 = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        vc.showTabs(for: [.sessionEntry(e1), .sessionEntry(e2)])
        vc.selectTab(matchingId: e2.id)
        XCTAssertEqual(vc.selectedIndex, 1)
    }

    func testTabEntryLabels() {
        let agent = makeAgent(id: "ag-test")
        let agentTab = TabEntry.manifestAgent(agent)
        XCTAssertEqual(agentTab.label, "ag-test — claude")
        XCTAssertEqual(agentTab.id, "ag-test")

        let session = DashboardSession()
        let entry = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        let sessionTab = TabEntry.sessionEntry(entry)
        XCTAssertEqual(sessionTab.label, entry.label)
        XCTAssertEqual(sessionTab.id, entry.id)
    }
}
