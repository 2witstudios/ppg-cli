import XCTest
@testable import PPG_CLI

final class PaneSplitNodeTests: XCTestCase {

    // MARK: - Leaf Count

    func testSingleLeafCount() {
        let node = PaneSplitNode.leaf(id: "a", entry: nil)
        XCTAssertEqual(node.leafCount, 1)
    }

    func testSplitLeafCount() {
        let node = PaneSplitNode.split(
            direction: .horizontal,
            first: .leaf(id: "a", entry: nil),
            second: .leaf(id: "b", entry: nil),
            ratio: 0.5
        )
        XCTAssertEqual(node.leafCount, 2)
    }

    func testNestedSplitLeafCount() {
        let node = PaneSplitNode.split(
            direction: .vertical,
            first: .leaf(id: "a", entry: nil),
            second: .split(
                direction: .horizontal,
                first: .leaf(id: "b", entry: nil),
                second: .leaf(id: "c", entry: nil),
                ratio: 0.5
            ),
            ratio: 0.5
        )
        XCTAssertEqual(node.leafCount, 3)
    }

    // MARK: - allLeafIds

    func testAllLeafIds() {
        let node = PaneSplitNode.split(
            direction: .vertical,
            first: .leaf(id: "a", entry: nil),
            second: .split(
                direction: .horizontal,
                first: .leaf(id: "b", entry: nil),
                second: .leaf(id: "c", entry: nil),
                ratio: 0.5
            ),
            ratio: 0.5
        )
        XCTAssertEqual(node.allLeafIds(), ["a", "b", "c"])
    }

    // MARK: - findLeaf

    func testFindLeafExists() {
        let node = PaneSplitNode.leaf(id: "a", entry: nil)
        XCTAssertNotNil(node.findLeaf(id: "a"))
    }

    func testFindLeafNotExists() {
        let node = PaneSplitNode.leaf(id: "a", entry: nil)
        XCTAssertNil(node.findLeaf(id: "b"))
    }

    func testFindLeafInNestedTree() {
        let node = PaneSplitNode.split(
            direction: .vertical,
            first: .leaf(id: "a", entry: nil),
            second: .split(
                direction: .horizontal,
                first: .leaf(id: "b", entry: nil),
                second: .leaf(id: "c", entry: nil),
                ratio: 0.5
            ),
            ratio: 0.5
        )
        XCTAssertNotNil(node.findLeaf(id: "c"))
        XCTAssertNil(node.findLeaf(id: "z"))
    }

    // MARK: - splittingLeaf

