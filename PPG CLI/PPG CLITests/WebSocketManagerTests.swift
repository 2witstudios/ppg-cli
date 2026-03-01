import XCTest
@testable import PPG_CLI

final class WebSocketManagerTests: XCTestCase {

    // MARK: - WebSocketConnectionState

    func testIsConnectedReturnsTrueOnlyWhenConnected() {
        XCTAssertTrue(WebSocketConnectionState.connected.isConnected)
        XCTAssertFalse(WebSocketConnectionState.disconnected.isConnected)
        XCTAssertFalse(WebSocketConnectionState.connecting.isConnected)
        XCTAssertFalse(WebSocketConnectionState.reconnecting(attempt: 1).isConnected)
    }

    func testIsReconnectingReturnsTrueOnlyWhenReconnecting() {
        XCTAssertTrue(WebSocketConnectionState.reconnecting(attempt: 1).isReconnecting)
        XCTAssertTrue(WebSocketConnectionState.reconnecting(attempt: 5).isReconnecting)
        XCTAssertFalse(WebSocketConnectionState.connected.isReconnecting)
        XCTAssertFalse(WebSocketConnectionState.disconnected.isReconnecting)
        XCTAssertFalse(WebSocketConnectionState.connecting.isReconnecting)
    }

    func testReconnectingEquality() {
        XCTAssertEqual(
            WebSocketConnectionState.reconnecting(attempt: 3),
            WebSocketConnectionState.reconnecting(attempt: 3)
        )
        XCTAssertNotEqual(
            WebSocketConnectionState.reconnecting(attempt: 1),
            WebSocketConnectionState.reconnecting(attempt: 2)
        )
    }

    // MARK: - WebSocketCommand.jsonString

    func testSubscribeCommandProducesValidJSON() {
        let cmd = WebSocketCommand.subscribe(channel: "manifest")
        let json = parseJSON(cmd.jsonString)
        XCTAssertEqual(json?["type"] as? String, "subscribe")
        XCTAssertEqual(json?["channel"] as? String, "manifest")
    }

    func testUnsubscribeCommandProducesValidJSON() {
        let cmd = WebSocketCommand.unsubscribe(channel: "agents")
        let json = parseJSON(cmd.jsonString)
        XCTAssertEqual(json?["type"] as? String, "unsubscribe")
        XCTAssertEqual(json?["channel"] as? String, "agents")
    }

    func testTerminalInputCommandProducesValidJSON() {
        let cmd = WebSocketCommand.terminalInput(agentId: "ag-12345678", data: "ls -la\n")
        let json = parseJSON(cmd.jsonString)
        XCTAssertEqual(json?["type"] as? String, "terminal_input")
        XCTAssertEqual(json?["agentId"] as? String, "ag-12345678")
        XCTAssertEqual(json?["data"] as? String, "ls -la\n")
    }

