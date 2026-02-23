import Foundation

class DashboardSession {
    static let shared = DashboardSession()

    struct TerminalEntry {
        let id: String
        var label: String
        let kind: Kind
        let parentWorktreeId: String?
        let workingDirectory: String
        let command: String

        enum Kind {
            case agent
            case terminal
        }
    }

    private(set) var entries: [TerminalEntry] = []
    private var terminalCounter = 0
    private var agentCounter = 0

    @discardableResult
    func addAgent(parentWorktreeId: String?, command: String, workingDir: String) -> TerminalEntry {
        agentCounter += 1
        let entry = TerminalEntry(
            id: "da-\(generateId(6))",
            label: "Claude \(agentCounter)",
            kind: .agent,
            parentWorktreeId: parentWorktreeId,
            workingDirectory: workingDir,
            command: command
        )
        entries.append(entry)
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
            command: "/bin/zsh"
        )
        entries.append(entry)
        return entry
    }

    func rename(id: String, newLabel: String) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].label = newLabel
        }
    }

    func remove(id: String) {
        entries.removeAll { $0.id == id }
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
    }

    private func generateId(_ length: Int) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}
