import Foundation
import SwiftUI

/// Terminal output view that subscribes to WebSocket terminal streaming.
/// Displays raw text output from tmux capture-pane with ANSI stripped server-side.
struct TerminalView: View {
    let agentId: String
    let agentName: String

    @Environment(AppState.self) private var appState
    @State private var viewModel = TerminalViewModel()
    @State private var inputText = ""
    @State private var showKillConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            terminalContent

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
        .task { await viewModel.subscribe(agentId: agentId, appState: appState) }
        .onDisappear { viewModel.unsubscribe(agentId: agentId, wsManager: appState.wsManager) }
    }

    @ViewBuilder
    private var terminalContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if viewModel.output.isEmpty {
                        Text(statusMessage)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    } else {
                        Text(viewModel.output)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .textSelection(.enabled)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("terminal-bottom")
                }
            }
            .defaultScrollAnchor(.bottom)
            .background(Color.black)
            .foregroundStyle(.green)
            .onChange(of: viewModel.output) { _, _ in
                withAnimation {
                    proxy.scrollTo("terminal-bottom", anchor: .bottom)
                }
            }
        }
    }

    private var statusMessage: String {
        if appState.activeConnection == nil {
            return "Not connected to server"
        }
        if viewModel.isSubscribed {
            return "Waiting for output..."
        }
        return "Loading terminal output..."
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
}

// MARK: - View Model

/// Manages terminal subscription lifecycle, output buffering, and message handler chaining.
/// Uses @Observable instead of @State closures to avoid type inference issues.
@Observable
@MainActor
final class TerminalViewModel {
    var output = ""
    var hasError = false
    private(set) var isSubscribed = false

    private static let maxOutputLength = 50_000
    private var subscriptionID: UUID?

    func subscribe(agentId: String, appState: AppState) async {
        guard !isSubscribed else { return }
        isSubscribed = true

        // Fetch initial log content via REST
        if let client = appState.client {
            do {
                let logs = try await client.fetchLogs(agentId: agentId, lines: 200)
                output = logs.output
                trimOutput()
            } catch {
                output = "Failed to load logs: \(error.localizedDescription)"
                hasError = true
            }
        }

        // Subscribe to live WebSocket updates
        let wsManager = appState.wsManager
        subscriptionID = TerminalMessageRouter.shared.addSubscriber(wsManager: wsManager) { [weak self] message in
            guard message.type == "terminal:output", message.agentId == agentId, let data = message.data else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.output += data
                self.trimOutput()
            }
        }
        wsManager.subscribeTerminal(agentId: agentId)
    }

    func unsubscribe(agentId: String, wsManager: WebSocketManager) {
        guard isSubscribed else { return }
        isSubscribed = false
        wsManager.unsubscribeTerminal(agentId: agentId)
        if let subscriptionID {
            TerminalMessageRouter.shared.removeSubscriber(wsManager: wsManager, subscriberID: subscriptionID)
            self.subscriptionID = nil
        }
    }

    /// Keep output within bounds, trimming at a newline boundary when possible.
    private func trimOutput() {
        guard output.count > Self.maxOutputLength else { return }
        let startIndex = output.index(output.endIndex, offsetBy: -Self.maxOutputLength)
        if let newlineIndex = output[startIndex...].firstIndex(of: "\n") {
            output = String(output[output.index(after: newlineIndex)...])
        } else {
            output = String(output[startIndex...])
        }
    }
}

private struct TerminalRouterState {
    var previousOnMessage: ((ServerMessage) -> Void)?
    var subscribers: [UUID: (ServerMessage) -> Void]
}

/// Multiplexes WebSocket messages so multiple terminal views can subscribe safely.
private final class TerminalMessageRouter {
    static let shared = TerminalMessageRouter()

    private let lock = NSLock()
    private var states: [ObjectIdentifier: TerminalRouterState] = [:]

    private init() {}

    func addSubscriber(
        wsManager: WebSocketManager,
        subscriber: @escaping (ServerMessage) -> Void
    ) -> UUID {
        let managerID = ObjectIdentifier(wsManager)
        let subscriberID = UUID()

        lock.lock()
        if states[managerID] == nil {
            let previousOnMessage = wsManager.onMessage
            states[managerID] = TerminalRouterState(previousOnMessage: previousOnMessage, subscribers: [:])
            wsManager.onMessage = { [weak self] message in
                self?.dispatch(message: message, managerID: managerID)
            }
        }
        states[managerID]?.subscribers[subscriberID] = subscriber
        lock.unlock()

        return subscriberID
    }

    func removeSubscriber(wsManager: WebSocketManager, subscriberID: UUID) {
        let managerID = ObjectIdentifier(wsManager)

        lock.lock()
        guard var state = states[managerID] else {
            lock.unlock()
            return
        }

        state.subscribers.removeValue(forKey: subscriberID)
        if state.subscribers.isEmpty {
            states.removeValue(forKey: managerID)
            lock.unlock()
            wsManager.onMessage = state.previousOnMessage
            return
        }

        states[managerID] = state
        lock.unlock()
    }

    private func dispatch(message: ServerMessage, managerID: ObjectIdentifier) {
        lock.lock()
        let state = states[managerID]
        let subscribers = state?.subscribers.values.map { $0 } ?? []
        lock.unlock()

        state?.previousOnMessage?(message)
        for subscriber in subscribers {
            subscriber(message)
        }
    }
}
