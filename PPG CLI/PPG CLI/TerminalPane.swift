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
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = statusColor(for: agent.status)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        terminalView.wantsLayer = true
        terminalView.layer?.cornerRadius = 8
        terminalView.layer?.cornerCurve = .continuous
        terminalView.layer?.masksToBounds = true
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminalView)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.heightAnchor.constraint(equalToConstant: 20),

            terminalView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    func startTmux() {
        // Hide the tmux status bar in the embedded terminal, then attach
        let cmd = "tmux set-option -t \(agent.tmuxTarget) status off 2>/dev/null; exec tmux attach-session -t \(agent.tmuxTarget)"
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
