import SwiftUI

/// Project overview dashboard with multi-project cards, aggregate stats, and agent status dots.
struct HomeDashboardView: View {
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
                connectedContent
            case .error(let message):
                errorView(message)
            }
        }
        .navigationTitle(appState.manifest?.sessionName ?? "PPG")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await appState.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(appState.activeConnection == nil)
            }
        }
    }

    // MARK: - Connected Content

    @ViewBuilder
    private var connectedContent: some View {
        if let projects = appState.projects, !projects.isEmpty {
            multiProjectView(projects)
        } else if let manifest = appState.manifest {
            singleProjectView(manifest)
        } else {
            emptyStateView
        }
    }

    // MARK: - Multi-Project View

    private func multiProjectView(_ projects: [ProjectInfo]) -> some View {
        let allWorktrees = projects.flatMap { $0.manifest.sortedWorktrees }
        let allAgents = projects.flatMap { $0.manifest.allAgents }
        let running = allAgents.filter { $0.status == .running || $0.status == .spawning }.count
        let completed = allAgents.filter { $0.status == .completed }.count
        let failed = allAgents.filter { $0.status == .failed }.count

        return ScrollView {
            LazyVStack(spacing: 8) {
                // Aggregate stats bar
                HStack {
                    let masterCount = projects.flatMap { $0.manifest.sortedMasterAgents }.count
                    Text("\(projects.count) projects, \(allWorktrees.count) worktrees\(masterCount > 0 ? ", \(masterCount) project agents" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 8) {
                        if running > 0 {
                            Label("\(running) running", systemImage: "bolt.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                        if completed > 0 {
                            Label("\(completed) completed", systemImage: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        if failed > 0 {
                            Label("\(failed) failed", systemImage: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.horizontal, 4)

                // Per-project cards
                ForEach(projects) { project in
                    ProjectCardView(project: project)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .refreshable {
            await appState.refreshAll()
        }
    }

    // MARK: - Single Project View

    private func singleProjectView(_ manifest: Manifest) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Stats grid
                statsGrid(manifest)

                // Commit heatmap
                CommitHeatmapView()
                    .frame(height: 100)
                    .glassCard()

                // Project-level agents (point guards, conductors, etc.)
                if !appState.manifestStore.sortedMasterAgents.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project Agents")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 4)

                        ForEach(appState.manifestStore.sortedMasterAgents.prefix(5)) { agent in
                            Button {
                                router.navigateToAgent(agentId: agent.id, agentName: agent.name)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: agent.status.sfSymbol)
                                        .foregroundStyle(agent.status.color)
                                        .font(.caption)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(agent.name)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        Text(agent.agentType)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(agent.status.label)
                                        .font(.caption2)
                                        .foregroundStyle(agent.status.color)
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .glassCard()
                }

                // Recent worktrees
                if !appState.manifestStore.sortedWorktrees.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent Worktrees")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 4)

                        ForEach(appState.manifestStore.sortedWorktrees.prefix(5)) { worktree in
                            Button {
                                router.navigateToWorktree(worktree.id)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: worktree.status.icon)
                                        .foregroundStyle(worktree.status.color)
                                        .font(.caption)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(worktree.name)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        Text(worktree.branch)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    agentDots(worktree)
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .glassCard()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .refreshable {
            await appState.refreshAll()
        }
    }

    // MARK: - Stats Grid

    @ViewBuilder
    private func statsGrid(_ manifest: Manifest) -> some View {
        let counts = appState.manifestStore.agentCounts
        let totalAgents = appState.manifestStore.allAgents.count
        let activeAgents = (counts[.running] ?? 0) + (counts[.spawning] ?? 0)

        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 8) {
            StatCard(title: "Worktrees", value: "\(manifest.worktrees.count)", icon: "arrow.triangle.branch")
            StatCard(title: "Agents", value: "\(totalAgents)", icon: "person.2")
            StatCard(title: "Active", value: "\(activeAgents)", icon: "bolt.fill")
        }
    }

    // MARK: - Agent Dots

    private func agentDots(_ worktree: WorktreeEntry) -> some View {
        HStack(spacing: 3) {
            ForEach(worktree.sortedAgents.prefix(6)) { agent in
                Circle()
                    .fill(agent.status.color)
                    .frame(width: 6, height: 6)
            }
            if worktree.agents.count > 6 {
                Text("+\(worktree.agents.count - 6)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
                Task { await appState.refreshAll() }
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

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .glassCard()
    }
}
