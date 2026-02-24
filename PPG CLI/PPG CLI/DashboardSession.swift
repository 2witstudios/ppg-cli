import Foundation

class DashboardSession {
    struct TerminalEntry: Codable {
        let id: String
        var label: String
        let kind: Kind
        let parentWorktreeId: String?
        let workingDirectory: String
        let command: String
        var tmuxTarget: String?
        var sessionId: String?

        enum Kind: String, Codable {
            case agent
            case terminal
        }
    }

    let projectRoot: String
    private(set) var entries: [TerminalEntry] = []
    private var terminalCounter = 0
    private var agentCounter = 0

    init(projectRoot: String) {
        self.projectRoot = projectRoot
        loadFromDisk()
    }

    @discardableResult
    func addAgent(sessionName: String, parentWorktreeId: String?, command: String, workingDir: String) -> TerminalEntry {
        agentCounter += 1
        let entryId = "da-\(generateId(6))"
        let sid = UUID().uuidString.lowercased()

        let effectiveSession = sessionName.isEmpty ? "ppg" : sessionName
        let tmuxTarget = createTmuxWindow(sessionName: effectiveSession, windowName: "claude-\(agentCounter)", cwd: workingDir)

        if let target = tmuxTarget {
            let fullCommand: String
            if command.contains("claude") {
                var cmd = "unset CLAUDECODE; \(command) --session-id \(sid)"
                if parentWorktreeId == nil {
                    let contextPath = ((projectRoot as NSString)
                        .appendingPathComponent(".pg") as NSString)
                        .appendingPathComponent("conductor-context.md")
                    if FileManager.default.fileExists(atPath: contextPath) {
                        cmd += " --append-system-prompt \"$(cat \(shellEscape(contextPath)))\""
                    }
                }
                fullCommand = cmd
            } else {
                fullCommand = command
            }
            sendTmuxKeys(target: target, command: fullCommand)
        }

        let entry = TerminalEntry(
            id: entryId,
            label: "Claude \(agentCounter)",
            kind: .agent,
            parentWorktreeId: parentWorktreeId,
            workingDirectory: workingDir,
            command: command,
            tmuxTarget: tmuxTarget,
            sessionId: tmuxTarget != nil ? sid : nil
        )
        entries.append(entry)
        saveToDisk()
        return entry
    }

    @discardableResult
    func addTerminal(parentWorktreeId: String?, workingDir: String) -> TerminalEntry {
        terminalCounter += 1
        let entry = TerminalEntry(
            id: "dt-\(generateId(6))",
            label: "Terminal \(terminalCounter)",
            kind: .terminal,
            parentWorktreeId: parentWorktreeId,
            workingDirectory: workingDir,
            command: "/bin/zsh",
            tmuxTarget: nil,
            sessionId: nil
        )
        entries.append(entry)
        saveToDisk()
        return entry
    }

    func rename(id: String, newLabel: String) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].label = newLabel
            saveToDisk()
        }
    }

    func remove(id: String) {
        entries.removeAll { $0.id == id }
        saveToDisk()
    }

    func entriesForMaster() -> [TerminalEntry] {
        entries.filter { $0.parentWorktreeId == nil }
    }

    func entriesForWorktree(_ worktreeId: String) -> [TerminalEntry] {
        entries.filter { $0.parentWorktreeId == worktreeId }
    }

    func entry(byId id: String) -> TerminalEntry? {
        entries.first { $0.id == id }
    }

    func removeAll() {
        entries.removeAll()
        terminalCounter = 0
        agentCounter = 0
        saveToDisk()
    }

    // MARK: - Persistence

    private var persistencePath: String? {
        guard !projectRoot.isEmpty, projectRoot != "/" else { return nil }
        let pgDir = (projectRoot as NSString).appendingPathComponent(".pg")
        return (pgDir as NSString).appendingPathComponent("dashboard-sessions.json")
    }

    private func saveToDisk() {
        guard let path = persistencePath else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            // Non-fatal — entries will be lost on restart
        }
    }

    private func loadFromDisk() {
        guard let path = persistencePath,
              FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else { return }
        do {
            entries = try JSONDecoder().decode([TerminalEntry].self, from: data)
            agentCounter = entries.filter { $0.kind == .agent }.count
            terminalCounter = entries.filter { $0.kind == .terminal }.count
        } catch {
            entries = []
        }
    }

    func reloadFromDisk() {
        entries = []
        terminalCounter = 0
        agentCounter = 0
        loadFromDisk()
    }

    // MARK: - Tmux helpers

    @discardableResult
    private func runTmux(_ args: String) -> (exitCode: Int32, stdout: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let cmd = """
        if [ -x /usr/libexec/path_helper ]; then eval $(/usr/libexec/path_helper -s); fi; \
        [ -f ~/.zprofile ] && source ~/.zprofile; \
        [ -f ~/.zshrc ] && source ~/.zshrc; \
        tmux \(args)
        """
        task.arguments = ["-c", cmd]
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return (-1, "")
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (task.terminationStatus, stdout)
    }

    private func createTmuxWindow(sessionName: String, windowName: String, cwd: String) -> String? {
        let escapedSession = shellEscape(sessionName)
        let escapedName = shellEscape(windowName)
        let escapedCwd = shellEscape(cwd)

        let hasResult = runTmux("has-session -t \(escapedSession)")
        if hasResult.exitCode != 0 {
            let createResult = runTmux("new-session -d -s \(escapedSession) -x 220 -y 50")
            guard createResult.exitCode == 0 else { return nil }
        }
        runTmux("set-option -t \(escapedSession) mouse on")
        runTmux("set-option -t \(escapedSession) history-limit 50000")

        let result = runTmux("new-window -t \(escapedSession) -n \(escapedName) -c \(escapedCwd) -P -F '#{window_index}'")
        guard result.exitCode == 0, !result.stdout.isEmpty else { return nil }
        return "\(sessionName):\(result.stdout)"
    }

    func killTmuxWindow(target: String) {
        runTmux("kill-window -t \(shellEscape(target))")
    }

    private func sendTmuxKeys(target: String, command: String) {
        runTmux("send-keys -t \(shellEscape(target)) -l \(shellEscape(command + "\n"))")
    }

    private func generateId(_ length: Int) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}