    func testCommandEscapesSpecialCharactersInChannel() {
        // A channel name with quotes should not break JSON structure
        let cmd = WebSocketCommand.subscribe(channel: #"test"channel"#)
        let json = parseJSON(cmd.jsonString)
        XCTAssertEqual(json?["channel"] as? String, #"test"channel"#)
    }

    func testCommandEscapesSpecialCharactersInAgentId() {
        let cmd = WebSocketCommand.terminalInput(agentId: #"id"with"quotes"#, data: "x")
        let json = parseJSON(cmd.jsonString)
        XCTAssertEqual(json?["agentId"] as? String, #"id"with"quotes"#)
    }

    func testTerminalInputPreservesControlCharacters() {
        let cmd = WebSocketCommand.terminalInput(agentId: "ag-1", data: "line1\nline2\ttab\r")
        let json = parseJSON(cmd.jsonString)
        XCTAssertEqual(json?["data"] as? String, "line1\nline2\ttab\r")
    }

    // MARK: - parseEvent

    func testParseAgentStatusChangedEvent() {
        let manager = WebSocketManager(url: URL(string: "ws://localhost")!)
        let json = #"{"type":"agent_status_changed","agentId":"ag-abc","status":"completed"}"#
        let event = manager.parseEvent(json)

        if case .agentStatusChanged(let agentId, let status) = event {
            XCTAssertEqual(agentId, "ag-abc")
            XCTAssertEqual(status, .completed)
        } else {
            XCTFail("Expected agentStatusChanged, got \(String(describing: event))")
        }
    }

    func testParseWorktreeStatusChangedEvent() {
        let manager = WebSocketManager(url: URL(string: "ws://localhost")!)
        let json = #"{"type":"worktree_status_changed","worktreeId":"wt-xyz","status":"active"}"#
        let event = manager.parseEvent(json)

        if case .worktreeStatusChanged(let worktreeId, let status) = event {
            XCTAssertEqual(worktreeId, "wt-xyz")
            XCTAssertEqual(status, "active")
        } else {
            XCTFail("Expected worktreeStatusChanged, got \(String(describing: event))")
        }
    }

    func testParsePongEvent() {
        let manager = WebSocketManager(url: URL(string: "ws://localhost")!)
        let event = manager.parseEvent(#"{"type":"pong"}"#)

        if case .pong = event {
            // pass
        } else {
            XCTFail("Expected pong, got \(String(describing: event))")
        }
    }

    func testParseUnknownEventType() {
        let manager = WebSocketManager(url: URL(string: "ws://localhost")!)
        let json = #"{"type":"custom_event","foo":"bar"}"#
        let event = manager.parseEvent(json)

        if case .unknown(let type, let payload) = event {
            XCTAssertEqual(type, "custom_event")
            XCTAssertEqual(payload, json)
        } else {
            XCTFail("Expected unknown, got \(String(describing: event))")
        }
    }

    func testParseManifestUpdatedEvent() {
        let manager = WebSocketManager(url: URL(string: "ws://localhost")!)
        let json = """
        {"type":"manifest_updated","manifest":{"version":1,"projectRoot":"/tmp","sessionName":"s","worktrees":{},"createdAt":"t","updatedAt":"t"}}
        """
        let event = manager.parseEvent(json)

        if case .manifestUpdated(let manifest) = event {
            XCTAssertEqual(manifest.version, 1)
            XCTAssertEqual(manifest.projectRoot, "/tmp")
            XCTAssertEqual(manifest.sessionName, "s")
        } else {
            XCTFail("Expected manifestUpdated, got \(String(describing: event))")
        }
    }

    func testParseManifestUpdatedWithInvalidManifestFallsBackToUnknown() {
        let manager = WebSocketManager(url: URL(string: "ws://localhost")!)
        let json = #"{"type":"manifest_updated","manifest":{"bad":"data"}}"#
        let event = manager.parseEvent(json)

        if case .unknown(let type, _) = event {
            XCTAssertEqual(type, "manifest_updated")
        } else {
            XCTFail("Expected unknown fallback, got \(String(describing: event))")
        }
    }

    func testParseReturnsNilForInvalidJSON() {
        let manager = WebSocketManager(url: URL(string: "ws://localhost")!)
        XCTAssertNil(manager.parseEvent("not json"))
    }

    func testParseReturnsNilForMissingType() {
        let manager = WebSocketManager(url: URL(string: "ws://localhost")!)
        XCTAssertNil(manager.parseEvent(#"{"channel":"test"}"#))
    }

    func testParseAgentStatusWithInvalidStatusFallsBackToUnknown() {
        let manager = WebSocketManager(url: URL(string: "ws://localhost")!)
        let json = #"{"type":"agent_status_changed","agentId":"ag-1","status":"bogus"}"#
        let event = manager.parseEvent(json)

        if case .unknown(let type, _) = event {
            XCTAssertEqual(type, "agent_status_changed")
        } else {
            XCTFail("Expected unknown fallback for invalid status, got \(String(describing: event))")
        }
    }

    func testParseAgentStatusWithMissingFieldsFallsBackToUnknown() {
        let manager = WebSocketManager(url: URL(string: "ws://localhost")!)
        let json = #"{"type":"agent_status_changed","agentId":"ag-1"}"#
        let event = manager.parseEvent(json)

        if case .unknown(let type, _) = event {
            XCTAssertEqual(type, "agent_status_changed")
        } else {
            XCTFail("Expected unknown fallback for missing status, got \(String(describing: event))")
        }
    }

    // MARK: - Initial State

    func testInitialStateIsDisconnected() {
        let manager = WebSocketManager(url: URL(string: "ws://localhost")!)
        XCTAssertEqual(manager.state, .disconnected)
    }

    func testConvenienceInitReturnsNilForEmptyString() {
        XCTAssertNil(WebSocketManager(urlString: ""))
    }

    func testConvenienceInitSucceedsForValidURL() {
        XCTAssertNotNil(WebSocketManager(urlString: "ws://localhost:8080"))
    }

    // MARK: - Helpers

    private func parseJSON(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
