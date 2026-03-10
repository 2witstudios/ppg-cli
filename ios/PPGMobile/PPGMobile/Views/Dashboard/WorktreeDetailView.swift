import SwiftUI

struct WorktreeDetailView: View {
    let worktreeId: String
    @Environment(AppState.self) private var appState

    @State private var confirmingMerge = false
    @State private var confirmingKill = false

    private var worktree: WorktreeEntry? {
        appState.manifest?.worktrees[worktreeId]
    }

    var body: some View {
        Group {
            if let worktree {
                List {
                    infoSection(worktree)
                    agentsSection(worktree)
                    actionsSection(worktree)
                }
                .listStyle(.insetGrouped)
                .navigationTitle(worktree.name)
                .navigationBarTitleDisplayMode(.large)
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

    // MARK: - Agents Section

    private func agentsSection(_ worktree: WorktreeEntry) -> some View {
        Section {
            if worktree.agents.isEmpty {
                Text("No agents")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(worktree.sortedAgents) { agent in
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
