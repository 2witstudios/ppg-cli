import XCTest
@testable import PPG_CLI

@MainActor
final class DashboardSplitViewControllerTests: XCTestCase {
    func testHasTwoSplitViewItems() {
        let vc = DashboardSplitViewController()
        vc.loadViewIfNeeded()
        XCTAssertEqual(vc.splitViewItems.count, 2)
    }

    func testLeftItemIsSidebar() {
        let vc = DashboardSplitViewController()
        vc.loadViewIfNeeded()
        XCTAssertTrue(vc.splitViewItems[0].viewController is SidebarViewController)
    }

    func testRightItemIsContentVC() {
        let vc = DashboardSplitViewController()
        vc.loadViewIfNeeded()
        XCTAssertTrue(vc.splitViewItems[1].viewController is ContentViewController)
    }

    func testSidebarMinimumThickness() {
        let vc = DashboardSplitViewController()
        vc.loadViewIfNeeded()
        XCTAssertEqual(vc.splitViewItems[0].minimumThickness, 200)
    }

    func testSidebarMaximumThickness() {
        let vc = DashboardSplitViewController()
        vc.loadViewIfNeeded()
        XCTAssertEqual(vc.splitViewItems[0].maximumThickness, 300)
    }

    func testSidebarCallbacksAreWired() {
        let vc = DashboardSplitViewController()
        vc.loadViewIfNeeded()
        XCTAssertNotNil(vc.sidebar.onItemSelected)
        XCTAssertNotNil(vc.sidebar.onAddAgent)
        XCTAssertNotNil(vc.sidebar.onAddTerminal)
    }
}
