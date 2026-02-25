import AppKit
import SwiftTerm

class TerminalPane: NSView {
    let agent: AgentModel
    let sessionName: String
    let label: NSTextField
    let terminalView: ScrollableTerminalView
    private var processStarted = false

    init(agent: AgentModel, sessionName: String) {
        self.agent = agent
        self.sessionName = sessionName
        let displayName = agent.name.isEmpty ? agent.id : agent.name
        self.label = NSTextField(labelWithString: "\(displayName) — \(agent.status.rawValue)")
        self.terminalView = ScrollableTerminalView(frame: .zero)
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = terminalBackground.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.7
        layer?.shadowRadius = 40
        layer?.shadowOffset = .zero

        label.isHidden = true

        terminalView.wantsLayer = true
        terminalView.layer?.masksToBounds = true
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminalView)

        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func layout() {
        super.layout()
        // Inset shadow source on the leading edge so the shadow doesn't bleed
        // into the 8px gap between the sidebar and this pane.
        let r = layer?.shadowRadius ?? 0
        layer?.shadowPath = CGPath(rect: CGRect(x: r, y: 0, width: bounds.width - r, height: bounds.height), transform: nil)

        // Start the tmux process only after the first layout pass gives us a real
        // frame.  Starting earlier (while frame is .zero) causes SwiftTerm to open
        // a 1-column PTY; tmux then rewraps all scrollback to 1 column which is
        // never reflowed even after a later SIGWINCH resize.
        if !processStarted && terminalView.bounds.width > 1 {
            processStarted = true
            startTmux()
        }
    }

    func startTmux() {
        let target = agent.tmuxTarget

        // Parse session name and window spec from the tmux target.
        // Format is typically "session:window" or "session:window.pane".
        let tmuxSession: String
        let windowSpec: String?
        if let colonIdx = target.firstIndex(of: ":") {
            tmuxSession = String(target[..<colonIdx])
            let after = String(target[target.index(after: colonIdx)...])
            windowSpec = after.isEmpty ? nil : after
        } else {
            tmuxSession = target
            windowSpec = nil
        }

        // Use a grouped session so this client gets independent current-window
        // tracking.  Without this, all TerminalPanes sharing the same tmux session
        // would display whichever window was most recently attached — clicking one
        // agent would hijack every other agent's view.
        let viewSession = "\(tmuxSession)-view-\(agent.id)"

        var cmd = "tmux set-option -t \(shellEscape(target)) status off 2>/dev/null; "
        cmd += "exec tmux new-session -t \(shellEscape(tmuxSession)) -s \(shellEscape(viewSession))"
        cmd += " \\; set-option destroy-unattached on"
        cmd += " \\; set-option status off"
        if let win = windowSpec {
            cmd += " \\; select-window -t :\(shellEscape(win))"
        }

        let shellPath = AppSettingsManager.shared.shell
        let shellName = (shellPath as NSString).lastPathComponent
        terminalView.startProcess(
            executable: shellPath,
            args: ["-c", cmd],
            environment: nil,
            execName: shellName
        )
    }

    func updateStatus(_ status: AgentStatus) {
        let displayName = agent.name.isEmpty ? agent.id : agent.name
        label.stringValue = "\(displayName) — \(status.rawValue)"
        label.textColor = statusColor(for: status)
    }

    func terminate() {
        terminalView.process?.terminate()
    }
}
