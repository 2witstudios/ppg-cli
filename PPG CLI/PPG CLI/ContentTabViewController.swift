import AppKit
import SwiftTerm

enum TabEntry {
    case manifestAgent(AgentModel, sessionName: String)
    case agentGroup([AgentModel], String, sessionName: String)  // agents sharing a tmux window, tmuxTarget, sessionName
    case sessionEntry(DashboardSession.TerminalEntry, sessionName: String)

    var id: String {
        switch self {
        case .manifestAgent(let agent, _): return agent.id
        case .agentGroup(let agents, _, _): return agents.map(\.id).joined(separator: "+")
        case .sessionEntry(let entry, _): return entry.id
        }
    }

    var label: String {
        switch self {
        case .manifestAgent(let agent, _): return "\(agent.id) — \(agent.agentType)"
        case .agentGroup(let agents, _, _): return "\(agents.count) agents (split)"
        case .sessionEntry(let entry, _): return entry.label
        }
    }

    var sessionName: String {
        switch self {
        case .manifestAgent(_, let name): return name
        case .agentGroup(_, _, let name): return name
        case .sessionEntry(_, let name): return name
        }
    }
}

class ContentViewController: NSViewController {
    let placeholderLabel = NSTextField(labelWithString: "Select an item from the sidebar")
    private let containerView = NSView()
    private(set) var currentEntry: TabEntry?
    private var terminalViews: [String: NSView] = [:]

    var currentEntryId: String? { currentEntry?.id }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 0.7).cgColor

        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        placeholderLabel.font = .systemFont(ofSize: 16)
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.alignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            placeholderLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func showEntry(_ entry: TabEntry?) {
        guard let entry = entry else {
            // Show placeholder
            for (_, termView) in terminalViews {
                termView.isHidden = true
            }
            currentEntry = nil
            placeholderLabel.isHidden = false
            containerView.isHidden = true
            return
        }

        // Same entry already showing — no-op
        if let current = currentEntry, current.id == entry.id {
            return
        }

        currentEntry = entry
        placeholderLabel.isHidden = true
        containerView.isHidden = false

        for (_, termView) in terminalViews {
            termView.isHidden = true
        }

        let termView = terminalView(for: entry)
        termView.isHidden = false
    }

    func updateCurrentEntry(_ entry: TabEntry) {
        guard let current = currentEntry, current.id == entry.id else { return }
        currentEntry = entry
        switch entry {
        case .manifestAgent(let agent, _):
            if let pane = terminalViews[agent.id] as? TerminalPane {
                pane.updateStatus(agent.status)
            }
        case .agentGroup(let agents, _, _):
            if let pane = terminalViews[entry.id] as? TerminalPane {
                let status = agents.first?.status ?? .lost
                pane.updateStatus(status)
            }
        case .sessionEntry:
            break
        }
    }

    func removeEntry(byId id: String) {
        if let termView = terminalViews[id] {
            terminateTerminal(termView)
            termView.removeFromSuperview()
            terminalViews.removeValue(forKey: id)
        }
        if currentEntry?.id == id {
            currentEntry = nil
            placeholderLabel.isHidden = false
            containerView.isHidden = true
        }
    }

    func clearStaleViews(validIds: Set<String>) {
        let staleIds = terminalViews.keys.filter { !validIds.contains($0) }
        for id in staleIds {
            if let termView = terminalViews[id] {
                terminateTerminal(termView)
                termView.removeFromSuperview()
                terminalViews.removeValue(forKey: id)
            }
        }
    }

    // MARK: - Private

    private func terminalView(for tab: TabEntry) -> NSView {
        if let existing = terminalViews[tab.id] {
            return existing
        }

        let sessionName = tab.sessionName
        let termView: NSView
        switch tab {
        case .manifestAgent(let agent, _):
            let pane = TerminalPane(agent: agent, sessionName: sessionName)
            pane.startTmux()
            termView = pane

        case .agentGroup(let agents, let tmuxTarget, _):
            let lead = agents[0]
            let groupAgent = AgentModel(
                id: tab.id,
                name: lead.name,
                agentType: lead.agentType,
                status: lead.status,
                tmuxTarget: tmuxTarget,
                prompt: lead.prompt,
                startedAt: lead.startedAt
            )
            let pane = TerminalPane(agent: groupAgent, sessionName: sessionName)
            pane.startTmux()
            termView = pane

        case .sessionEntry(let entry, _):
            if let tmuxTarget = entry.tmuxTarget {
                let agentModel = AgentModel(
                    id: entry.id,
                    name: entry.label,
                    agentType: entry.kind == .agent ? "claude" : "terminal",
                    status: .running,
                    tmuxTarget: tmuxTarget,
                    prompt: "",
                    startedAt: "",
                    sessionId: entry.sessionId
                )
                let pane = TerminalPane(agent: agentModel, sessionName: sessionName)
                pane.startTmux()
                termView = pane
            } else {
                let localTerm = ScrollableTerminalView(frame: containerView.bounds)
                let cmd = """
                if [ -x /usr/libexec/path_helper ]; then eval $(/usr/libexec/path_helper -s); fi; \
                [ -f ~/.zprofile ] && source ~/.zprofile; \
                [ -f ~/.zshrc ] && source ~/.zshrc; \
                cd \(shellEscape(entry.workingDirectory)) && exec \(entry.command)
                """
                localTerm.startProcess(
                    executable: "/bin/zsh",
                    args: ["-c", cmd],
                    environment: nil,
                    execName: "zsh"
                )
                termView = localTerm
            }
        }

        termView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(termView)
        NSLayoutConstraint.activate([
            termView.topAnchor.constraint(equalTo: containerView.topAnchor),
            termView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            termView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            termView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        terminalViews[tab.id] = termView
        return termView
    }

    private func terminateTerminal(_ view: NSView) {
        if let pane = view as? TerminalPane {
            pane.terminate()
        } else if let scrollTerm = view as? ScrollableTerminalView {
            scrollTerm.process?.terminate()
        } else if let localTerm = view as? LocalProcessTerminalView {
            localTerm.process?.terminate()
        }
    }
}
