import Foundation

// MARK: - Connection State

enum WebSocketConnectionState: Equatable, Sendable {
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

enum WebSocketEvent: Sendable {
    case manifestUpdated(Manifest)
    case agentStatusChanged(agentId: String, status: AgentStatus)
    case worktreeStatusChanged(worktreeId: String, status: String)
    case pong
    case unknown(type: String, payload: String)
}

// MARK: - Server Message (for terminal streaming)

struct ServerMessage {
    let type: String
    let agentId: String?
    let data: String?
}

// MARK: - WebSocketManager

final class WebSocketManager: NSObject, @unchecked Sendable, URLSessionWebSocketDelegate {

    // MARK: - Callbacks

    var onStateChange: ((WebSocketConnectionState) -> Void)?
    var onEvent: ((WebSocketEvent) -> Void)?
    var onMessage: ((ServerMessage) -> Void)?

    // MARK: - Configuration

    private let url: URL
    private let maxReconnectDelay: TimeInterval = 30.0
    private let baseReconnectDelay: TimeInterval = 1.0
    private let pingInterval: TimeInterval = 30.0

    // MARK: - State

    private let queue = DispatchQueue(label: "ppg.websocket-manager", qos: .utility)
    private var _state: WebSocketConnectionState = .disconnected

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

    func sendTerminalInput(agentId: String, text: String) {
        let dict: [String: String] = ["type": "terminal_input", "agentId": agentId, "data": text]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return }
        queue.async { [weak self] in
            self?.doSend(str)
        }
    }

    func subscribeTerminal(agentId: String) {
        let dict: [String: String] = ["type": "subscribe", "channel": "terminal:\(agentId)"]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return }
        queue.async { [weak self] in
            self?.doSend(str)
        }
    }

    func unsubscribeTerminal(agentId: String) {
        let dict: [String: String] = ["type": "unsubscribe", "channel": "terminal:\(agentId)"]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return }
        queue.async { [weak self] in
            self?.doSend(str)
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
            // Keep attempt counter
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

    private func setState(_ newState: WebSocketConnectionState) {
        guard _state != newState else { return }
        _state = newState
        let callback = onStateChange
        DispatchQueue.main.async {
            callback?(newState)
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

        // Parse as generic ServerMessage for terminal streaming
        if let serverMsg = parseServerMessage(text) {
            let callback = onMessage
            DispatchQueue.main.async {
                callback?(serverMsg)
            }
        }

        // Parse as typed event
        if let event = parseEvent(text) {
            let callback = onEvent
            DispatchQueue.main.async {
                callback?(event)
            }
        }
    }

    // MARK: - Event Parsing

    private func parseServerMessage(_ text: String) -> ServerMessage? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }
        return ServerMessage(
            type: type,
            agentId: json["agentId"] as? String,
            data: json["data"] as? String
        )
    }

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
               let manifest = try? JSONDecoder().decode(Manifest.self, from: payloadJSON) {
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
