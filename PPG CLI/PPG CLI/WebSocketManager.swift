import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let webSocketStateDidChange = Notification.Name("PPGWebSocketStateDidChange")
    static let webSocketDidReceiveEvent = Notification.Name("PPGWebSocketDidReceiveEvent")
}

// MARK: - Connection State

enum WebSocketConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)

    var isConnected: Bool { self == .connected }
}

// MARK: - Server Events

enum WebSocketEvent: Sendable {
    case manifestUpdated(ManifestModel)
    case agentStatusChanged(agentId: String, status: AgentStatus)
    case worktreeStatusChanged(worktreeId: String, status: String)
    case pong
    case unknown(type: String, payload: String)
}

// MARK: - Client Commands

enum WebSocketCommand {
    case subscribe(channel: String)
    case unsubscribe(channel: String)
    case terminalInput(agentId: String, data: String)

    var jsonString: String {
        switch self {
        case .subscribe(let channel):
            return #"{"type":"subscribe","channel":"\#(channel)"}"#
        case .unsubscribe(let channel):
            return #"{"type":"unsubscribe","channel":"\#(channel)"}"#
        case .terminalInput(let agentId, let data):
            let escaped = data
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            return #"{"type":"terminal_input","agentId":"\#(agentId)","data":"\#(escaped)"}"#
        }
    }
}

// MARK: - WebSocketManager

nonisolated class WebSocketManager: NSObject, @unchecked Sendable, URLSessionWebSocketDelegate {

    /// Notification userInfo key for connection state.
    static let stateUserInfoKey = "PPGWebSocketState"
    /// Notification userInfo key for received event.
    static let eventUserInfoKey = "PPGWebSocketEvent"

    // MARK: - Configuration

    private let url: URL
    private let maxReconnectDelay: TimeInterval = 30.0
    private let baseReconnectDelay: TimeInterval = 1.0
    private let pingInterval: TimeInterval = 30.0

    // MARK: - State

    private let queue = DispatchQueue(label: "ppg.websocket-manager", qos: .utility)
    private(set) var state: WebSocketConnectionState = .disconnected {
        didSet {
            guard state != oldValue else { return }
            let newState = state
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .webSocketStateDidChange,
                    object: nil,
                    userInfo: [WebSocketManager.stateUserInfoKey: newState]
                )
            }
        }
    }

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var pingTimer: DispatchSourceTimer?
    private var reconnectAttempt = 0
    private var intentionalDisconnect = false

    // MARK: - Callbacks (alternative to NotificationCenter)

    var onStateChange: ((WebSocketConnectionState) -> Void)?
    var onEvent: ((WebSocketEvent) -> Void)?

    // MARK: - Init

    init(url: URL) {
        self.url = url
        super.init()
    }

    convenience init?(urlString: String) {
        guard let url = URL(string: urlString) else { return nil }
        self.init(url: url)
    }

    deinit {
        disconnect()
    }

    // MARK: - Public API

    func connect() {
        queue.async { [weak self] in
            self?.doConnect()
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            self?.doDisconnect()
        }
    }

    func send(_ command: WebSocketCommand) {
        queue.async { [weak self] in
            self?.doSend(command.jsonString)
        }
    }

    // MARK: - Connection Lifecycle

    private func doConnect() {
        guard state == .disconnected || state != .connecting else { return }

        intentionalDisconnect = false

        if case .reconnecting = state {
            // Already in reconnect flow — keep the attempt counter
        } else {
            reconnectAttempt = 0
            state = .connecting
        }

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        let wsTask = session!.webSocketTask(with: url)
        task = wsTask
        wsTask.resume()
    }

    private func doDisconnect() {
        intentionalDisconnect = true
        stopPingTimer()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        reconnectAttempt = 0
        state = .disconnected
    }

    // MARK: - Sending

    private func doSend(_ text: String) {
        guard state == .connected, let task = task else { return }
        task.send(.string(text)) { error in
            if let error = error {
                NSLog("[WebSocketManager] send error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Receiving

    private func listenForMessages() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.listenForMessages()
            case .failure(let error):
                if !self.intentionalDisconnect {
                    NSLog("[WebSocketManager] receive error: \(error.localizedDescription)")
                    self.queue.async { self.handleConnectionLost() }
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let s):
            text = s
        case .data(let d):
            guard let s = String(data: d, encoding: .utf8) else { return }
            text = s
        @unknown default:
            return
        }

        guard let event = parseEvent(text) else { return }

        // Notify via callback
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
            NotificationCenter.default.post(
                name: .webSocketDidReceiveEvent,
                object: nil,
                userInfo: [WebSocketManager.eventUserInfoKey: event]
            )
        }
    }

    // MARK: - Event Parsing

    private func parseEvent(_ text: String) -> WebSocketEvent? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        switch type {
        case "manifest_updated":
            if let payloadData = json["manifest"],
               let payloadJSON = try? JSONSerialization.data(withJSONObject: payloadData),
               let manifest = try? JSONDecoder().decode(ManifestModel.self, from: payloadJSON) {
                return .manifestUpdated(manifest)
            }
            return .unknown(type: type, payload: text)

        case "agent_status_changed":
            if let agentId = json["agentId"] as? String,
               let statusRaw = json["status"] as? String,
               let status = AgentStatus(rawValue: statusRaw) {
                return .agentStatusChanged(agentId: agentId, status: status)
            }
            return .unknown(type: type, payload: text)

        case "worktree_status_changed":
            if let worktreeId = json["worktreeId"] as? String,
               let status = json["status"] as? String {
                return .worktreeStatusChanged(worktreeId: worktreeId, status: status)
            }
            return .unknown(type: type, payload: text)

        case "pong":
            return .pong

        default:
            return .unknown(type: type, payload: text)
        }
    }

    // MARK: - Keepalive Ping

    private func startPingTimer() {
        stopPingTimer()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
        timer.setEventHandler { [weak self] in
            self?.sendPing()
        }
        timer.resume()
        pingTimer = timer
    }

    private func stopPingTimer() {
        pingTimer?.cancel()
        pingTimer = nil
    }

    private func sendPing() {
        task?.sendPing { [weak self] error in
            if let error = error {
                NSLog("[WebSocketManager] ping error: \(error.localizedDescription)")
                self?.queue.async { self?.handleConnectionLost() }
            }
        }
    }

    // MARK: - Reconnect

    private func handleConnectionLost() {
        guard !intentionalDisconnect else { return }
        stopPingTimer()
        task?.cancel(with: .abnormalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectAttempt += 1
        state = .reconnecting(attempt: reconnectAttempt)

        let delay = min(baseReconnectDelay * pow(2.0, Double(reconnectAttempt - 1)), maxReconnectDelay)
        NSLog("[WebSocketManager] reconnecting in %.1fs (attempt %d)", delay, reconnectAttempt)

        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.intentionalDisconnect else { return }
            self.doConnect()
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.reconnectAttempt = 0
            self.state = .connected
            self.startPingTimer()
            self.listenForMessages()
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.intentionalDisconnect {
                self.state = .disconnected
            } else {
                self.handleConnectionLost()
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard error != nil else { return }
        queue.async { [weak self] in
            guard let self = self, !self.intentionalDisconnect else { return }
            self.handleConnectionLost()
        }
    }
}
