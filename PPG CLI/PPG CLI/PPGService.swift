import Foundation

nonisolated class PPGService: @unchecked Sendable {
    static let shared = PPGService()

    /// Read manifest from the given path. Thread-safe: does not access shared mutable state.
    func readManifest(at path: String) -> ManifestModel? {
        guard !path.isEmpty else { return nil }
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(ManifestModel.self, from: data)
    }

    /// Convenience: read manifest from ProjectState. Only call from main thread.
    func readManifest() -> ManifestModel? {
        readManifest(at: ProjectState.shared.manifestPath)
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
        cd \(shellEscape(projectRoot)) && ppg \(args)
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

    /// Check if ppg CLI is available in the user's PATH.
    func checkCLIAvailable() -> (available: Bool, version: String?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let cmd = """
        if [ -x /usr/libexec/path_helper ]; then eval $(/usr/libexec/path_helper -s); fi; \
        [ -f ~/.zprofile ] && source ~/.zprofile; \
        [ -f ~/.zshrc ] && source ~/.zshrc; \
        ppg --version
        """
        task.arguments = ["-c", cmd]

        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return (false, nil)
        }

        if task.terminationStatus == 0 {
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (true, version)
        }
        return (false, nil)
    }

    /// Check if tmux is available in the user's PATH.
    func checkTmuxAvailable() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let cmd = """
        if [ -x /usr/libexec/path_helper ]; then eval $(/usr/libexec/path_helper -s); fi; \
        [ -f ~/.zprofile ] && source ~/.zprofile; \
        [ -f ~/.zshrc ] && source ~/.zshrc; \
        tmux -V
        """
        task.arguments = ["-c", cmd]
        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Run a git command directly in a specific directory. Faster than runPPGCommand
    /// since git doesn't need shell profile sourcing.
    func runGitCommand(_ args: [String], cwd: String) -> CommandResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = args
        task.currentDirectoryURL = URL(fileURLWithPath: cwd)

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

    /// Check if a directory is a git repository.
    func isGitRepo(_ path: String) -> Bool {
        let pgDir = (path as NSString).appendingPathComponent(".git")
        return FileManager.default.fileExists(atPath: pgDir)
    }

    /// Run `ppg init` in the given directory. Returns true on success.
    func initProject(at projectRoot: String) -> Bool {
        let result = runPPGCommand("init --json", projectRoot: projectRoot)
        return result.exitCode == 0
    }

    /// Convenience: refresh using ProjectState. Only call from main thread.
    func refreshStatus() -> [WorktreeModel] {
        refreshStatus(manifestPath: ProjectState.shared.manifestPath)
    }

    /// Refresh status using the given manifest path. Thread-safe.
    func refreshStatus(manifestPath: String) -> [WorktreeModel] {
        guard let manifest = readManifest(at: manifestPath) else { return [] }

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
