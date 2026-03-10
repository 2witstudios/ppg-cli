import SwiftUI

/// Bottom input bar for sending text to a terminal pane via WebSocket.
struct TerminalInputBar: View {
    @Binding var text: String
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Send to terminal...", text: $text)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .onSubmit(onSend)

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(text.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
