import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var showAddManual = false
    @State private var showQRScanner = false
    @State private var deleteTarget: ServerConnection?
    @State private var testResult: TestResult?

    private enum TestResult: Equatable {
        case testing
        case success
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            List {
                currentConnectionSection
                savedServersSection
                addServerSection
                aboutSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showQRScanner) {
                QRScannerView { result in
                    handleQRScan(result)
                }
            }
            .sheet(isPresented: $showAddManual) {
                AddServerView()
            }
            .confirmationDialog(
                "Delete Server",
                isPresented: .init(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                presenting: deleteTarget
            ) { server in
                Button("Delete \"\(server.name)\"", role: .destructive) {
                    appState.removeConnection(server)
                    deleteTarget = nil
                }
            } message: { server in
                Text("Remove \(server.name) (\(server.host):\(server.port))? This cannot be undone.")
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var currentConnectionSection: some View {
        Section("Current Connection") {
            if let conn = appState.activeConnection {
                HStack {
                    VStack(alignment: .leading) {
                        Text(conn.name)
                            .font(.headline)
                        Text("\(conn.host):\(conn.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    connectionStatusBadge
                }

                testConnectionRow

                Button("Disconnect", role: .destructive) {
                    Task { @MainActor in
                        appState.disconnect()
                    }
                }
            } else {
                Text("Not connected")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var savedServersSection: some View {
        Section("Saved Servers") {
            ForEach(appState.connections) { conn in
                Button {
                    Task { await appState.connect(to: conn) }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(conn.name)
                            Text("\(conn.host):\(conn.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if appState.activeConnection?.id == conn.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) {
                        deleteTarget = conn
                    }
                }
            }

            if appState.connections.isEmpty {
                Text("No saved servers")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var addServerSection: some View {
        Section("Add Server") {
            Button {
                showQRScanner = true
            } label: {
                Label("Scan QR Code", systemImage: "qrcode.viewfinder")
            }

            Button {
                showAddManual = true
            } label: {
                Label("Enter Manually", systemImage: "keyboard")
            }
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section("About") {
            LabeledContent("PPG Mobile", value: appVersion)
            LabeledContent("Server Protocol", value: "v1")

            Link(destination: URL(string: "https://github.com/jongravois/ppg-cli")!) {
                Label("GitHub Repository", systemImage: "link")
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var connectionStatusBadge: some View {
        switch appState.connectionStatus {
        case .connected:
            Label("Connected", systemImage: "circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .connecting:
            ProgressView()
                .controlSize(.small)
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
        case .disconnected:
            Label("Disconnected", systemImage: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var testConnectionRow: some View {
        Button {
            testConnection()
        } label: {
            HStack {
                Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                Spacer()
                switch testResult {
                case .testing:
                    ProgressView()
                        .controlSize(.small)
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failure:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                case nil:
                    EmptyView()
                }
            }
        }
        .disabled(testResult == .testing)
    }

    // MARK: - Actions

    private func handleQRScan(_ result: String) {
        if let conn = ServerConnection.fromQRCode(result) {
            appState.addConnection(conn)
            Task { await appState.connect(to: conn) }
        }
        showQRScanner = false
    }

    private func testConnection() {
        testResult = .testing
        Task {
            do {
                _ = try await appState.client.fetchStatus()
                testResult = .success
            } catch {
                testResult = .failure(error.localizedDescription)
            }
            // Auto-clear after 3 seconds
            try? await Task.sleep(for: .seconds(3))
            testResult = nil
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}
