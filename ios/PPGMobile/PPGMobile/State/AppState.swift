import Foundation

// MARK: - UserDefaults Keys

private enum DefaultsKey {
    static let savedConnections = "ppg_saved_connections"
    static let lastConnectionId = "ppg_last_connection_id"
}

// MARK: - AppState

/// Root application state managing server connections and the REST/WS lifecycle.
///
/// `AppState` is the single entry point for connection management. It persists
/// connections to `UserDefaults`, auto-connects to the last-used server on
/// launch, and coordinates `PPGClient` (REST) and `WebSocketManager` (WS)
/// through `ManifestStore`.
@Observable
final class AppState {

    // MARK: - Connection State

    /// All saved server connections.
    private(set) var connections: [ServerConnection] = []

    /// The currently active connection, or `nil` if disconnected.
    private(set) var activeConnection: ServerConnection?

    /// Whether a connection attempt is in progress.
    private(set) var isConnecting = false

    /// User-facing error message, cleared on next successful action.
    private(set) var errorMessage: String?

    // MARK: - WebSocket State

    /// Current WebSocket connection state.
    private(set) var webSocketState: WebSocketConnectionState = .disconnected

    // MARK: - Dependencies

    let client = PPGClient()
    let manifestStore: ManifestStore
    private var webSocket: WebSocketManager?

    // MARK: - Init

    init() {
        self.manifestStore = ManifestStore(client: client)
        loadConnections()
    }

    // MARK: - Auto-Connect

    /// Connects to the last-used server if one exists.
    /// Call this from the app's `.task` modifier on launch.
    @MainActor
    func autoConnect() async {
        guard let lastId = UserDefaults.standard.string(forKey: DefaultsKey.lastConnectionId),
              let uuid = UUID(uuidString: lastId),
              let connection = connections.first(where: { $0.id == uuid }) else {
            return
        }
        await connect(to: connection)
    }

    // MARK: - Connect / Disconnect

    /// Connects to the given server: configures REST client, tests reachability,
    /// starts WebSocket, and fetches the initial manifest.
    @MainActor
    func connect(to connection: ServerConnection) async {
        // Disconnect current connection first
        if activeConnection != nil {
            disconnect()
        }

        isConnecting = true
        errorMessage = nil

        await client.configure(connection: connection)

        do {
            try await client.testConnection()
        } catch {
            isConnecting = false
            errorMessage = "Cannot reach server: \(error.localizedDescription)"
            return
        }

        activeConnection = connection
        UserDefaults.standard.set(connection.id.uuidString, forKey: DefaultsKey.lastConnectionId)

        // Start WebSocket
        startWebSocket(for: connection)

        // Fetch initial manifest
        await manifestStore.refresh()

        isConnecting = false
    }

    /// Disconnects from the current server, tearing down WS and clearing state.
    @MainActor
    func disconnect() {
        stopWebSocket()
        activeConnection = nil
        manifestStore.clear()
        webSocketState = .disconnected
        errorMessage = nil
    }

    // MARK: - Connection CRUD

    /// Adds a new connection, persists it, and optionally connects to it.
    @MainActor
    func addConnection(_ connection: ServerConnection, connectImmediately: Bool = true) async {
        // Avoid duplicates by host+port
        if let existing = connections.firstIndex(where: { $0.host == connection.host && $0.port == connection.port }) {
            connections[existing] = connection
        } else {
            connections.append(connection)
        }
        saveConnections()

        if connectImmediately {
            await connect(to: connection)
        }
    }

    /// Removes a saved connection. Disconnects first if it's the active one.
    @MainActor
    func removeConnection(_ connection: ServerConnection) {
        if activeConnection?.id == connection.id {
            disconnect()
        }
        connections.removeAll { $0.id == connection.id }
        saveConnections()

        // Clear last-used if it was this connection
        if let lastId = UserDefaults.standard.string(forKey: DefaultsKey.lastConnectionId),
           lastId == connection.id.uuidString {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.lastConnectionId)
        }
    }

    /// Updates an existing connection's properties and re-persists.
    @MainActor
    func updateConnection(_ connection: ServerConnection) {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        connections[index] = connection
        saveConnections()

        // If this is the active connection, reconnect with new settings
        if activeConnection?.id == connection.id {
            Task {
                await connect(to: connection)
            }
        }
    }

    // MARK: - Error Handling

    /// Clears the current error message.
    @MainActor
    func clearError() {
        errorMessage = nil
    }

    // MARK: - WebSocket Lifecycle

    private func startWebSocket(for connection: ServerConnection) {
        stopWebSocket()

        let ws = WebSocketManager(url: connection.webSocketURL)
        ws.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.webSocketState = state
            }
        }
        ws.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleWebSocketEvent(event)
            }
        }
        webSocket = ws
        ws.connect()
    }

    private func stopWebSocket() {
        webSocket?.disconnect()
        webSocket = nil
    }

    @MainActor
    private func handleWebSocketEvent(_ event: WebSocketEvent) {
        switch event {
        case .manifestUpdated(let manifest):
            manifestStore.applyManifest(manifest)

        case .agentStatusChanged(let agentId, let status):
            manifestStore.updateAgentStatus(agentId: agentId, status: status)

        case .worktreeStatusChanged(let worktreeId, let statusRaw):
            if let status = WorktreeStatus(rawValue: statusRaw) {
                manifestStore.updateWorktreeStatus(worktreeId: worktreeId, status: status)
            }

        case .pong:
            break

        case .unknown:
            break
        }
    }

    // MARK: - Persistence (UserDefaults)

    private func loadConnections() {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.savedConnections),
              let decoded = try? JSONDecoder().decode([ServerConnection].self, from: data) else {
            return
        }
        connections = decoded
    }

    private func saveConnections() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        UserDefaults.standard.set(data, forKey: DefaultsKey.savedConnections)
    }
}
