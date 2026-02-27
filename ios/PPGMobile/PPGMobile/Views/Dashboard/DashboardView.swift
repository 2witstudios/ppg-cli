import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            Group {
                switch appState.connectionStatus {
                case .disconnected:
                    disconnectedView
                case .connecting:
                    ProgressView("Connecting...")
                case .connected:
                    if appState.manifestStore.sortedWorktrees.isEmpty {
                        emptyStateView
                    } else {
                        worktreeList
                    }
                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle(appState.manifest?.sessionName ?? "PPG")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await appState.manifestStore.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(appState.activeConnection == nil)
                }
            }
        }
    }

    // MARK: - Worktree List

    private var worktreeList: some View {
        let worktrees = appState.manifestStore.sortedWorktrees

        return List {
            let active = worktrees.filter { !$0.status.isTerminal }
            let completed = worktrees.filter { $0.status.isTerminal }

            if !active.isEmpty {
                Section("Active") {
                    ForEach(active) { worktree in
                        NavigationLink(value: worktree.id) {
                            WorktreeCard(worktree: worktree)
                        }
                    }
                }
            }

            if !completed.isEmpty {
                Section("Completed") {
                    ForEach(completed) { worktree in
                        NavigationLink(value: worktree.id) {
                            WorktreeCard(worktree: worktree)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await appState.manifestStore.refresh()
        }
        .navigationDestination(for: String.self) { worktreeId in
            if appState.manifest?.worktrees[worktreeId] != nil {
                WorktreeDetailView(worktreeId: worktreeId)
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
                Task { await appState.manifestStore.refresh() }
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
                Task { await appState.autoConnect() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Error State

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Connection Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                appState.clearError()
                Task { await appState.autoConnect() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
