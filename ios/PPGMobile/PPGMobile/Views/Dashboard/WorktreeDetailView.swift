import SwiftUI

struct WorktreeDetailView: View {
    let worktree: Worktree
    @Bindable var store: DashboardStore

    @State private var confirmingMerge = false
    @State private var confirmingKill = false

    var body: some View {
        List {
            infoSection
            agentsSection
            actionsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(worktree.name)
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Merge Worktree", isPresented: $confirmingMerge) {
            Button("Squash Merge") {
                Task { await store.mergeWorktree(worktree.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Merge \"\(worktree.name)\" back to the base branch?")
        }
        .confirmationDialog("Kill Worktree", isPresented: $confirmingKill) {
            Button("Kill All Agents", role: .destructive) {
                Task { await store.killWorktree(worktree.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Kill all agents in \"\(worktree.name)\"? This cannot be undone.")
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
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

    // MARK: - Agents Section

    private var agentsSection: some View {
        Section {
            if worktree.agents.isEmpty {
                Text("No agents")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(worktree.agents) { agent in
                    AgentRow(
                        agent: agent,
                        onKill: {
                            Task { await store.killAgent(agent.id, in: worktree.id) }
                        },
                        onRestart: {
                            Task { await store.restartAgent(agent.id, in: worktree.id) }
                        }
                    )
                }
            }
        } header: {
            HStack {
                Text("Agents")
                Spacer()
                Text(agentSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
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
                // PR creation — will be wired to store action
            } label: {
                Label("Create Pull Request", systemImage: "arrow.triangle.pull")
            }
            .disabled(worktree.status != .running && worktree.status != .merged)
        } header: {
            Text("Actions")
        }
    }

    // MARK: - Helpers

    private var agentSummary: String {
        let active = worktree.agents.filter { $0.status.isActive }.count
        let total = worktree.agents.count
        if active > 0 {
            return "\(active)/\(total) active"
        }
        return "\(total) total"
    }
}

#Preview {
    NavigationStack {
        WorktreeDetailView(
            worktree: Worktree(
                id: "wt-abc123",
                name: "auth-feature",
                branch: "ppg/auth-feature",
                path: ".worktrees/wt-abc123",
                status: .running,
                agents: [
                    Agent(id: "ag-11111111", name: "claude-1", agentType: "claude", status: .running, prompt: "Implement OAuth2 authentication flow with JWT tokens", startedAt: .now.addingTimeInterval(-300), completedAt: nil, exitCode: nil, error: nil),
                    Agent(id: "ag-22222222", name: "claude-2", agentType: "claude", status: .completed, prompt: "Write integration tests for auth", startedAt: .now.addingTimeInterval(-600), completedAt: .now.addingTimeInterval(-120), exitCode: 0, error: nil),
                    Agent(id: "ag-33333333", name: "codex-1", agentType: "codex", status: .failed, prompt: "Set up auth middleware", startedAt: .now.addingTimeInterval(-500), completedAt: .now.addingTimeInterval(-200), exitCode: 1, error: "Process exited with code 1"),
                ],
                createdAt: .now.addingTimeInterval(-3600),
                mergedAt: nil
            ),
            store: .preview
        )
    }
}
