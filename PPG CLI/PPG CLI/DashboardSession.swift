import AppKit
import Foundation

/// Codable representation of a PaneSplitNode tree (entry IDs only, no views).
struct GridLayoutNode: Codable {
    /// Leaf: entryId is the session entry ID (nil = empty placeholder pane).
    var entryId: String?
    /// Split: direction ("horizontal" or "vertical"), ratio, and exactly 2 children.
    var direction: String?
    var ratio: CGFloat?
    var children: [GridLayoutNode]?

    var isLeaf: Bool { children == nil }

    static func leaf(entryId: String?) -> GridLayoutNode {
        GridLayoutNode(entryId: entryId)
    }

    static func split(direction: String, ratio: CGFloat, first: GridLayoutNode, second: GridLayoutNode) -> GridLayoutNode {
        GridLayoutNode(direction: direction, ratio: ratio, children: [first, second])
    }
}

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
        /// When set, this entry belongs to a grid owned by another entry and should not appear in the sidebar.
        var gridOwnerEntryId: String?
        /// Agent variant identifier (e.g. "claude", "codex", "opencode"). Optional for backward compat.
        var variantId: String?

        enum Kind: String, Codable {
            case agent
            case terminal
        }
    }

    /// Wrapper for the on-disk format (entries + grid layouts).
    private struct SessionData: Codable {
        var entries: [TerminalEntry]
        var gridLayouts: [String: GridLayoutNode]?
    }

    let projectRoot: String
    private(set) var entries: [TerminalEntry] = []
    private var gridLayouts: [String: GridLayoutNode] = [:]
    private var terminalCounter = 0
    private var agentCounter = 0

    /// Serial queue for all disk I/O — keeps file reads/writes off the main thread.
    private let ioQueue = DispatchQueue(label: "ppg.dashboard-session.io", qos: .utility)
    /// Pending debounced write work item (cancelled + replaced on each mutation).
    private var pendingWrite: DispatchWorkItem?
    /// Debounce interval for disk writes (seconds).
    private let writeDebounceInterval: TimeInterval = 1.0

    init(projectRoot: String) {
        self.projectRoot = projectRoot
        loadFromDisk()
    }

    @discardableResult
    func addAgent(sessionName: String, parentWorktreeId: String?, variant: AgentVariant, command: String, workingDir: String, initialPrompt: String? = nil) -> TerminalEntry {
        dispatchPrecondition(condition: .onQueue(.main))
        agentCounter += 1
        let entryId = "da-\(generateId(6))"
        let sid = UUID().uuidString.lowercased()

        let effectiveSession = sessionName.isEmpty ? "ppg" : sessionName
        let windowName = "\(variant.id)-\(agentCounter)"
        let tmuxTarget = createTmuxWindow(sessionName: effectiveSession, windowName: windowName, cwd: workingDir)

        if let target = tmuxTarget {
            var cmdParts: [String] = []

            // 1. Environment prefix
            if variant.needsUnsetClaudeCode {
                cmdParts.append("unset CLAUDECODE")
            }
            if variant.id == "codex" {
                cmdParts.append(codexLaunchEnvironmentExports())
            }

            // 2. Base command + agent-specific flags
            var agentCmd = command
            if variant.needsSessionId {
                agentCmd += " --session-id \(sid)"
            }
            if variant.needsConductorContext, parentWorktreeId == nil {
                let contextPath = ((projectRoot as NSString)
                    .appendingPathComponent(".ppg") as NSString)
                    .appendingPathComponent("conductor-context.md")
                if FileManager.default.fileExists(atPath: contextPath) {
                    agentCmd += " --append-system-prompt \"$(cat \(shellEscape(contextPath)))\""
                }
            }

            // 3. Prompt delivery — positional arg mode
            if case .positionalArg = variant.promptDelivery, let prompt = initialPrompt, !prompt.isEmpty {
                agentCmd += " \(shellEscape(prompt))"
            }

            cmdParts.append(agentCmd)
            let fullCommand = cmdParts.joined(separator: "; ")
            sendTmuxKeys(target: target, command: fullCommand)

            // 4. Prompt delivery — sendKeys mode (after agent launches)
            if case .sendKeys = variant.promptDelivery, let prompt = initialPrompt, !prompt.isEmpty {
                let sendTarget = target
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.sendTmuxKeys(target: sendTarget, command: prompt)
                }
            }
        }

        let entry = TerminalEntry(
            id: entryId,
            label: "\(variant.displayName) \(agentCounter)",
            kind: .agent,
            parentWorktreeId: parentWorktreeId,
            workingDirectory: workingDir,
            command: command,
            tmuxTarget: tmuxTarget,
            sessionId: tmuxTarget != nil ? sid : nil,
            variantId: variant.id
        )
        entries.append(entry)
        saveToDisk()
        return entry
    }

    @discardableResult
    func addTerminal(parentWorktreeId: String?, workingDir: String) -> TerminalEntry {
        dispatchPrecondition(condition: .onQueue(.main))
        terminalCounter += 1
        let entry = TerminalEntry(
            id: "dt-\(generateId(6))",
            label: "Terminal \(terminalCounter)",
            kind: .terminal,
            parentWorktreeId: parentWorktreeId,
            workingDirectory: workingDir,
            command: AppSettingsManager.shared.shell,
            tmuxTarget: nil,
            sessionId: nil
        )
        entries.append(entry)
        saveToDisk()
        return entry
    }

    func rename(id: String, newLabel: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].label = newLabel
            saveToDisk()
        }
    }

    func remove(id: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        entries.removeAll { $0.id == id }
        saveToDisk()
    }

    func entriesForMaster() -> [TerminalEntry] {
        entries.filter { $0.parentWorktreeId == nil && $0.gridOwnerEntryId == nil }
    }

    func entriesForWorktree(_ worktreeId: String) -> [TerminalEntry] {
        entries.filter { $0.parentWorktreeId == worktreeId && $0.gridOwnerEntryId == nil }
    }

    func entriesForGrid(ownerEntryId: String) -> [TerminalEntry] {
        entries.filter { $0.gridOwnerEntryId == ownerEntryId }
    }

    func entry(byId id: String) -> TerminalEntry? {
        entries.first { $0.id == id }
    }

    func setGridOwner(entryId: String, gridOwnerEntryId: String?) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let index = entries.firstIndex(where: { $0.id == entryId }) {
            entries[index].gridOwnerEntryId = gridOwnerEntryId
            saveToDisk()
        }
    }

    // MARK: - Grid Layouts

    func saveGridLayout(ownerEntryId: String, layout: GridLayoutNode) {
        dispatchPrecondition(condition: .onQueue(.main))
        gridLayouts[ownerEntryId] = layout
        saveToDisk()
    }

    func gridLayout(forOwnerEntryId ownerEntryId: String) -> GridLayoutNode? {
        gridLayouts[ownerEntryId]
    }

    func removeGridLayout(ownerEntryId: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        gridLayouts.removeValue(forKey: ownerEntryId)
        saveToDisk()
    }

    func removeAll() {
        dispatchPrecondition(condition: .onQueue(.main))
        entries.removeAll()
        gridLayouts.removeAll()
        terminalCounter = 0
        agentCounter = 0
        saveToDisk()
    }

    // MARK: - Persistence

    private var persistencePath: String? {
        guard !projectRoot.isEmpty, projectRoot != "/" else { return nil }
        let ppgDir = (projectRoot as NSString).appendingPathComponent(".ppg")
        return (ppgDir as NSString).appendingPathComponent("dashboard-sessions.json")
    }

    private func saveToDisk() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let path = persistencePath else { return }

        // Snapshot current state for the background write
        let sessionData = SessionData(
            entries: entries,
            gridLayouts: gridLayouts.isEmpty ? nil : gridLayouts
        )

        // Cancel any pending debounced write and schedule a new one
        pendingWrite?.cancel()
        let workItem = DispatchWorkItem { [sessionData] in
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(sessionData)
                try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            } catch {
                // Non-fatal — entries will be lost on restart
            }
        }
        pendingWrite = workItem
        ioQueue.asyncAfter(deadline: .now() + writeDebounceInterval, execute: workItem)
    }

    /// Force an immediate synchronous write (e.g., before app termination).
    /// Serializes against any in-flight debounced write on ioQueue.
    func flushToDisk() {
        dispatchPrecondition(condition: .onQueue(.main))
        pendingWrite?.cancel()
        pendingWrite = nil
        guard let path = persistencePath else { return }
        let sessionData = SessionData(
            entries: entries,
            gridLayouts: gridLayouts.isEmpty ? nil : gridLayouts
        )
        ioQueue.sync {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(sessionData)
                try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            } catch {
                // Non-fatal
            }
        }
    }

    private func loadFromDisk() {
        // Cancel any pending debounced write — we're about to reload from disk
        pendingWrite?.cancel()
        pendingWrite = nil

        guard let path = persistencePath,
              FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else { return }

        // Try new wrapper format first, fall back to legacy [TerminalEntry] array
        if let sessionData = try? JSONDecoder().decode(SessionData.self, from: data) {
            entries = sessionData.entries
            gridLayouts = sessionData.gridLayouts ?? [:]
        } else if let legacyEntries = try? JSONDecoder().decode([TerminalEntry].self, from: data) {
            entries = legacyEntries
            gridLayouts = [:]
        } else {
            entries = []
            gridLayouts = [:]
        }
        agentCounter = entries.filter { $0.kind == .agent }.count
        terminalCounter = entries.filter { $0.kind == .terminal }.count
    }

    func reloadFromDisk() {
        dispatchPrecondition(condition: .onQueue(.main))
        entries = []
        gridLayouts = [:]
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
        runTmux("set-option -t \(escapedSession) history-limit \(AppSettingsManager.shared.historyLimit)")

        let result = runTmux("new-window -t \(escapedSession) -n \(escapedName) -c \(escapedCwd) -P -F '#{window_index}'")
        guard result.exitCode == 0, !result.stdout.isEmpty else { return nil }
        return "\(sessionName):\(result.stdout)"
    }

    func killTmuxWindow(target: String) {
        runTmux("kill-window -t \(shellEscape(target))")
    }

    func sendTmuxKeys(target: String, command: String) {
        runTmux("send-keys -t \(shellEscape(target)) -l \(shellEscape(command + "\n"))")
    }

    private func generateId(_ length: Int) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private func codexLaunchEnvironmentExports() -> String {
        let colorFgBg = isDarkAppearanceForAgents() ? "15;0" : "0;15"
        let envPairs = [
            ("COLORTERM", "truecolor"),
            ("COLORFGBG", colorFgBg),
            ("TERM_PROGRAM", "ppg-cli"),
        ]
        return envPairs
            .map { key, value in "export \(key)=\(shellEscape(value))" }
            .joined(separator: "; ")
    }

    private func isDarkAppearanceForAgents() -> Bool {
        switch AppSettingsManager.shared.appearanceMode {
        case .dark:
            return true
        case .light:
            return false
        case .system:
            let match = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua
        }
    }
}
