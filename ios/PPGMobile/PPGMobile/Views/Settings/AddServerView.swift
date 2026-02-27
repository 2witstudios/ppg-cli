import SwiftUI

struct AddServerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = "My Mac"
    @State private var host = ""
    @State private var port = "7700"
    @State private var token = ""
    @State private var showToken = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server Details") {
                    TextField("Name", text: $name)

                    TextField("Host (e.g., 192.168.1.100)", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                }

                Section("Authentication") {
                    HStack {
                        Group {
                            if showToken {
                                TextField("Token", text: $token)
                                    .fontDesign(.monospaced)
                            } else {
                                SecureField("Token", text: $token)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            showToken.toggle()
                        } label: {
                            Image(systemName: showToken ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Button {
                        addServer()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Add Server")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!isValid)
                }
            }
            .navigationTitle("Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var isValid: Bool {
        !trimmedHost.isEmpty
            && !trimmedToken.isEmpty
            && parsedPort != nil
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedPort: Int? {
        guard
            let value = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)),
            (1...65_535).contains(value)
        else {
            return nil
        }
        return value
    }

    private func addServer() {
        guard let validatedPort = parsedPort else { return }
        let connection = ServerConnection(
            name: trimmedName.isEmpty ? "My Mac" : trimmedName,
            host: trimmedHost,
            port: validatedPort,
            token: trimmedToken
        )
        appState.addConnection(connection)
        Task { await appState.connect(to: connection) }
        dismiss()
    }
}
