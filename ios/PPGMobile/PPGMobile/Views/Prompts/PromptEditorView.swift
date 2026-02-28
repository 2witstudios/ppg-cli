import SwiftUI

/// Read-only markdown viewer for a prompt/template file.
/// Highlights `{{VAR}}` syntax placeholders.
struct PromptEditorView: View {
    let promptName: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Read Only", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Text("Prompt content is managed on the server. Use the macOS app or edit files directly in `.ppg/prompts/` or `.ppg/templates/`.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Divider()

                Text(promptName)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
        }
        .navigationTitle(promptName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
