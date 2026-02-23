import XCTest
@testable import PPG_CLI

final class ManifestModelTests: XCTestCase {
    let fixtureJSON = """
    {
      "version": 1,
      "projectRoot": "/tmp/test",
      "sessionName": "ppg-test",
      "worktrees": {
        "wt-abc123": {
          "id": "wt-abc123", "name": "feature-x", "path": "/tmp/test/.worktrees/wt-abc123",
          "branch": "ppg/feature-x", "baseBranch": "main", "status": "active",
          "tmuxWindow": "ppg-test:1",
          "agents": {
            "ag-def456": {
              "id": "ag-def456", "name": "claude", "agentType": "claude",
              "status": "running", "tmuxTarget": "ppg-test:1",
              "prompt": "Do something", "resultFile": "/tmp/test/.pg/results/ag-def456.md",
              "startedAt": "2026-02-23T12:00:00Z"
            }
          },
          "createdAt": "2026-02-23T12:00:00Z"
        }
      },
      "createdAt": "2026-02-23T10:00:00Z",
      "updatedAt": "2026-02-23T12:00:00Z"
    }
    """.data(using: .utf8)!

    func testDecodesFromJSONFixture() throws {
        let manifest = try JSONDecoder().decode(ManifestModel.self, from: fixtureJSON)
        XCTAssertEqual(manifest.version, 1)
        XCTAssertEqual(manifest.worktrees.count, 1)
        let wt = try XCTUnwrap(manifest.worktrees["wt-abc123"])
        XCTAssertEqual(wt.name, "feature-x")
        XCTAssertEqual(wt.branch, "ppg/feature-x")
        let agent = try XCTUnwrap(wt.agents["ag-def456"])
        XCTAssertEqual(agent.id, "ag-def456")
        XCTAssertEqual(agent.status, "running")
        XCTAssertEqual(agent.prompt, "Do something")
    }

    func testHandlesMissingOptionals() throws {
        let json = """
        {
          "version": 1, "projectRoot": "/tmp", "sessionName": "s",
          "worktrees": {
            "wt-1": {
              "id": "wt-1", "name": "a", "path": "/p", "branch": "b", "baseBranch": "main",
              "status": "active", "tmuxWindow": "s:1",
              "agents": {
                "ag-1": {
                  "id": "ag-1", "name": "c", "agentType": "claude", "status": "running",
                  "tmuxTarget": "s:1", "prompt": "x", "resultFile": "/r", "startedAt": "t"
                }
              },
              "createdAt": "t"
            }
          },
          "createdAt": "t", "updatedAt": "t"
        }
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(ManifestModel.self, from: json)
        let wt = try XCTUnwrap(manifest.worktrees["wt-1"])
        XCTAssertNil(wt.mergedAt)
        let agent = try XCTUnwrap(wt.agents["ag-1"])
        XCTAssertNil(agent.completedAt)
        XCTAssertNil(agent.exitCode)
        XCTAssertNil(agent.error)
    }
}

final class AgentModelTests: XCTestCase {
    func testStatusMappingFromEntry() {
        let entry = AgentEntryModel(
            id: "ag-1", name: "c", agentType: "claude", status: "running",
            tmuxTarget: "s:1", prompt: "x", resultFile: "/r", startedAt: "t",
            completedAt: nil, exitCode: nil, error: nil
        )
        let model = AgentModel(from: entry)
        XCTAssertEqual(model.status, .running)
    }

    func testUnknownStatusMapsToLost() {
        let entry = AgentEntryModel(
            id: "ag-1", name: "c", agentType: "claude", status: "unknown_status",
            tmuxTarget: "s:1", prompt: "x", resultFile: "/r", startedAt: "t",
            completedAt: nil, exitCode: nil, error: nil
        )
        let model = AgentModel(from: entry)
        XCTAssertEqual(model.status, .lost)
    }
}

final class WorktreeModelTests: XCTestCase {
    func testIsClassWithObjectIdentity() {
        let a = WorktreeModel(id: "wt-1", name: "n", path: "/tmp/wt", branch: "b", status: "active", tmuxWindow: "w", agents: [])
        let b = a
        XCTAssert(a === b)
    }
}

final class LaunchConfigTests: XCTestCase {
    func testParseWithValidArgs() {
        let config = LaunchConfig.parse(["app", "--manifest-path", "/foo/.pg/manifest.json", "--session-name", "ppg-foo"])
        XCTAssertEqual(config.manifestPath, "/foo/.pg/manifest.json")
        XCTAssertEqual(config.sessionName, "ppg-foo")
        XCTAssertEqual(config.projectName, "foo")
        XCTAssertEqual(config.projectRoot, "/foo")
    }

    func testParseWithMissingArgs() {
        let config = LaunchConfig.parse(["app"])
        XCTAssertEqual(config.manifestPath, "")
        XCTAssertEqual(config.sessionName, "")
        XCTAssertEqual(config.projectName, "")
        XCTAssertEqual(config.projectRoot, "")
    }

    func testParseWithArgsInDifferentOrder() {
        let config = LaunchConfig.parse(["app", "--session-name", "ppg-bar", "--manifest-path", "/bar/.pg/manifest.json"])
        XCTAssertEqual(config.manifestPath, "/bar/.pg/manifest.json")
        XCTAssertEqual(config.sessionName, "ppg-bar")
        XCTAssertEqual(config.projectName, "bar")
    }

    func testProjectNameDerivation() {
        let config = LaunchConfig.parse(["app", "--manifest-path", "/Users/jono/Production/my-app/.pg/manifest.json"])
        XCTAssertEqual(config.projectName, "my-app")
        XCTAssertEqual(config.projectRoot, "/Users/jono/Production/my-app")
    }

    func testExplicitProjectRoot() {
        let config = LaunchConfig.parse(["app", "--project-root", "/custom/root", "--manifest-path", "/foo/.pg/manifest.json"])
        XCTAssertEqual(config.projectRoot, "/custom/root")
        XCTAssertEqual(config.projectName, "root")
    }

    func testAgentCommandDefault() {
        let config = LaunchConfig.parse(["app"])
        XCTAssertEqual(config.agentCommand, "claude --dangerously-skip-permissions")
    }

    func testAgentCommandOverride() {
        let config = LaunchConfig.parse(["app", "--agent-command", "my-agent --flag"])
        XCTAssertEqual(config.agentCommand, "my-agent --flag")
    }
}
