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
            if let worktree = store.worktree(by: worktreeId) {
                WorktreeDetailView(worktreeId: worktree.id, store: store)
            } else {
                ContentUnavailableView(
                    "Worktree Not Found",
                    systemImage: "questionmark.folder",
                    description: Text("This worktree may have been removed.")
                )
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

#if DEBUG
#Preview("Connected with worktrees") {
    DashboardView(store: .preview)
}

#Preview("Empty state") {
    DashboardView(store: .previewEmpty)
}

#Preview("Disconnected") {
    DashboardView(store: .previewDisconnected)
}
#endif
