import AppKit
import SwiftTerm

class TerminalPane: NSView {
    let agent: AgentModel
    let sessionName: String
    let label: NSTextField
    let terminalView: ScrollableTerminalView

    init(agent: AgentModel, sessionName: String) {
        self.agent = agent
        self.sessionName = sessionName
        self.label = NSTextField(labelWithString: "\(agent.id) — \(agent.status.rawValue)")
        self.terminalView = ScrollableTerminalView(frame: .zero)
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.7
        layer?.shadowRadius = 40
        layer?.shadowOffset = .zero

        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = statusColor(for: agent.status)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        terminalView.wantsLayer = true
        terminalView.layer?.masksToBounds = true
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminalView)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.heightAnchor.constraint(equalToConstant: 20),

            terminalView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func startTmux() {
        // Hide the tmux status bar in the embedded terminal, then attach
        let escaped = shellEscape(agent.tmuxTarget)
        let cmd = "tmux set-option -t \(escaped) status off 2>/dev/null; exec tmux attach-session -t \(escaped)"
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
