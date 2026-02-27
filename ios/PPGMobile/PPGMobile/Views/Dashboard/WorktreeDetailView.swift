import SwiftUI

struct WorktreeDetailView: View {
    let worktreeId: String
    @Bindable var store: DashboardStore

    @State private var confirmingMerge = false
    @State private var confirmingKill = false

    private var worktree: Worktree? {
        store.worktree(by: worktreeId)
    }

    var body: some View {
        Group {
            if let worktree {
                List {
                    infoSection(worktree)
                    diffStatsSection(worktree)
                    agentsSection(worktree)
                    actionsSection(worktree)
                }
                .listStyle(.insetGrouped)
                .navigationTitle(worktree.name)
                .navigationBarTitleDisplayMode(.large)
                .confirmationDialog("Merge Worktree", isPresented: $confirmingMerge) {
                    Button("Squash Merge") {
                        Task { await store.mergeWorktree(worktreeId) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Merge \"\(worktree.name)\" back to the base branch?")
                }
                .confirmationDialog("Kill Worktree", isPresented: $confirmingKill) {
                    Button("Kill All Agents", role: .destructive) {
                        Task { await store.killWorktree(worktreeId) }
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

    private func infoSection(_ worktree: Worktree) -> some View {
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

            LabeledContent("Created") {
                Text(worktree.createdAt, style: .relative)
            }

            if let mergedAt = worktree.mergedAt {
                LabeledContent("Merged") {
                    Text(mergedAt, style: .relative)
                }
            }
        } header: {
            Text("Details")
        }
    }

    // MARK: - Diff Stats Section

    @ViewBuilder
    private func diffStatsSection(_ worktree: Worktree) -> some View {
        if let stats = worktree.diffStats {
            Section {
                LabeledContent("Files Changed") {
                    Text("\(stats.filesChanged)")
                }

                LabeledContent("Insertions") {
                    Text("+\(stats.insertions)")
                        .foregroundStyle(.green)
                }

                LabeledContent("Deletions") {
                    Text("-\(stats.deletions)")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Changes")
            }
        }
    }

    // MARK: - Agents Section

    private func agentsSection(_ worktree: Worktree) -> some View {
        Section {
            if worktree.agents.isEmpty {
                Text("No agents")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(worktree.agents) { agent in
                    AgentRow(
                        agent: agent,
                        onKill: {
                            Task { await store.killAgent(agent.id, in: worktreeId) }
                        },
                        onRestart: {
                            Task { await store.restartAgent(agent.id, in: worktreeId) }
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

    private func actionsSection(_ worktree: Worktree) -> some View {
        Section {
            if worktree.status == .running {
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
                // TODO: Wire to store.createPullRequest(for:)
                Task { await store.createPullRequest(for: worktreeId) }
            } label: {
                Label("Create Pull Request", systemImage: "arrow.triangle.pull")
            }
            .disabled(worktree.status != .running && worktree.status != .merged)
        } header: {
            Text("Actions")
        }
    }

    // MARK: - Helpers

    private func agentSummary(_ worktree: Worktree) -> String {
        let active = worktree.agents.filter { $0.status.isActive }.count
        let total = worktree.agents.count
        if active > 0 {
            return "\(active)/\(total) active"
        }
        return "\(total) total"
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        WorktreeDetailView(
            worktreeId: "wt-abc123",
            store: .preview
        )
    }
}
#endif
