import SwiftUI

/// Terminal output view that subscribes to WebSocket terminal streaming.
/// Displays raw text output from tmux capture-pane with ANSI stripped server-side.
struct TerminalView: View {
    let agentId: String
    let agentName: String

    @Environment(AppState.self) private var appState
    @State private var terminalOutput = ""
    @State private var inputText = ""
    @State private var isSubscribed = false
    @State private var showKillConfirm = false
    @State private var previousOnMessage: ((ServerMessage) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(terminalOutput.isEmpty ? "Connecting to terminal..." : terminalOutput)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .id("terminal-bottom")
                }
                .background(Color.black)
                .foregroundStyle(.green)
                .onChange(of: terminalOutput) { _, _ in
                    withAnimation {
                        proxy.scrollTo("terminal-bottom", anchor: .bottom)
                    }
                }
            }

            TerminalInputBar(text: $inputText) {
                guard !inputText.isEmpty else { return }
                appState.wsManager.sendTerminalInput(agentId: agentId, text: inputText)
                inputText = ""
            }
        }
        .navigationTitle(agentName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Kill", systemImage: "xmark.circle") {
                    showKillConfirm = true
                }
                .tint(.red)
                .disabled(agentIsTerminal)
            }
        }
        .confirmationDialog("Kill Agent", isPresented: $showKillConfirm) {
            Button("Kill Agent", role: .destructive) {
                Task { await appState.killAgent(agentId) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { subscribe() }
        .onDisappear { unsubscribe() }
    }

    private var agentIsTerminal: Bool {
        guard let manifest = appState.manifest else { return true }
        for worktree in manifest.worktrees.values {
            if let agent = worktree.agents[agentId] {
                return agent.status.isTerminal
            }
        }
        return true
    }

    private func subscribe() {
        guard !isSubscribed else { return }
        isSubscribed = true

        // Fetch initial log content
        Task {
            if let client = appState.client {
                do {
                    let logs = try await client.fetchLogs(agentId: agentId, lines: 200)
                    terminalOutput = logs.output
                } catch {
                    terminalOutput = "Failed to load logs: \(error.localizedDescription)"
                }
            }
        }

        // Subscribe to live updates via WebSocket
        appState.wsManager.subscribeTerminal(agentId: agentId)

        // Chain onto existing message handler to avoid overwriting AppState's handler
        previousOnMessage = appState.wsManager.onMessage
        let existingHandler = previousOnMessage
        appState.wsManager.onMessage = { message in
            // Forward to existing handler (AppState)
            existingHandler?(message)

            // Handle terminal output for this agent
            if message.type == "terminal:output" && message.agentId == agentId {
                Task { @MainActor in
                    if let data = message.data {
                        terminalOutput += data
                    }
                }
            }
        }
    }

    private func unsubscribe() {
        guard isSubscribed else { return }
        isSubscribed = false
        appState.wsManager.unsubscribeTerminal(agentId: agentId)

        // Restore the previous message handler
        appState.wsManager.onMessage = previousOnMessage
        previousOnMessage = nil
    }
}
