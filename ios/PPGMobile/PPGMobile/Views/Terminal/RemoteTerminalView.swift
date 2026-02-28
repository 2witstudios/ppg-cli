import SwiftUI

/// Full-screen terminal view with chrome for a single agent.
/// Uses SwiftTermView for VT100 rendering over WebSocket.
struct RemoteTerminalView: View {
    let agentId: String
    let agentName: String

    @Environment(AppState.self) private var appState
    @State private var showKillConfirm = false

    var body: some View {
        SwiftTermView(agentId: agentId)
            .navigationTitle(agentName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                try? await appState.client.restartAgent(agentId: agentId)
                                await appState.manifestStore.refresh()
                            }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .disabled(agentIsTerminal)

                        Button("Kill", systemImage: "xmark.circle") {
                            showKillConfirm = true
                        }
                        .tint(.red)
                        .disabled(agentIsTerminal)
                    }
                }
            }
            .confirmationDialog("Kill Agent", isPresented: $showKillConfirm) {
                Button("Kill Agent", role: .destructive) {
                    Task { await appState.killAgent(agentId) }
                }
                Button("Cancel", role: .cancel) {}
            }
    }

    private var agentIsTerminal: Bool {
        // Check root-level (master) agents
        if let agent = appState.manifest?.agents[agentId] {
            return agent.status.isTerminal
        }
        // Check worktree agents
        if let manifest = appState.manifest {
            for worktree in manifest.worktrees.values {
                if let agent = worktree.agents[agentId] {
                    return agent.status.isTerminal
                }
            }
        }
        // Multi-project fallback
        for project in (appState.projects ?? []) {
            if let agent = project.manifest.agents[agentId] {
                return agent.status.isTerminal
            }
            for worktree in project.manifest.worktrees.values {
                if let agent = worktree.agents[agentId] {
                    return agent.status.isTerminal
                }
            }
        }
        return true
    }
}
