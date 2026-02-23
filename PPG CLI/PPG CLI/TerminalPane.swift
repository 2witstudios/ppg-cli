import AppKit
import SwiftTerm

class TerminalPane: NSView {
    let agent: AgentModel
    let sessionName: String
    let label: NSTextField
    let terminalView: LocalProcessTerminalView

    init(agent: AgentModel, sessionName: String) {
        self.agent = agent
        self.sessionName = sessionName
        self.label = NSTextField(labelWithString: "\(agent.id) — \(agent.status.rawValue)")
        self.terminalView = LocalProcessTerminalView(frame: .zero)
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        label.textColor = statusColor(for: agent.status)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminalView)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.heightAnchor.constraint(equalToConstant: 22),

            terminalView.topAnchor.constraint(equalTo: label.bottomAnchor),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func startTmux() {
        // With one window per agent, no zoom needed — just attach directly
        let cmd = "exec tmux attach-session -t \(agent.tmuxTarget)"
        terminalView.startProcess(
            executable: "/bin/zsh",
            args: ["-c", cmd],
            environment: nil,
            execName: "zsh"
        )
    }

    func updateStatus(_ status: AgentStatus) {
        label.stringValue = "\(agent.id) — \(status.rawValue)"
        label.textColor = statusColor(for: status)
    }

    func terminate() {
        terminalView.process?.terminate()
    }
}
