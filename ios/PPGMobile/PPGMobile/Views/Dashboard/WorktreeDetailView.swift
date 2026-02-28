import SwiftUI

struct WorktreeDetailView: View {
    let worktreeId: String
    @Environment(AppState.self) private var appState
    @Environment(NavigationRouter.self) private var router

    @State private var confirmingMerge = false
    @State private var confirmingKill = false
    @State private var diffFiles: [DiffFile] = []
    @State private var loadingDiff = false

    private var worktree: WorktreeEntry? {
        // Single-project manifest
        if let found = appState.manifest?.worktrees[worktreeId] {
            return found
        }
        // Multi-project: search all project manifests
        for project in (appState.projects ?? []) {
            if let found = project.manifest.worktrees[worktreeId] {
                return found
            }
        }
        return nil
    }

    var body: some View {
        Group {
            if let worktree {
                List {
                    infoSection(worktree)
                    diffSection(worktree)
                    agentsSection(worktree)
                    actionsSection(worktree)
                }
                .listStyle(.insetGrouped)
                .navigationTitle(worktree.name)
                .navigationBarTitleDisplayMode(.inline)
                .confirmationDialog("Merge Worktree", isPresented: $confirmingMerge) {
                    Button("Squash Merge") {
                        Task {
                            try? await appState.client.mergeWorktree(worktreeId: worktreeId)
                            await appState.manifestStore.refresh()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Merge \"\(worktree.name)\" back to the base branch?")
                }
                .confirmationDialog("Kill Worktree", isPresented: $confirmingKill) {
                    Button("Kill All Agents", role: .destructive) {
                        Task {
                            try? await appState.client.killWorktree(worktreeId: worktreeId)
                            await appState.manifestStore.refresh()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Kill all agents in \"\(worktree.name)\"? This cannot be undone.")
                }
            } else {
                ContentUnavailableView(
                    "Worktree Not Found",
                    systemImage: "questionmark.folder",
                    description: Text("This worktree may have been removed.")
                )
            }
        }
    }

    // MARK: - Info Section

    private func infoSection(_ worktree: WorktreeEntry) -> some View {
        Section {
            LabeledContent("Status") {
                HStack(spacing: 4) {
                    Image(systemName: worktree.status.icon)
                        .font(.caption2)
                    Text(worktree.status.label)
                        .fontWeight(.medium)
                }
                .foregroundStyle(worktree.status.color)
            }

            LabeledContent("Branch") {
                Text(worktree.branch)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Agents") {
                Text("\(worktree.agents.count)")
            }

            if let date = worktree.createdDate {
                LabeledContent("Created") {
                    Text(date, style: .relative)
                }
            }

            if let mergedDate = worktree.mergedDate {
                LabeledContent("Merged") {
                    Text(mergedDate, style: .relative)
                }
            }
        } header: {
            Text("Details")
        }
    }

    // MARK: - Diff Section

    private func diffSection(_ worktree: WorktreeEntry) -> some View {
        Section {
            if loadingDiff {
                ProgressView()
            } else if diffFiles.isEmpty {
                Text("No changes")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(diffFiles) { file in
                    HStack {
                        Text(file.file)
                            .font(.footnote.monospaced())
                            .lineLimit(1)
                        Spacer()
                        Text("+\(file.added)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.green)
                        Text("-\(file.removed)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.red)
                    }
                }
            }
        } header: {
            HStack {
                Text("Changes")
                Spacer()
                if !diffFiles.isEmpty {
                    Text("\(diffFiles.count) files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            await loadDiff()
        }
    }

    private func loadDiff() async {
        loadingDiff = true
        defer { loadingDiff = false }
        do {
            let response = try await appState.client.fetchDiff(worktreeId: worktreeId)
            diffFiles = response.files
        } catch {
            diffFiles = []
        }
    }

    // MARK: - Agents Section

    private func agentsSection(_ worktree: WorktreeEntry) -> some View {
        Section {
            if worktree.agents.isEmpty {
                Text("No agents")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(worktree.sortedAgents) { agent in
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
        } header: {
            HStack {
                Text("Agents")
                Spacer()
                Text(agentSummary(worktree))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions Section

    private func actionsSection(_ worktree: WorktreeEntry) -> some View {
        Section {
            if !worktree.agents.isEmpty {
                Button {
                    router.navigateToPaneGrid(worktreeId: worktreeId)
                } label: {
                    Label("Terminal Grid", systemImage: "rectangle.split.2x2")
                }
            }

            if worktree.status == .active || worktree.status == .running {
                Button {
                    confirmingMerge = true
                } label: {
                    Label("Merge Worktree", systemImage: "arrow.triangle.merge")
                }

                Button(role: .destructive) {
                    confirmingKill = true
                } label: {
                    Label("Kill All Agents", systemImage: "xmark.octagon")
                }
            }

            Button {
                Task {
                    try? await appState.client.createPR(worktreeId: worktreeId)
                    await appState.manifestStore.refresh()
                }
            } label: {
                Label("Create Pull Request", systemImage: "arrow.triangle.pull")
            }
            .disabled(worktree.status != .active && worktree.status != .running && worktree.status != .merged)
        } header: {
            Text("Actions")
        }
    }

    // MARK: - Helpers

    private func agentSummary(_ worktree: WorktreeEntry) -> String {
        let active = worktree.sortedAgents.filter { $0.status.isActive }.count
        let total = worktree.agents.count
        if active > 0 {
            return "\(active)/\(total) active"
        }
        return "\(total) total"
    }
}
