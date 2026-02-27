import SwiftUI

struct SpawnView: View {
    @Environment(AppState.self) private var appState

    // Form fields
    @State private var name = ""
    @State private var prompt = ""
    @State private var selectedVariant: AgentVariant = .claude
    @State private var count = 1
    @State private var baseBranch = ""
    @State private var selectedTemplate: String?

    // UI state
    @State private var isSpawning = false
    @State private var errorMessage: String?
    @State private var spawnedWorktree: WorktreeEntry?
    @State private var showResult = false

    private var isFormValid: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let hasPrompt = !prompt.trimmingCharacters(in: .whitespaces).isEmpty
        let hasTemplate = selectedTemplate != nil
        return hasName && (hasPrompt || hasTemplate)
    }

    private var spawnableVariants: [AgentVariant] {
        [.claude, .codex, .opencode]
    }

    private var availableBranches: [String] {
        var branches = Set<String>()
        branches.insert("main")
        if let manifest = appState.manifestStore.manifest {
            for wt in manifest.worktrees.values {
                branches.insert(wt.baseBranch)
            }
        }
        return branches.sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                agentSection
                promptSection
                templatesSection
                baseBranchSection
                errorSection
            }
            .navigationTitle("Spawn")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    spawnButton
                }
            }
            .navigationDestination(isPresented: $showResult) {
                if let worktree = spawnedWorktree {
                    WorktreeDetailView(worktree: worktree)
                }
            }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            TextField("Worktree name", text: $name)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Name")
        } footer: {
            Text("Required. Used as the branch suffix (ppg/<name>)")
        }
    }

    private var agentSection: some View {
        Section("Agent") {
            Picker("Type", selection: $selectedVariant) {
                ForEach(spawnableVariants, id: \.self) { variant in
                    Label(variant.displayName, systemImage: variant.icon)
                        .tag(variant)
                }
            }

            Stepper("Count: \(count)", value: $count, in: 1...10)
        }
    }

    private var promptSection: some View {
        Section {
            TextEditor(text: $prompt)
                .frame(minHeight: 120)
                .font(.body)
        } header: {
            Text("Prompt")
        } footer: {
            if selectedTemplate != nil {
                Text("Template selected — prompt is optional")
            } else {
                Text("Required if no template is selected")
            }
        }
    }

    @ViewBuilder
    private var templatesSection: some View {
        if !appState.templates.isEmpty {
            Section("Quick Templates") {
                ForEach(appState.templates, id: \.self) { template in
                    Button {
                        withAnimation {
                            selectedTemplate = selectedTemplate == template ? nil : template
                        }
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                            Text(template)
                            Spacer()
                            if selectedTemplate == template {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
        }
    }

    private var baseBranchSection: some View {
        Section {
            Picker("Base branch", selection: $baseBranch) {
                Text("Default (current)").tag("")
                ForEach(availableBranches, id: \.self) { branch in
                    Text(branch).tag(branch)
                }
            }
        } footer: {
            Text("Branch to create the worktree from")
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage {
            Section {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    private var spawnButton: some View {
        Button {
            Task { await spawnWorktree() }
        } label: {
            if isSpawning {
                ProgressView()
            } else {
                Text("Spawn")
                    .bold()
            }
        }
        .disabled(!isFormValid || isSpawning)
    }

    // MARK: - Actions

    @MainActor
    private func spawnWorktree() async {
        isSpawning = true
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespaces)
        let promptText = trimmedPrompt.isEmpty
            ? (selectedTemplate ?? "")
            : trimmedPrompt

        do {
            let response = try await appState.client.spawn(
                name: trimmedName,
                agent: selectedVariant.rawValue,
                prompt: promptText,
                template: selectedTemplate,
                base: baseBranch.isEmpty ? nil : baseBranch,
                count: count
            )

            await appState.manifestStore.refresh()

            if let newWorktree = appState.manifestStore.manifest?.worktrees[response.worktree.id] {
                spawnedWorktree = newWorktree
                clearForm()
                showResult = true
            } else {
                clearForm()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isSpawning = false
    }

    private func clearForm() {
        name = ""
        prompt = ""
        selectedVariant = .claude
        count = 1
        baseBranch = ""
        selectedTemplate = nil
        errorMessage = nil
    }
}
