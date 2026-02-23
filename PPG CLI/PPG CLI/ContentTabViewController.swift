import AppKit
import SwiftTerm

enum TabEntry {
    case manifestAgent(AgentModel)
    case agentGroup([AgentModel], String)  // agents sharing a tmux window, tmuxTarget
    case sessionEntry(DashboardSession.TerminalEntry)

    var id: String {
        switch self {
        case .manifestAgent(let agent): return agent.id
        case .agentGroup(let agents, _): return agents.map(\.id).joined(separator: "+")
        case .sessionEntry(let entry): return entry.id
        }
    }

    var label: String {
        switch self {
        case .manifestAgent(let agent): return "\(agent.id) — \(agent.agentType)"
        case .agentGroup(let agents, _): return "\(agents.count) agents (split)"
        case .sessionEntry(let entry): return entry.label
        }
    }
}

class ContentTabViewController: NSViewController {
    let segmentedControl = NSSegmentedControl()
    let placeholderLabel = NSTextField(labelWithString: "Select an item from the sidebar")
    private let containerView = NSView()
    private(set) var tabs: [TabEntry] = []
    private var terminalViews: [String: NSView] = [:]
    private(set) var selectedIndex: Int = -1

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        segmentedControl.segmentStyle = .automatic
        segmentedControl.target = self
        segmentedControl.action = #selector(tabClicked(_:))
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.borderShape = .capsule
        segmentedControl.isHidden = true
        view.addSubview(segmentedControl)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        placeholderLabel.font = .systemFont(ofSize: 16)
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.alignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            segmentedControl.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            segmentedControl.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            segmentedControl.heightAnchor.constraint(equalToConstant: 28),

            containerView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            placeholderLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func showTabs(for entries: [TabEntry]) {
        // Tear down old terminals that aren't in the new set
        let newIds = Set(entries.map(\.id))
        for (id, termView) in terminalViews where !newIds.contains(id) {
            terminateTerminal(termView)
            termView.removeFromSuperview()
            terminalViews.removeValue(forKey: id)
        }

        tabs = entries
        rebuildSegmentedControl()

        if tabs.isEmpty {
            placeholderLabel.isHidden = false
            segmentedControl.isHidden = true
            containerView.isHidden = true
            selectedIndex = -1
        } else {
            placeholderLabel.isHidden = true
            segmentedControl.isHidden = false
            containerView.isHidden = false
            selectTab(at: 0)
        }
    }

    /// Update tab metadata in-place without tearing down terminal views.
    /// Only updates labels and agent status — does NOT destroy/recreate terminals.
    func updateTabs(with entries: [TabEntry]) {
        tabs = entries
        rebuildSegmentedControl()

        // Update status labels on existing TerminalPane views
        for entry in entries {
            switch entry {
            case .manifestAgent(let agent):
                if let termView = terminalViews[agent.id],
                   let pane = termView as? TerminalPane {
                    pane.updateStatus(agent.status)
                }
            case .agentGroup(let agents, _):
                let groupId = entry.id
                if let termView = terminalViews[groupId],
                   let pane = termView as? TerminalPane {
                    // Use the "worst" status from the group for the badge
                    let status = agents.first?.status ?? .lost
                    pane.updateStatus(status)
                }
            case .sessionEntry:
                break
            }
        }
    }

    func selectTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        selectedIndex = index
        segmentedControl.selectedSegment = index

        // Hide all terminal views
        for (_, termView) in terminalViews {
            termView.isHidden = true
        }

        let tab = tabs[index]
        let termView = terminalView(for: tab)
        termView.isHidden = false
    }

    func selectTab(matchingId id: String) {
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            selectTab(at: index)
        }
    }

    func addTab(_ entry: TabEntry) {
        tabs.append(entry)
        rebuildSegmentedControl()
        selectTab(at: tabs.count - 1)
        placeholderLabel.isHidden = true
        segmentedControl.isHidden = false
        containerView.isHidden = false
    }

    func currentTabIds() -> [String] {
        tabs.map(\.id)
    }

    func updateTabLabel(id: String, newLabel: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if let updated = DashboardSession.shared.entry(byId: id) {
            tabs[index] = .sessionEntry(updated)
        }
        segmentedControl.setLabel(newLabel, forSegment: index)
    }

    func removeTab(byId id: String) {
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            removeTab(at: index)
        }
    }

    func removeTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        let tab = tabs[index]
        if let termView = terminalViews[tab.id] {
            terminateTerminal(termView)
            termView.removeFromSuperview()
            terminalViews.removeValue(forKey: tab.id)
        }
        tabs.remove(at: index)
        rebuildSegmentedControl()

        if tabs.isEmpty {
            placeholderLabel.isHidden = false
            segmentedControl.isHidden = true
            containerView.isHidden = true
            selectedIndex = -1
        } else {
            selectTab(at: min(index, tabs.count - 1))
        }
    }

    // MARK: - Private

    private func rebuildSegmentedControl() {
        segmentedControl.segmentCount = tabs.count
        for (i, tab) in tabs.enumerated() {
            segmentedControl.setLabel(tab.label, forSegment: i)
            segmentedControl.setWidth(0, forSegment: i) // auto-size
        }
    }

    private func terminalView(for tab: TabEntry) -> NSView {
        if let existing = terminalViews[tab.id] {
            return existing
        }

        let termView: NSView
        switch tab {
        case .manifestAgent(let agent):
            let pane = TerminalPane(agent: agent, sessionName: ProjectState.shared.sessionName)
            pane.startTmux()
            termView = pane

        case .agentGroup(let agents, let tmuxTarget):
            // All agents share the same tmux window — attach to the window target to show all panes
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
            let pane = TerminalPane(agent: groupAgent, sessionName: ProjectState.shared.sessionName)
            pane.startTmux()
            termView = pane

        case .sessionEntry(let entry):
            if let tmuxTarget = entry.tmuxTarget {
                // Tmux-backed session entry — attach to the tmux pane
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
                let pane = TerminalPane(agent: agentModel, sessionName: ProjectState.shared.sessionName)
                pane.startTmux()
                termView = pane
            } else {
                // Local process fallback (terminals without tmux)
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
            termView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            termView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            termView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            termView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
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

    private func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @objc private func tabClicked(_ sender: NSSegmentedControl) {
        selectTab(at: sender.selectedSegment)
    }
}
