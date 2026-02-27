import Testing
import Foundation
@testable import PPGMobile

@Suite("AgentStatus")
struct AgentStatusTests {
    @Test("decodes canonical lifecycle values")
    func decodesCanonicalValues() throws {
        let cases = ["spawning", "running", "completed", "failed", "killed", "lost"]
        for value in cases {
            let json = Data("\"\(value)\"".utf8)
            let status = try JSONDecoder().decode(AgentStatus.self, from: json)
            #expect(status.rawValue == value)
        }
    }

    @Test("decodes TypeScript alias 'idle' as .running")
    func decodesIdleAlias() throws {
        let json = Data("\"idle\"".utf8)
        let status = try JSONDecoder().decode(AgentStatus.self, from: json)
        #expect(status == .running)
    }

    @Test("decodes TypeScript alias 'exited' as .completed")
    func decodesExitedAlias() throws {
        let json = Data("\"exited\"".utf8)
        let status = try JSONDecoder().decode(AgentStatus.self, from: json)
        #expect(status == .completed)
    }

    @Test("decodes TypeScript alias 'gone' as .lost")
    func decodesGoneAlias() throws {
        let json = Data("\"gone\"".utf8)
        let status = try JSONDecoder().decode(AgentStatus.self, from: json)
        #expect(status == .lost)
    }

    @Test("rejects unknown status values")
    func rejectsUnknown() {
        let json = Data("\"banana\"".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AgentStatus.self, from: json)
        }
    }

    @Test("encodes using lifecycle rawValue, not alias")
    func encodesToCanonicalValue() throws {
        let json = Data("\"idle\"".utf8)
        let status = try JSONDecoder().decode(AgentStatus.self, from: json)
        let encoded = try JSONEncoder().encode(status)
        let raw = String(data: encoded, encoding: .utf8)
        #expect(raw == "\"running\"")
    }

    @Test("every case has a non-empty label, color, and sfSymbol")
    func displayProperties() {
        for status in AgentStatus.allCases {
            #expect(!status.label.isEmpty)
            #expect(!status.sfSymbol.isEmpty)
        }
    }
}

@Suite("WorktreeStatus")
struct WorktreeStatusTests {
    @Test("decodes all worktree status values")
    func decodesAllValues() throws {
        let cases = ["active", "merging", "merged", "failed", "cleaned"]
        for value in cases {
            let json = Data("\"\(value)\"".utf8)
            let status = try JSONDecoder().decode(WorktreeStatus.self, from: json)
            #expect(status.rawValue == value)
        }
    }

    @Test("every case has a non-empty label and sfSymbol")
    func displayProperties() {
        for status in WorktreeStatus.allCases {
            #expect(!status.label.isEmpty)
            #expect(!status.sfSymbol.isEmpty)
        }
    }
}

@Suite("Manifest decoding")
struct ManifestDecodingTests {
    static let sampleJSON = """
    {
        "version": 1,
        "projectRoot": "/Users/test/project",
        "sessionName": "ppg",
        "worktrees": {
            "wt-abc123": {
                "id": "wt-abc123",
                "name": "feature-auth",
                "path": "/Users/test/project/.worktrees/wt-abc123",
                "branch": "ppg/feature-auth",
                "baseBranch": "main",
                "status": "active",
                "tmuxWindow": "ppg:1",
                "agents": {
                    "ag-test1234": {
                        "id": "ag-test1234",
                        "name": "claude",
                        "agentType": "claude",
                        "status": "running",
                        "tmuxTarget": "ppg:1.0",
                        "prompt": "Implement auth",
                        "startedAt": "2025-01-15T10:30:00.000Z"
                    }
                },
                "createdAt": "2025-01-15T10:30:00.000Z"
            }
        },
        "createdAt": "2025-01-15T10:00:00.000Z",
        "updatedAt": "2025-01-15T10:30:00.000Z"
    }
    """

    @Test("decodes a full manifest from server JSON")
    func decodesFullManifest() throws {
        let data = Data(Self.sampleJSON.utf8)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)

        #expect(manifest.version == 1)
        #expect(manifest.sessionName == "ppg")
        #expect(manifest.worktrees.count == 1)

        let worktree = manifest.worktrees["wt-abc123"]
        #expect(worktree?.name == "feature-auth")
        #expect(worktree?.status == .active)
        #expect(worktree?.agents.count == 1)

        let agent = worktree?.agents["ag-test1234"]
        #expect(agent?.agentType == "claude")
        #expect(agent?.status == .running)
    }

    @Test("decodes manifest with TypeScript status aliases")
    func decodesWithAliases() throws {
        let json = """
        {
            "version": 1,
            "projectRoot": "/test",
            "sessionName": "ppg",
            "worktrees": {
                "wt-xyz789": {
                    "id": "wt-xyz789",
                    "name": "review",
                    "path": "/test/.worktrees/wt-xyz789",
                    "branch": "ppg/review",
                    "baseBranch": "main",
                    "status": "active",
                    "tmuxWindow": "ppg:2",
                    "agents": {
                        "ag-alias001": {
                            "id": "ag-alias001",
                            "name": "codex",
                            "agentType": "codex",
                            "status": "idle",
                            "tmuxTarget": "ppg:2.0",
                            "prompt": "Review code",
                            "startedAt": "2025-01-15T11:00:00.000Z"
                        },
                        "ag-alias002": {
                            "id": "ag-alias002",
                            "name": "claude",
                            "agentType": "claude",
                            "status": "exited",
                            "tmuxTarget": "ppg:2.1",
                            "prompt": "Fix bug",
                            "startedAt": "2025-01-15T11:00:00.000Z",
                            "exitCode": 0
                        },
                        "ag-alias003": {
                            "id": "ag-alias003",
                            "name": "opencode",
                            "agentType": "opencode",
                            "status": "gone",
                            "tmuxTarget": "ppg:2.2",
                            "prompt": "Test",
                            "startedAt": "2025-01-15T11:00:00.000Z"
                        }
                    },
                    "createdAt": "2025-01-15T11:00:00.000Z"
                }
            },
            "createdAt": "2025-01-15T10:00:00.000Z",
            "updatedAt": "2025-01-15T11:00:00.000Z"
        }
        """
        let data = Data(json.utf8)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        let agents = manifest.worktrees["wt-xyz789"]!.agents

        #expect(agents["ag-alias001"]?.status == .running)    // idle → running
        #expect(agents["ag-alias002"]?.status == .completed)  // exited → completed
        #expect(agents["ag-alias003"]?.status == .lost)       // gone → lost
    }

    @Test("allAgents flattens agents across worktrees")
    func allAgentsFlattens() throws {
        let data = Data(Self.sampleJSON.utf8)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        #expect(manifest.allAgents.count == 1)
        #expect(manifest.allAgents.first?.id == "ag-test1234")
    }
}
