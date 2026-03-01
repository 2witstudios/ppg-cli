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
    var name: String
    var host: String
    var port: Int
    var caCertificate: String?

    init(from connection: ServerConnection) {
        self.id = connection.id
        self.name = connection.name
        self.host = connection.host
        self.port = connection.port
        self.caCertificate = connection.caCertificate
    }

    func toServerConnection(token: String) -> ServerConnection {
        ServerConnection(
            id: id,
            name: name,
            host: host,
            port: port,
            token: token,
            caCertificate: caCertificate
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

    // MARK: - Connection Status (for Settings UI)

    var connectionStatus: ConnectionState {
        if isConnecting { return .connecting }
        if let error = errorMessage { return .error(error) }
        if activeConnection != nil { return .connected }
        return .disconnected
    }

    // MARK: - Dependencies

    let client = PPGClient()
    let manifestStore: ManifestStore
    private(set) var wsManager: WebSocketManager?

    private let tokenStorage = TokenStorage()

    // MARK: - Computed

    var manifest: Manifest? { manifestStore.manifest }
    var templates: [String] { [] }

    // MARK: - Init

    init() {
        self.manifestStore = ManifestStore(client: client)
        loadConnections()
    }

    // MARK: - Auto-Connect

    /// Connects to the last-used server if one exists.
    func autoConnect() async {
        guard let lastId = UserDefaults.standard.string(forKey: DefaultsKey.lastConnectionId),
              let uuid = UUID(uuidString: lastId),
              let connection = connections.first(where: { $0.id == uuid }) else {
            return
        }
        await connect(to: connection)
    }

    // MARK: - Connect / Disconnect

    func connect(to connection: ServerConnection) async {
        guard !isConnecting else { return }

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

    func disconnect() {
        stopWebSocket()
        activeConnection = nil
        manifestStore.clear()
        webSocketState = .disconnected
    }

    // MARK: - Agent Actions

    func killAgent(_ agentId: String) async {
        do {
            try await client.killAgent(agentId: agentId)
            await manifestStore.refresh()
        } catch {
            errorMessage = "Failed to kill agent: \(error.localizedDescription)"
        }
    }

    // MARK: - Connection CRUD

    func addConnection(_ connection: ServerConnection) {
        // Remove duplicate host:port
        if let existing = connections.first(where: { $0.host == connection.host && $0.port == connection.port }),
           existing.id != connection.id {
            try? tokenStorage.delete(for: existing.id)
        }

        if let index = connections.firstIndex(where: { $0.host == connection.host && $0.port == connection.port }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        saveConnections()
    }

    func addConnectionAndConnect(_ connection: ServerConnection) async {
        addConnection(connection)
        await connect(to: connection)
    }

    func removeConnection(_ connection: ServerConnection) {
        if activeConnection?.id == connection.id {
            disconnect()
        }
        connections.removeAll { $0.id == connection.id }
        try? tokenStorage.delete(for: connection.id)
        saveConnections()

        if let lastId = UserDefaults.standard.string(forKey: DefaultsKey.lastConnectionId),
           lastId == connection.id.uuidString {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.lastConnectionId)
        }
    }

    func updateConnection(_ connection: ServerConnection) async {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        connections[index] = connection
        saveConnections()

        if activeConnection?.id == connection.id {
            await connect(to: connection)
        }
    }

    // MARK: - Error Handling

    func clearError() {
        errorMessage = nil
    }

    // MARK: - WebSocket Lifecycle

    private func startWebSocket(for connection: ServerConnection) {
        stopWebSocket()

        guard let wsURL = connection.webSocketURL else { return }
        let ws = WebSocketManager(url: wsURL)
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
        wsManager = ws
        ws.connect()
    }

    private func stopWebSocket() {
        wsManager?.disconnect()
        wsManager = nil
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
                let token = try tokenStorage.load(for: entry.id)
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
        let persisted = connections.map { PersistedConnection(from: $0) }
        do {
            let data = try JSONEncoder().encode(persisted)
            UserDefaults.standard.set(data, forKey: DefaultsKey.savedConnections)
        } catch {
            errorMessage = "Failed to save connections."
            return
        }

        var failedTokenSave = false
        for connection in connections {
            do {
                try tokenStorage.save(token: connection.token, for: connection.id)
            } catch {
                failedTokenSave = true
            }
        }

        if failedTokenSave {
            errorMessage = "Some connection tokens could not be saved."
        }
    }
}
