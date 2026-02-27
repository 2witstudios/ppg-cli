import Foundation

// MARK: - UserDefaults Keys

private enum DefaultsKey {
    static let savedConnections = "ppg_saved_connections"
    static let lastConnectionId = "ppg_last_connection_id"
}

/// Codable projection of ServerConnection without the token.
/// Tokens are stored separately in Keychain via TokenStorage.
private struct PersistedConnection: Codable {
    let id: UUID
    var host: String
    var port: Int
    var caCertificate: String?

    init(from connection: ServerConnection) {
        self.id = connection.id
        self.host = connection.host
        self.port = connection.port
        self.caCertificate = connection.caCertificate
    }

    func toServerConnection(token: String) -> ServerConnection {
        ServerConnection(
            id: id,
            host: host,
            port: port,
            caCertificate: caCertificate,
            token: token
        )
    }
}

// MARK: - AppState

/// Root application state managing server connections and the REST/WS lifecycle.
///
/// `AppState` is the single entry point for connection management. It persists
/// connection metadata to `UserDefaults` and tokens to Keychain via `TokenStorage`.
/// Auto-connects to the last-used server on launch and coordinates `PPGClient`
/// (REST) and `WebSocketManager` (WS) through `ManifestStore`.
@MainActor
@Observable
final class AppState {

    // MARK: - Connection State

    /// All saved server connections.
    private(set) var connections: [ServerConnection] = []

    /// The currently active connection, or `nil` if disconnected.
    private(set) var activeConnection: ServerConnection?

    /// Whether a connection attempt is in progress.
    private(set) var isConnecting = false

    /// User-facing error message, cleared on next connect attempt.
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
    func connect(to connection: ServerConnection) async {
        guard !isConnecting else { return }

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

        startWebSocket(for: connection)
        await manifestStore.refresh()

        isConnecting = false
    }

    /// Disconnects from the current server, tearing down WS and clearing state.
    func disconnect() {
        stopWebSocket()
        activeConnection = nil
        manifestStore.clear()
        webSocketState = .disconnected
    }

    // MARK: - Connection CRUD

    /// Adds a new connection, persists it, and optionally connects to it.
    func addConnection(_ connection: ServerConnection, connectImmediately: Bool = true) async {
        // Clean up orphaned Keychain token if replacing a duplicate
        if let existing = connections.first(where: { $0.host == connection.host && $0.port == connection.port }),
           existing.id != connection.id {
            do {
                try TokenStorage.delete(for: existing.id)
            } catch {
                errorMessage = "Failed to remove stale credentials from Keychain."
            }
        }

        if let index = connections.firstIndex(where: { $0.host == connection.host && $0.port == connection.port }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        saveConnections()

        if connectImmediately {
            await connect(to: connection)
        }
    }

    /// Removes a saved connection. Disconnects first if it's the active one.
    func removeConnection(_ connection: ServerConnection) {
        if activeConnection?.id == connection.id {
            disconnect()
        }
        connections.removeAll { $0.id == connection.id }
        do {
            try TokenStorage.delete(for: connection.id)
        } catch {
            errorMessage = "Failed to remove connection credentials from Keychain."
        }
        saveConnections()

        if let lastId = UserDefaults.standard.string(forKey: DefaultsKey.lastConnectionId),
           lastId == connection.id.uuidString {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.lastConnectionId)
        }
    }

    /// Updates an existing connection's properties and re-persists.
    func updateConnection(_ connection: ServerConnection) async {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        connections[index] = connection
        saveConnections()

        if activeConnection?.id == connection.id {
            await connect(to: connection)
        }
    }

    // MARK: - Error Handling

    /// Clears the current error message.
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

    // MARK: - Persistence

    private func loadConnections() {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.savedConnections) else {
            return
        }

        let persisted: [PersistedConnection]
        do {
            persisted = try JSONDecoder().decode([PersistedConnection].self, from: data)
        } catch {
            errorMessage = "Failed to load saved connections."
            return
        }

        var loaded: [ServerConnection] = []
        var failedTokenLoad = false
        for entry in persisted {
            do {
                let token = try TokenStorage.load(for: entry.id)
                loaded.append(entry.toServerConnection(token: token))
            } catch {
                failedTokenLoad = true
            }
        }
        connections = loaded

        if failedTokenLoad {
            errorMessage = "Some saved connection tokens could not be loaded."
        }
    }

    private func saveConnections() {
        // Persist metadata to UserDefaults (no tokens)
        let persisted = connections.map { PersistedConnection(from: $0) }
        do {
            let data = try JSONEncoder().encode(persisted)
            UserDefaults.standard.set(data, forKey: DefaultsKey.savedConnections)
        } catch {
            errorMessage = "Failed to save connections."
            return
        }

        // Persist tokens to Keychain
        var failedTokenSave = false
        for connection in connections {
            do {
                try TokenStorage.save(token: connection.token, for: connection.id)
            } catch {
                failedTokenSave = true
            }
        }

        if failedTokenSave {
            errorMessage = "Some connection tokens could not be saved."
        }
    }
}
