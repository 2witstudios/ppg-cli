import Foundation

nonisolated class PPGService: @unchecked Sendable {
    static let shared = PPGService()

    var manifestPath: String { ProjectState.shared.manifestPath }

    func readManifest() -> ManifestModel? {
        guard !manifestPath.isEmpty else { return nil }
        guard let data = FileManager.default.contents(atPath: manifestPath) else { return nil }
        return try? JSONDecoder().decode(ManifestModel.self, from: data)
    }

    struct CommandResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    func runPPGCommand(_ args: String, projectRoot: String) -> CommandResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let cmd = """
        if [ -x /usr/libexec/path_helper ]; then eval $(/usr/libexec/path_helper -s); fi; \
        [ -f ~/.zprofile ] && source ~/.zprofile; \
        [ -f ~/.zshrc ] && source ~/.zshrc; \
        cd '\(projectRoot.replacingOccurrences(of: "'", with: "'\\''"))' && ppg \(args)
        """
        task.arguments = ["-c", cmd]

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return CommandResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(
            exitCode: task.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    func refreshStatus() -> [WorktreeModel] {
        guard let manifest = readManifest() else { return [] }

        return manifest.worktrees.values
            .filter { $0.status != "cleaned" && $0.status != "merged" }
            .sorted { $0.createdAt < $1.createdAt }
            .map { entry in
                let agents = entry.agents.values
                    .sorted { $0.startedAt < $1.startedAt }
                    .map { AgentModel(from: $0) }
                return WorktreeModel(
                    id: entry.id,
                    name: entry.name,
                    path: entry.path,
                    branch: entry.branch,
                    status: entry.status,
                    tmuxWindow: entry.tmuxWindow,
                    agents: agents
                )
            }
    }
}
