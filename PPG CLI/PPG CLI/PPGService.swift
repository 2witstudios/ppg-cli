import Foundation

nonisolated class PoguService: @unchecked Sendable {
    static let shared = PoguService()
    static let minimumTmuxVersionForCodexInputTheme = "3.5"

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

    func runPoguCommand(_ args: String, projectRoot: String) -> CommandResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let cmd = """
        if [ -x /usr/libexec/path_helper ]; then eval $(/usr/libexec/path_helper -s); fi; \
        [ -f ~/.zprofile ] && source ~/.zprofile; \
        [ -f ~/.zshrc ] && source ~/.zshrc; \
        cd \(shellEscape(projectRoot)) && pogu \(args)
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

    /// Check if pogu CLI is available in the user's PATH.
    func checkCLIAvailable() -> (available: Bool, version: String?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let cmd = """
        if [ -x /usr/libexec/path_helper ]; then eval $(/usr/libexec/path_helper -s); fi; \
        [ -f ~/.zprofile ] && source ~/.zprofile; \
        [ -f ~/.zshrc ] && source ~/.zshrc; \
        pogu --version
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

    /// Check if tmux is available in the user's PATH and whether its version
    /// supports Codex input theming inside tmux.
    func checkTmuxAvailable() -> (available: Bool, version: String?, supportsCodexInputTheme: Bool) {
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
            guard task.terminationStatus == 0 else {
                return (false, nil, false)
            }
            let data = (task.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
            let stdout = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let version = extractTmuxVersion(from: stdout)
            let supports = version.map {
                isVersion($0, atLeast: Self.minimumTmuxVersionForCodexInputTheme)
            } ?? false
            return (true, version, supports)
        } catch {
            return (false, nil, false)
        }
    }

    private func extractTmuxVersion(from output: String) -> String? {
        // Match the "tmux X.Y" line specifically to avoid false positives
        // from shell startup scripts that may print version-like numbers.
        guard let range = output.range(
            of: #"tmux\s+([0-9]+(?:\.[0-9]+)*[a-z]?)"#,
            options: .regularExpression
        ) else {
            return nil
        }
        let match = output[range]
        // Extract just the version number after "tmux "
        guard let versionRange = match.range(
            of: #"[0-9]+(?:\.[0-9]+)*[a-z]?"#,
            options: .regularExpression
        ) else {
            return nil
        }
        return String(match[versionRange])
    }

    private func isVersion(_ version: String, atLeast minimum: String) -> Bool {
        guard let lhs = versionComponents(version),
              let rhs = versionComponents(minimum) else { return false }
        let count = max(lhs.count, rhs.count)
        for idx in 0..<count {
            let l = idx < lhs.count ? lhs[idx] : 0
            let r = idx < rhs.count ? rhs[idx] : 0
            if l != r { return l > r }
        }
        return true
    }

    private func versionComponents(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".")
        guard !parts.isEmpty else { return nil }
        var ints: [Int] = []
        for part in parts {
            let numericPrefix = part.prefix { $0.isNumber }
            guard !numericPrefix.isEmpty, let value = Int(numericPrefix) else {
                return nil
            }
            ints.append(value)
        }
        return ints
    }

    /// Run a git command directly in a specific directory. Faster than runPoguCommand
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

    /// Get the current branch name for a repository.
    func currentBranch(at path: String) -> String {
        let result = runGitCommand(["rev-parse", "--abbrev-ref", "HEAD"], cwd: path)
        let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? "main" : branch
    }

    /// Check if a directory is a git repository.
    func isGitRepo(_ path: String) -> Bool {
        let gitDir = (path as NSString).appendingPathComponent(".git")
        return FileManager.default.fileExists(atPath: gitDir)
    }

    /// Check the npm registry for the latest published version of pointguard.
    func checkLatestCLIVersion() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let cmd = """
        if [ -x /usr/libexec/path_helper ]; then eval $(/usr/libexec/path_helper -s); fi; \
        [ -f ~/.zprofile ] && source ~/.zprofile; \
        [ -f ~/.zshrc ] && source ~/.zshrc; \
        npm view pointguard version
        """
        task.arguments = ["-c", cmd]

        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        guard task.terminationStatus == 0 else { return nil }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (version?.isEmpty == false) ? version : nil
    }

    /// Install the latest version of pointguard globally via npm.
    func updateCLI() -> (success: Bool, output: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let cmd = """
        if [ -x /usr/libexec/path_helper ]; then eval $(/usr/libexec/path_helper -s); fi; \
        [ -f ~/.zprofile ] && source ~/.zprofile; \
        [ -f ~/.zshrc ] && source ~/.zshrc; \
        npm install -g pointguard@latest 2>&1
        """
        task.arguments = ["-c", cmd]

        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (task.terminationStatus == 0, output)
    }

    /// Run `pogu init` in the given directory. Returns true on success.
    func initProject(at projectRoot: String) -> Bool {
        let result = runPoguCommand("init --json", projectRoot: projectRoot)
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
