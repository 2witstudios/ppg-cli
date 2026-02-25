import XCTest
@testable import PPG_CLI

@MainActor
final class DashboardSessionTests: XCTestCase {
    private var session: DashboardSession!

    override func setUp() {
        session = DashboardSession(projectRoot: "/tmp/test-dashboard")
    }

    func testAddAgentCreatesEntry() {
        let entry = session.addAgent(sessionName: "test", parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
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
        session.addAgent(sessionName: "test", parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
        session.addAgent(sessionName: "test", parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
        session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")

        XCTAssertEqual(session.entries[0].label, "Claude 1")
        XCTAssertEqual(session.entries[1].label, "Claude 2")
        XCTAssertEqual(session.entries[2].label, "Terminal 1")
        XCTAssertEqual(session.entries[3].label, "Terminal 2")
    }

    func testRemoveDeletesEntry() {
        let entry = session.addAgent(sessionName: "test", parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
        session.remove(id: entry.id)
        XCTAssertEqual(session.entries.count, 0)
    }

    func testRemoveNonexistentIdIsNoOp() {
        session.addAgent(sessionName: "test", parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
        session.remove(id: "nonexistent")
        XCTAssertEqual(session.entries.count, 1)
    }

    func testEntriesForMasterReturnsMasterLevel() {
        session.addAgent(sessionName: "test", parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
        session.addAgent(sessionName: "test", parentWorktreeId: "wt-123", command: "claude", workingDir: "/tmp")
        session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")

        let master = session.entriesForMaster()
        XCTAssertEqual(master.count, 2)
        XCTAssertTrue(master.allSatisfy { $0.parentWorktreeId == nil })
    }

    func testEntriesForWorktreeReturnsWorktreeLevel() {
        session.addAgent(sessionName: "test", parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
        session.addAgent(sessionName: "test", parentWorktreeId: "wt-123", command: "claude", workingDir: "/tmp")
        session.addTerminal(parentWorktreeId: "wt-123", workingDir: "/tmp")

        let wt = session.entriesForWorktree("wt-123")
        XCTAssertEqual(wt.count, 2)
        XCTAssertTrue(wt.allSatisfy { $0.parentWorktreeId == "wt-123" })
    }

    func testEntryByIdFindsEntry() {
        let entry = session.addAgent(sessionName: "test", parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
        let found = session.entry(byId: entry.id)
        XCTAssertEqual(found?.id, entry.id)
    }

    func testEntryByIdReturnsNilForMissing() {
        XCTAssertNil(session.entry(byId: "nonexistent"))
    }

    func testRemoveAllClearsEverything() {
        session.addAgent(sessionName: "test", parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
        session.addTerminal(parentWorktreeId: nil, workingDir: "/tmp")
        session.removeAll()
        XCTAssertEqual(session.entries.count, 0)
    }

    func testAddAgentWithWorktreeId() {
        let entry = session.addAgent(sessionName: "test", parentWorktreeId: "wt-abc", command: "claude", workingDir: "/tmp/wt")
        XCTAssertEqual(entry.parentWorktreeId, "wt-abc")
        XCTAssertEqual(entry.workingDirectory, "/tmp/wt")
    }

    func testKindIsCorrect() {
        let agent = session.addAgent(sessionName: "test", parentWorktreeId: nil, command: "claude", workingDir: "/tmp")
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

    // MARK: - Persistence: debounce & flush

    func testFlushWritesImmediately() {
        let dir = NSTemporaryDirectory() + "ppg-test-flush-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir + "/.pg", withIntermediateDirectories: true)
        let s = DashboardSession(projectRoot: dir)
        s.addTerminal(parentWorktreeId: nil, workingDir: dir)

        // Debounced write hasn't fired yet — file may not exist
        s.flushToDisk()

        let filePath = dir + "/.pg/dashboard-sessions.json"
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath),
                      "flushToDisk should write the file synchronously")

        let data = FileManager.default.contents(atPath: filePath)!
        let decoded = try! JSONDecoder().decode(SessionDataWrapper.self, from: data)
        XCTAssertEqual(decoded.entries.count, 1)

        try? FileManager.default.removeItem(atPath: dir)
    }

    func testDebouncedWriteCoalesces() {
        let dir = NSTemporaryDirectory() + "ppg-test-debounce-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir + "/.pg", withIntermediateDirectories: true)
        let s = DashboardSession(projectRoot: dir)

        // Rapid mutations — each triggers saveToDisk with 1s debounce
        s.addTerminal(parentWorktreeId: nil, workingDir: dir)
        s.addTerminal(parentWorktreeId: nil, workingDir: dir)
        s.addTerminal(parentWorktreeId: nil, workingDir: dir)

        let filePath = dir + "/.pg/dashboard-sessions.json"

        // Wait for debounce to fire (1s interval + margin)
        let expectation = expectation(description: "Debounced write completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)

        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath),
                      "Debounced write should produce the file after the interval")

        let data = FileManager.default.contents(atPath: filePath)!
        let decoded = try! JSONDecoder().decode(SessionDataWrapper.self, from: data)
        XCTAssertEqual(decoded.entries.count, 3,
                       "All three entries should be present in the coalesced write")

        try? FileManager.default.removeItem(atPath: dir)
    }

    func testFlushCancelsPendingDebouncedWrite() {
        let dir = NSTemporaryDirectory() + "ppg-test-cancel-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir + "/.pg", withIntermediateDirectories: true)
        let s = DashboardSession(projectRoot: dir)

        s.addTerminal(parentWorktreeId: nil, workingDir: dir)
        // Flush immediately — should cancel the pending debounced write
        s.flushToDisk()

        let filePath = dir + "/.pg/dashboard-sessions.json"
        let data = FileManager.default.contents(atPath: filePath)!
        let decoded = try! JSONDecoder().decode(SessionDataWrapper.self, from: data)
        XCTAssertEqual(decoded.entries.count, 1)

        try? FileManager.default.removeItem(atPath: dir)
    }

    func testReloadFromDiskCancelsPendingWrite() {
        let dir = NSTemporaryDirectory() + "ppg-test-reload-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir + "/.pg", withIntermediateDirectories: true)
        let s = DashboardSession(projectRoot: dir)

        s.addTerminal(parentWorktreeId: nil, workingDir: dir)
        // Flush so the file exists with 1 entry
        s.flushToDisk()

        // Add another — triggers debounced write (not yet flushed)
        s.addTerminal(parentWorktreeId: nil, workingDir: dir)
        XCTAssertEqual(s.entries.count, 2)

        // Reload cancels the pending write and restores from disk (1 entry)
        s.reloadFromDisk()
        XCTAssertEqual(s.entries.count, 1,
                       "reloadFromDisk should restore from the flushed file, not the in-memory state")

        try? FileManager.default.removeItem(atPath: dir)
    }
}

/// Minimal Codable wrapper matching DashboardSession.SessionData for test decoding.
private struct SessionDataWrapper: Codable {
    var entries: [DashboardSession.TerminalEntry]
    var gridLayouts: [String: GridLayoutNode]?
}
