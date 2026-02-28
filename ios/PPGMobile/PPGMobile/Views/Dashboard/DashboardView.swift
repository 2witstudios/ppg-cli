import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState

    @Environment(NavigationRouter.self) private var router

    var body: some View {
        Group {
            switch appState.connectionStatus {
            case .disconnected:
                disconnectedView
            case .connecting:
                ProgressView("Connecting...")
            case .connected:
                if appState.manifestStore.sortedWorktrees.isEmpty && appState.manifestStore.sortedMasterAgents.isEmpty {
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

    // MARK: - Worktree List

    private var worktreeList: some View {
        let worktrees = appState.manifestStore.sortedWorktrees
        let masterAgents = appState.manifestStore.sortedMasterAgents

        return List {
            // Project-level agents (point guards, conductors, etc.)
            if !masterAgents.isEmpty {
                let activeMaster = masterAgents.filter { $0.status.isActive }
                let inactiveMaster = masterAgents.filter { !$0.status.isActive }

                if !activeMaster.isEmpty {
                    Section("Project Agents") {
                        ForEach(activeMaster) { agent in
                            Button {
                                router.navigateToAgent(agentId: agent.id, agentName: agent.name)
                            } label: {
                                AgentRow(
                                    agent: agent,
                                    onKill: {
                                        Task { await appState.killAgent(agent.id) }
                                    },
                                    onRestart: {
                                        Task {
                                            try? await appState.client.restartAgent(agentId: agent.id)
                                            await appState.manifestStore.refresh()
                                        }
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !inactiveMaster.isEmpty {
                    Section("Project Agents — Finished") {
                        ForEach(inactiveMaster) { agent in
                            Button {
                                router.navigateToAgent(agentId: agent.id, agentName: agent.name)
                            } label: {
                                AgentRow(agent: agent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            let active = worktrees.filter { !$0.status.isTerminal }
            let completed = worktrees.filter { $0.status.isTerminal }

            if !active.isEmpty {
                Section("Active") {
                    ForEach(active) { worktree in
                        Button {
                            router.navigateToWorktree(worktree.id)
                        } label: {
                            WorktreeCard(worktree: worktree)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !completed.isEmpty {
                Section("Completed") {
                    ForEach(completed) { worktree in
                        Button {
                            router.navigateToWorktree(worktree.id)
                        } label: {
                            WorktreeCard(worktree: worktree)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await appState.manifestStore.refresh()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Agents", systemImage: "person.2.slash")
        } description: {
            Text("Spawn agents from the CLI or dashboard to see them here.")
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
