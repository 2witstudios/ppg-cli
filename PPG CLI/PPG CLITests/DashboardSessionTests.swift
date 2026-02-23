import XCTest
@testable import PPG_CLI

@MainActor
final class DashboardSessionTests: XCTestCase {
    private var session: DashboardSession!

    override func setUp() {
        session = DashboardSession()
    }

    func testAddAgentCreatesEntry() {
        let entry = session.addAgent(parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
        XCTAssertTrue(entry.id.hasPrefix("da-"))
        XCTAssertEqual(entry.label, "Claude 1")
        XCTAssertEqual(entry.command, "claude")
        XCTAssertNil(entry.parentWorktreeId)
        XCTAssertEqual(session.entries.count, 1)
    }

    func testAddTerminalCreatesEntry() {
        let entry = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        XCTAssertTrue(entry.id.hasPrefix("dt-"))
        XCTAssertEqual(entry.label, "Terminal 1")
        XCTAssertEqual(entry.command, "/bin/zsh")
        XCTAssertEqual(session.entries.count, 1)
    }

    func testAddMultipleIncrementsLabels() {
        session.addAgent(parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
        session.addAgent(parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
        session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")

        XCTAssertEqual(session.entries[0].label, "Claude 1")
        XCTAssertEqual(session.entries[1].label, "Claude 2")
        XCTAssertEqual(session.entries[2].label, "Terminal 1")
        XCTAssertEqual(session.entries[3].label, "Terminal 2")
    }

    func testRemoveDeletesEntry() {
        let entry = session.addAgent(parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
        session.remove(id: entry.id)
        XCTAssertEqual(session.entries.count, 0)
    }

    func testRemoveNonexistentIdIsNoOp() {
        session.addAgent(parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
        session.remove(id: "nonexistent")
        XCTAssertEqual(session.entries.count, 1)
    }

    func testEntriesForMasterReturnsMasterLevel() {
        session.addAgent(parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
        session.addAgent(parentWorktreeId: "wt-123", command: "claude", workingDir: "/tmp")
        session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")

        let master = session.entriesForMaster()
        XCTAssertEqual(master.count, 2)
        XCTAssertTrue(master.allSatisfy { $0.parentWorktreeId == nil })
    }

    func testEntriesForWorktreeReturnsWorktreeLevel() {
        session.addAgent(parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
        session.addAgent(parentWorktreeId: "wt-123", command: "claude", workingDir: "/tmp")
        session.addTerminal(parentWorktreeId: "wt-123", workingDir: "/tmp")

        let wt = session.entriesForWorktree("wt-123")
        XCTAssertEqual(wt.count, 2)
        XCTAssertTrue(wt.allSatisfy { $0.parentWorktreeId == "wt-123" })
    }

    func testEntryByIdFindsEntry() {
        let entry = session.addAgent(parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
        let found = session.entry(byId: entry.id)
        XCTAssertEqual(found?.id, entry.id)
    }

    func testEntryByIdReturnsNilForMissing() {
        XCTAssertNil(session.entry(byId: "nonexistent"))
    }

    func testRemoveAllClearsEverything() {
        session.addAgent(parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
        session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        session.removeAll()
        XCTAssertEqual(session.entries.count, 0)
    }

    func testAddAgentWithWorktreeId() {
        let entry = session.addAgent(parentWorktreeId: "wt-abc", command: "claude", workingDir: "/tmp/wt")
        XCTAssertEqual(entry.parentWorktreeId, "wt-abc")
        XCTAssertEqual(entry.workingDirectory, "/tmp/wt")
    }

    func testKindIsCorrect() {
        let agent = session.addAgent(parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
        let terminal = session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")

        switch agent.kind {
        case .agent: break // expected
        case .terminal: XCTFail("Expected agent kind")
        }

        switch terminal.kind {
        case .terminal: break // expected
        case .agent: XCTFail("Expected terminal kind")
        }
    }
}