    func testSplitLeafCreatesNewNode() {
        let node = PaneSplitNode.leaf(id: "a", entry: nil)
        let result = node.splittingLeaf(id: "a", direction: .horizontal, newLeafId: "b", currentCount: 1)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.leafCount, 2)
        XCTAssertEqual(result?.allLeafIds(), ["a", "b"])
    }

    func testSplitLeafReturnsNilWhenTargetNotFound() {
        let node = PaneSplitNode.leaf(id: "a", entry: nil)
        let result = node.splittingLeaf(id: "z", direction: .horizontal, newLeafId: "b", currentCount: 1)
        XCTAssertNil(result)
    }

    func testSplitLeafReturnsNilAtMaxCapacity() {
        let node = PaneSplitNode.leaf(id: "a", entry: nil)
        let result = node.splittingLeaf(id: "a", direction: .horizontal, newLeafId: "b", currentCount: 6)
        XCTAssertNil(result)
    }

    func testSplitLeafInNestedTree() {
        let node = PaneSplitNode.split(
            direction: .vertical,
            first: .leaf(id: "a", entry: nil),
            second: .leaf(id: "b", entry: nil),
            ratio: 0.5
        )
        let result = node.splittingLeaf(id: "b", direction: .horizontal, newLeafId: "c", currentCount: 2)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.leafCount, 3)
        XCTAssertEqual(result?.allLeafIds(), ["a", "b", "c"])
    }

    func testSplitLeafPreservesDirection() {
        let node = PaneSplitNode.leaf(id: "a", entry: nil)
        let result = node.splittingLeaf(id: "a", direction: .vertical, newLeafId: "b", currentCount: 1)

        if case .split(let dir, _, _, _) = result {
            XCTAssertEqual(dir, .vertical)
        } else {
            XCTFail("Expected split node")
        }
    }

    // MARK: - removingLeaf

    func testRemoveOnlyLeafReturnsNil() {
        let node = PaneSplitNode.leaf(id: "a", entry: nil)
        let result = node.removingLeaf(id: "a")
        XCTAssertNil(result)
    }

    func testRemoveNonexistentLeafReturnsSelf() {
        let node = PaneSplitNode.leaf(id: "a", entry: nil)
        let result = node.removingLeaf(id: "z")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.allLeafIds(), ["a"])
    }

    func testRemoveLeafCollapsesParentSplit() {
        let node = PaneSplitNode.split(
            direction: .horizontal,
            first: .leaf(id: "a", entry: nil),
            second: .leaf(id: "b", entry: nil),
            ratio: 0.5
        )
        let result = node.removingLeaf(id: "a")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.leafCount, 1)
        XCTAssertEqual(result?.allLeafIds(), ["b"])

        // Should collapse to a leaf, not remain a split
        if case .leaf(let id, _) = result {
            XCTAssertEqual(id, "b")
        } else {
            XCTFail("Expected collapse to leaf node")
        }
    }

    func testRemoveLeafFromDeeplyNestedTree() {
        // Structure: split(a, split(b, c))
        let node = PaneSplitNode.split(
            direction: .vertical,
            first: .leaf(id: "a", entry: nil),
            second: .split(
                direction: .horizontal,
                first: .leaf(id: "b", entry: nil),
                second: .leaf(id: "c", entry: nil),
                ratio: 0.5
            ),
            ratio: 0.5
        )

        // Remove "c" → inner split collapses to just "b" → outer split(a, b)
        let result = node.removingLeaf(id: "c")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.leafCount, 2)
        XCTAssertEqual(result?.allLeafIds(), ["a", "b"])
    }

    // MARK: - settingEntry

    func testSetEntryOnLeaf() {
        let entry = TabEntry.sessionEntry(
            DashboardSession.TerminalEntry(
                id: "t1", label: "Terminal 1", kind: .terminal,
                parentWorktreeId: nil, workingDirectory: "/tmp",
                command: "/bin/zsh", tmuxTarget: nil, sessionId: nil
            ),
            sessionName: "test"
        )
        let node = PaneSplitNode.leaf(id: "a", entry: nil)
        let result = node.settingEntry(entry, forLeafId: "a")

        XCTAssertNotNil(result.entry(forLeafId: "a"))
        XCTAssertEqual(result.entry(forLeafId: "a")?.id, "t1")
    }

    func testSetEntryOnWrongLeafIsNoOp() {
        let entry = TabEntry.sessionEntry(
            DashboardSession.TerminalEntry(
                id: "t1", label: "Terminal 1", kind: .terminal,
                parentWorktreeId: nil, workingDirectory: "/tmp",
                command: "/bin/zsh", tmuxTarget: nil, sessionId: nil
            ),
            sessionName: "test"
        )
        let node = PaneSplitNode.leaf(id: "a", entry: nil)
        let result = node.settingEntry(entry, forLeafId: "z")
        XCTAssertNil(result.entry(forLeafId: "a"))
    }

    func testSetEntryInNestedTree() {
        let entry = TabEntry.sessionEntry(
            DashboardSession.TerminalEntry(
                id: "t1", label: "Terminal 1", kind: .terminal,
                parentWorktreeId: nil, workingDirectory: "/tmp",
                command: "/bin/zsh", tmuxTarget: nil, sessionId: nil
            ),
            sessionName: "test"
        )
        let node = PaneSplitNode.split(
            direction: .vertical,
            first: .leaf(id: "a", entry: nil),
            second: .leaf(id: "b", entry: nil),
            ratio: 0.5
        )
        let result = node.settingEntry(entry, forLeafId: "b")

        XCTAssertNil(result.entry(forLeafId: "a"))
        XCTAssertEqual(result.entry(forLeafId: "b")?.id, "t1")
    }

    // MARK: - Max Leaves Enforcement

    func testMaxLeavesEnforcedDuringSplitting() {
        // Build a tree with 6 leaves by successive splits
        var node = PaneSplitNode.leaf(id: "p0", entry: nil)
        for i in 1..<6 {
            let result = node.splittingLeaf(id: "p\(i-1)", direction: .horizontal, newLeafId: "p\(i)", currentCount: node.leafCount)
            XCTAssertNotNil(result, "Split \(i) should succeed")
            node = result!
        }
        XCTAssertEqual(node.leafCount, 6)

        // 7th split should fail
        let overflow = node.splittingLeaf(id: "p5", direction: .horizontal, newLeafId: "p6", currentCount: node.leafCount)
        XCTAssertNil(overflow)
    }
}

// MARK: - SplitDirection Equatable (for test assertions)

extension SplitDirection: Equatable {}
