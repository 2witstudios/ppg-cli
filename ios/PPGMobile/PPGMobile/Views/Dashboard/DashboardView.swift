import SwiftUI

struct DashboardView: View {
    @Bindable var store: DashboardStore

    var body: some View {
        NavigationStack {
            Group {
                switch store.connectionState {
                case .disconnected:
                    disconnectedView
                case .connecting:
                    ProgressView("Connecting...")
                case .connected:
                    if store.worktrees.isEmpty {
                        emptyStateView
                    } else {
                        worktreeList
                    }
                }
            }
            .navigationTitle(store.projectName)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    connectionIndicator
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(store.connectionState != .connected)
                }
            }
        }
    }

    // MARK: - Worktree List

    private var worktreeList: some View {
        List {
            if !activeWorktrees.isEmpty {
                Section("Active") {
                    ForEach(activeWorktrees) { worktree in
                        NavigationLink(value: worktree.id) {
                            WorktreeCard(worktree: worktree)
                        }
                    }
                }
            }

            if !completedWorktrees.isEmpty {
                Section("Completed") {
                    ForEach(completedWorktrees) { worktree in
                        NavigationLink(value: worktree.id) {
                            WorktreeCard(worktree: worktree)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await store.refresh()
        }
        .navigationDestination(for: String.self) { worktreeId in
            if let worktree = store.worktrees.first(where: { $0.id == worktreeId }) {
                WorktreeDetailView(worktree: worktree, store: store)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Worktrees", systemImage: "arrow.triangle.branch")
        } description: {
            Text("Spawn agents from the CLI to see them here.")
        } actions: {
            Button("Refresh") {
                Task { await store.refresh() }
            }
        }
    }

    // MARK: - Disconnected State

    private var disconnectedView: some View {
        ContentUnavailableView {
            Label("Disconnected", systemImage: "wifi.slash")
        } description: {
            Text("Unable to reach the ppg service. Check that the CLI is running and the server is started.")
        } actions: {
            Button("Retry") {
                Task { await store.connect() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Connection Indicator

    private var connectionIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)
            Text(connectionLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var activeWorktrees: [Worktree] {
        store.worktrees.filter { !$0.status.isTerminal }
    }

    private var completedWorktrees: [Worktree] {
        store.worktrees.filter { $0.status.isTerminal }
    }

    private var connectionColor: Color {
        switch store.connectionState {
        case .connected: .green
        case .connecting: .yellow
        case .disconnected: .red
        }
    }

    private var connectionLabel: String {
        switch store.connectionState {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .disconnected: "Disconnected"
        }
    }
}

// MARK: - Domain Models

enum ConnectionState {
    case disconnected
    case connecting
    case connected
}

struct Worktree: Identifiable {
    let id: String
    let name: String
    let branch: String
    let path: String
    let status: WorktreeStatus
    let agents: [Agent]
    let createdAt: Date
    let mergedAt: Date?
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

// MARK: - Store Protocol

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
}

#Preview("Connected with worktrees") {
    DashboardView(store: .preview)
}

#Preview("Empty state") {
    DashboardView(store: .previewEmpty)
}

#Preview("Disconnected") {
    DashboardView(store: .previewDisconnected)
}

// MARK: - Preview Helpers

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
