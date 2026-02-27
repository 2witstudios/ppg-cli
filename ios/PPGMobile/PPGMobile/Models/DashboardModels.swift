import SwiftUI

// MARK: - Connection

enum ConnectionState {
    case disconnected
    case connecting
    case connected
}

// MARK: - Worktree

struct Worktree: Identifiable {
    let id: String
    let name: String
    let branch: String
    let path: String
    let status: WorktreeStatus
    let agents: [Agent]
    let diffStats: DiffStats?
    let createdAt: Date
    let mergedAt: Date?
}

struct DiffStats {
    let filesChanged: Int
    let insertions: Int
    let deletions: Int
}

enum WorktreeStatus: String {
    case spawning
    case running
    case merged
    case cleaned
    case merging

    var isTerminal: Bool {
        self == .merged || self == .cleaned
    }

    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .spawning: .yellow
        case .running: .green
        case .merging: .orange
        case .merged: .blue
        case .cleaned: .secondary
        }
    }

    var icon: String {
        switch self {
        case .spawning: "hourglass"
        case .running: "play.circle.fill"
        case .merging: "arrow.triangle.merge"
        case .merged: "checkmark.circle.fill"
        case .cleaned: "archivebox"
        }
    }
}

// MARK: - Agent

struct Agent: Identifiable {
    let id: String
    let name: String
    let agentType: String
    let status: AgentStatus
    let prompt: String
    let startedAt: Date
    let completedAt: Date?
    let exitCode: Int?
    let error: String?
}

enum AgentStatus: String, CaseIterable {
    case spawning
    case running
    case waiting
    case completed
    case failed
    case killed
    case lost

    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .running: .green
        case .completed: .blue
        case .failed: .red
        case .killed: .orange
        case .spawning: .yellow
        case .waiting, .lost: .secondary
        }
    }

    var icon: String {
        switch self {
        case .spawning: "hourglass"
        case .running: "play.circle.fill"
        case .waiting: "pause.circle"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .killed: "stop.circle.fill"
        case .lost: "questionmark.circle"
        }
    }

    var isActive: Bool {
        self == .spawning || self == .running || self == .waiting
    }
}

// MARK: - Store

@Observable
class DashboardStore {
    var projectName: String = ""
    var worktrees: [Worktree] = []
    var connectionState: ConnectionState = .disconnected

    func refresh() async {}
    func connect() async {}
    func killAgent(_ agentId: String, in worktreeId: String) async {}
    func restartAgent(_ agentId: String, in worktreeId: String) async {}
    func mergeWorktree(_ worktreeId: String) async {}
    func killWorktree(_ worktreeId: String) async {}
    func createPullRequest(for worktreeId: String) async {}

    func worktree(by id: String) -> Worktree? {
        worktrees.first { $0.id == id }
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension DashboardStore {
    static var preview: DashboardStore {
        let store = DashboardStore()
        store.projectName = "my-project"
        store.connectionState = .connected
        store.worktrees = [
            Worktree(
                id: "wt-abc123",
                name: "auth-feature",
                branch: "ppg/auth-feature",
                path: ".worktrees/wt-abc123",
                status: .running,
                agents: [
                    Agent(id: "ag-11111111", name: "claude-1", agentType: "claude", status: .running, prompt: "Implement auth", startedAt: .now.addingTimeInterval(-300), completedAt: nil, exitCode: nil, error: nil),
                    Agent(id: "ag-22222222", name: "claude-2", agentType: "claude", status: .completed, prompt: "Write tests", startedAt: .now.addingTimeInterval(-600), completedAt: .now.addingTimeInterval(-120), exitCode: 0, error: nil),
                ],
                diffStats: DiffStats(filesChanged: 12, insertions: 340, deletions: 45),
                createdAt: .now.addingTimeInterval(-3600),
                mergedAt: nil
            ),
            Worktree(
                id: "wt-def456",
                name: "fix-bug",
                branch: "ppg/fix-bug",
                path: ".worktrees/wt-def456",
                status: .merged,
                agents: [
                    Agent(id: "ag-33333333", name: "codex-1", agentType: "codex", status: .completed, prompt: "Fix the login bug", startedAt: .now.addingTimeInterval(-7200), completedAt: .now.addingTimeInterval(-3600), exitCode: 0, error: nil),
                ],
                diffStats: DiffStats(filesChanged: 3, insertions: 28, deletions: 12),
                createdAt: .now.addingTimeInterval(-86400),
                mergedAt: .now.addingTimeInterval(-3600)
            ),
        ]
        return store
    }

    static var previewEmpty: DashboardStore {
        let store = DashboardStore()
        store.projectName = "new-project"
        store.connectionState = .connected
        return store
    }

    static var previewDisconnected: DashboardStore {
        let store = DashboardStore()
        store.projectName = "my-project"
        store.connectionState = .disconnected
        return store
    }
}
#endif
