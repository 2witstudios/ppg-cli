import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let webSocketStateDidChange = Notification.Name("PPGWebSocketStateDidChange")
    static let webSocketDidReceiveEvent = Notification.Name("PPGWebSocketDidReceiveEvent")
}

// MARK: - Connection State

nonisolated enum WebSocketConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)

    var isConnected: Bool { self == .connected }

    var isReconnecting: Bool {
        if case .reconnecting = self { return true }
        return false
    }
}

// MARK: - Server Events

nonisolated enum WebSocketEvent: Sendable {
    case manifestUpdated(ManifestModel)
    case agentStatusChanged(agentId: String, status: AgentStatus)
    case worktreeStatusChanged(worktreeId: String, status: String)
    case pong
    case unknown(type: String, payload: String)
}

// MARK: - Client Commands

nonisolated enum WebSocketCommand: Sendable {
    case subscribe(channel: String)
    case unsubscribe(channel: String)
    case terminalInput(agentId: String, data: String)

    var jsonString: String {
        let dict: [String: String]
        switch self {
        case .subscribe(let channel):
            dict = ["type": "subscribe", "channel": channel]
        case .unsubscribe(let channel):
            dict = ["type": "unsubscribe", "channel": channel]
        case .terminalInput(let agentId, let data):
            dict = ["type": "terminal_input", "agentId": agentId, "data": data]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
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

    /// Internal state — only read/write on `queue`.
    private var _state: WebSocketConnectionState = .disconnected

    /// Thread-safe read of the current connection state.
    var state: WebSocketConnectionState {
        queue.sync { _state }
    }

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var pingTimer: DispatchSourceTimer?
    private var reconnectWorkItem: DispatchWorkItem?
    private var reconnectAttempt = 0
    private var intentionalDisconnect = false
    private var isHandlingConnectionLoss = false

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
        // Synchronous cleanup — safe because we're the last reference holder.
        intentionalDisconnect = true
        pingTimer?.cancel()
        pingTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
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
        guard _state == .disconnected || _state.isReconnecting else { return }

        intentionalDisconnect = false
        isHandlingConnectionLoss = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

        if _state.isReconnecting {
            // Already in reconnect flow — keep the attempt counter
        } else {
            reconnectAttempt = 0
            setState(.connecting)
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
        isHandlingConnectionLoss = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        stopPingTimer()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        reconnectAttempt = 0
        setState(.disconnected)
    }

    /// Set state on the queue and post a notification on main.
    private func setState(_ newState: WebSocketConnectionState) {
        guard _state != newState else { return }
        _state = newState
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .webSocketStateDidChange,
                object: nil,
                userInfo: [WebSocketManager.stateUserInfoKey: newState]
            )
        }
    }

    // MARK: - Sending

    private func doSend(_ text: String) {
        guard _state == .connected, let task = task else { return }
        task.send(.string(text)) { error in
            if let error = error {
                NSLog("[WebSocketManager] send error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Receiving

    private func listenForMessages(for expectedTask: URLSessionWebSocketTask) {
        expectedTask.receive { [weak self] result in
            guard let self = self else { return }
            self.queue.async {
                guard self.task === expectedTask else { return }
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.listenForMessages(for: expectedTask)
                case .failure(let error):
                    if !self.intentionalDisconnect {
                        NSLog("[WebSocketManager] receive error: \(error.localizedDescription)")
                        self.handleConnectionLost()
                    }
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

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .webSocketDidReceiveEvent,
                object: nil,
                userInfo: [WebSocketManager.eventUserInfoKey: event]
            )
        }
    }

    // MARK: - Event Parsing

    /// Parse a JSON text message into a typed event. Internal for testability.
    func parseEvent(_ text: String) -> WebSocketEvent? {
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
        guard !isHandlingConnectionLoss else { return }
        isHandlingConnectionLoss = true
        stopPingTimer()
        task?.cancel(with: .abnormalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectAttempt += 1
        setState(.reconnecting(attempt: reconnectAttempt))

        let delay = min(baseReconnectDelay * pow(2.0, Double(reconnectAttempt - 1)), maxReconnectDelay)
        NSLog("[WebSocketManager] reconnecting in %.1fs (attempt %d)", delay, reconnectAttempt)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, !self.intentionalDisconnect else { return }
            self.reconnectWorkItem = nil
            self.doConnect()
        }
        reconnectWorkItem?.cancel()
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.task === webSocketTask else { return }
            self.reconnectAttempt = 0
            self.isHandlingConnectionLoss = false
            self.setState(.connected)
            self.startPingTimer()
            self.listenForMessages(for: webSocketTask)
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.task === webSocketTask else { return }
            if self.intentionalDisconnect {
                self.setState(.disconnected)
            } else {
                self.handleConnectionLost()
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard error != nil else { return }
        queue.async { [weak self] in
            guard let self = self, !self.intentionalDisconnect else { return }
            guard let webSocketTask = task as? URLSessionWebSocketTask,
                  self.task === webSocketTask else { return }
            self.handleConnectionLost()
        }
    }
}
