import XCTest
@testable import PPG_CLI

final class PoguServiceTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        LaunchConfig.shared = LaunchConfig(manifestPath: "", sessionName: "", projectName: "", projectRoot: "")
        super.tearDown()
    }

    private func writeFixture(_ json: String) -> String {
        let poguDir = tempDir.appendingPathComponent(".pogu")
        try? FileManager.default.createDirectory(at: poguDir, withIntermediateDirectories: true)
        let path = poguDir.appendingPathComponent("manifest.json").path
        FileManager.default.createFile(atPath: path, contents: json.data(using: .utf8))
        return path
    }

    private let validJSON = """
    {
      "version": 1, "projectRoot": "/tmp/test", "sessionName": "pogu-test",
      "worktrees": {
        "wt-abc123": {
          "id": "wt-abc123", "name": "feature-x", "path": "/tmp/test/.worktrees/wt-abc123",
          "branch": "pogu/feature-x", "baseBranch": "main", "status": "active",
          "tmuxWindow": "pogu-test:1",
          "agents": {
            "ag-def456": {
              "id": "ag-def456", "name": "claude", "agentType": "claude",
              "status": "running", "tmuxTarget": "pogu-test:1",
              "prompt": "Do something", "resultFile": "/tmp/test/.pogu/results/ag-def456.md",
              "startedAt": "2026-02-23T12:00:00Z"
            }
          },
          "createdAt": "2026-02-23T12:00:00Z"
        }
      },
      "createdAt": "2026-02-23T10:00:00Z", "updatedAt": "2026-02-23T12:00:00Z"
    }
    """

    func testReadManifestWithValidJSON() {
        let path = writeFixture(validJSON)
        LaunchConfig.shared = LaunchConfig(manifestPath: path, sessionName: "pogu-test", projectName: "test", projectRoot: "")
        let manifest = PoguService.shared.readManifest()
        XCTAssertNotNil(manifest)
        XCTAssertEqual(manifest?.version, 1)
        XCTAssertEqual(manifest?.worktrees.count, 1)
    }

    func testReadManifestReturnsNilForNonexistentPath() {
        LaunchConfig.shared = LaunchConfig(manifestPath: "/nonexistent/path.json", sessionName: "", projectName: "", projectRoot: "")
        XCTAssertNil(PoguService.shared.readManifest())
    }

    func testReadManifestReturnsNilForMalformedJSON() {
        let path = writeFixture("{ not valid json }")
        LaunchConfig.shared = LaunchConfig(manifestPath: path, sessionName: "", projectName: "", projectRoot: "")
        XCTAssertNil(PoguService.shared.readManifest())
    }

    func testRefreshStatusReturnsSortedWorktrees() {
        let json = """
        {
          "version": 1, "projectRoot": "/tmp", "sessionName": "s",
          "worktrees": {
            "wt-2": {
              "id": "wt-2", "name": "second", "path": "/p2", "branch": "b2", "baseBranch": "main",
              "status": "active", "tmuxWindow": "s:2", "agents": {},
              "createdAt": "2026-02-23T14:00:00Z"
            },
            "wt-1": {
              "id": "wt-1", "name": "first", "path": "/p1", "branch": "b1", "baseBranch": "main",
              "status": "active", "tmuxWindow": "s:1", "agents": {},
              "createdAt": "2026-02-23T12:00:00Z"
            }
          },
          "createdAt": "t", "updatedAt": "t"
        }
        """
        let path = writeFixture(json)
        LaunchConfig.shared = LaunchConfig(manifestPath: path, sessionName: "s", projectName: "test", projectRoot: "")
        let worktrees = PoguService.shared.refreshStatus()
        XCTAssertEqual(worktrees.count, 2)
        XCTAssertEqual(worktrees[0].name, "first")
        XCTAssertEqual(worktrees[1].name, "second")
    }

    func testRefreshStatusReturnsSortedAgents() {
        let json = """
        {
          "version": 1, "projectRoot": "/tmp", "sessionName": "s",
          "worktrees": {
            "wt-1": {
              "id": "wt-1", "name": "w", "path": "/p", "branch": "b", "baseBranch": "main",
              "status": "active", "tmuxWindow": "s:1",
              "agents": {
                "ag-b": {
                  "id": "ag-b", "name": "b", "agentType": "claude", "status": "running",
                  "tmuxTarget": "s:1.1", "prompt": "x", "resultFile": "/r",
                  "startedAt": "2026-02-23T14:00:00Z"
                },
                "ag-a": {
                  "id": "ag-a", "name": "a", "agentType": "claude", "status": "completed",
                  "tmuxTarget": "s:1.0", "prompt": "y", "resultFile": "/r",
                  "startedAt": "2026-02-23T12:00:00Z"
                }
              },
              "createdAt": "t"
            }
          },
          "createdAt": "t", "updatedAt": "t"
        }
        """
        let path = writeFixture(json)
        LaunchConfig.shared = LaunchConfig(manifestPath: path, sessionName: "s", projectName: "test", projectRoot: "")
        let worktrees = PoguService.shared.refreshStatus()
        XCTAssertEqual(worktrees[0].agents.count, 2)
        XCTAssertEqual(worktrees[0].agents[0].id, "ag-a")
        XCTAssertEqual(worktrees[0].agents[1].id, "ag-b")
    }

    func testRefreshStatusReturnsEmptyWhenMissing() {
        LaunchConfig.shared = LaunchConfig(manifestPath: "/nonexistent", sessionName: "", projectName: "", projectRoot: "")
        XCTAssertEqual(PoguService.shared.refreshStatus().count, 0)
    }
}
