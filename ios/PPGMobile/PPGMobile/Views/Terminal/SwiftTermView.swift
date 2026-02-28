import SwiftUI
import SwiftTerm

/// UIViewRepresentable wrapping SwiftTerm's iOS `TerminalView` for VT100 rendering.
/// Data comes from WebSocket terminal streaming, not a local process.
struct SwiftTermView: UIViewRepresentable {
    let agentId: String
    @Environment(AppState.self) private var appState

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let tv = SwiftTerm.TerminalView(frame: .zero)
        tv.nativeBackgroundColor = UIColor(
            red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0
        )
        tv.nativeForegroundColor = UIColor(
            red: 0.85, green: 0.85, blue: 0.87, alpha: 1.0
        )
        tv.installColors(GlassTheme.ansiPalette())
        tv.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.terminalDelegate = context.coordinator
        context.coordinator.terminalView = tv
        context.coordinator.setup(agentId: agentId, appState: appState)

        // Trigger keyboard after SwiftUI lays out the view.
        // SwiftTerm's built-in accessory bar provides Esc, Ctrl, Tab, arrows, etc.
        // Scroll to bottom first so the cursor/typing area is visible when keyboard appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            tv.scroll(toPosition: 1.0)
            tv.becomeFirstResponder()
        }

        return tv
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleUIView(_ uiView: SwiftTerm.TerminalView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, TerminalViewDelegate {
        weak var terminalView: SwiftTerm.TerminalView?
        private var subscriptionID: UUID?
        // Set once in setup(), read from delegate callbacks — safe for nonisolated access.
        nonisolated(unsafe) private var agentId: String?
        nonisolated(unsafe) private weak var appState: AppState?

        func setup(agentId: String, appState: AppState) {
            self.agentId = agentId
            self.appState = appState

            Task { @MainActor in
                // Fetch initial logs and feed into terminal
                do {
                    let logs = try await appState.client.fetchAgentLogs(agentId: agentId, lines: 200)
                    if let bytes = logs.output.data(using: .utf8) {
                        self.terminalView?.feed(byteArray: ArraySlice(bytes))
                    }
                } catch {
                    let msg = "Failed to load logs: \(error.localizedDescription)\r\n"
                    if let bytes = msg.data(using: .utf8) {
                        self.terminalView?.feed(byteArray: ArraySlice(bytes))
                    }
                }

                // Scroll to bottom so the latest output is visible
                self.terminalView?.scroll(toPosition: 1.0)

                // Subscribe to live WebSocket updates
                guard let ws = appState.wsManager else { return }
                self.subscriptionID = TerminalMessageRouter.shared.addSubscriber(wsManager: ws) { [weak self] message in
                    guard message.type == "terminal:output",
                          message.agentId == agentId,
                          let data = message.data else { return }
                    Task { @MainActor [weak self] in
                        if let bytes = data.data(using: .utf8) {
                            self?.terminalView?.feed(byteArray: ArraySlice(bytes))
                        }
                    }
                }
                ws.subscribeTerminal(agentId: agentId)
            }
        }

        func teardown() {
            guard let agentId, let appState else { return }
            let subId = subscriptionID
            subscriptionID = nil
            MainActor.assumeIsolated {
                if let ws = appState.wsManager {
                    ws.unsubscribeTerminal(agentId: agentId)
                    if let subId {
                        TerminalMessageRouter.shared.removeSubscriber(wsManager: ws, subscriberID: subId)
                    }
                }
            }
        }

        // MARK: - TerminalViewDelegate

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            let text = String(bytes: data, encoding: .utf8) ?? ""
            guard let agentId, let appState else { return }
            Task { @MainActor in
                appState.wsManager?.sendTerminalInput(agentId: agentId, text: text)
            }
        }

        func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            guard let agentId, let appState else { return }
            Task { @MainActor in
                appState.wsManager?.sendTerminalResize(agentId: agentId, cols: newCols, rows: newRows)
            }
        }
        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {}
        func bell(source: SwiftTerm.TerminalView) {}
        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            UIPasteboard.general.setData(content, forPasteboardType: "public.utf8-plain-text")
        }
        func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
    }
}
