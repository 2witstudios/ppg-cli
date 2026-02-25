import AppKit
import SwiftTerm

class TerminalPane: NSView {
    let agent: AgentModel
    let sessionName: String
    let label: NSTextField
    /// Lazily created — nil until the pane is actually visible in a window.
    private(set) var terminalView: ScrollableTerminalView?
    private var processStarted = false
    private var terminalInstalled = false

    init(agent: AgentModel, sessionName: String) {
        self.agent = agent
        self.sessionName = sessionName
        let displayName = agent.name.isEmpty ? agent.id : agent.name
        self.label = NSTextField(labelWithString: "\(displayName) — \(agent.status.rawValue)")
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
    }

    /// Create and install the terminal view on demand (first time only).
    private func ensureTerminalView() {
        guard !terminalInstalled else { return }
        terminalInstalled = true

        let tv = ScrollableTerminalView(frame: bounds)
        tv.wantsLayer = true
        tv.layer?.masksToBounds = true
        tv.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tv)

        NSLayoutConstraint.activate([
            tv.topAnchor.constraint(equalTo: topAnchor),
            tv.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            tv.trailingAnchor.constraint(equalTo: trailingAnchor),
            tv.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        terminalView = tv
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Create the terminal view only when we're actually in a window.
        if window != nil && !terminalInstalled {
            ensureTerminalView()
        }
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
        if let tv = terminalView, !processStarted && tv.bounds.width > 1 {
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
        // Suffix with a short random ID to avoid session name collisions on fast
        // re-selection after LRU eviction (the old view session may still be dying).
        let suffix = String((0..<4).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        let viewSession = "\(tmuxSession)-view-\(agent.id)-\(suffix)"

        // Source shell profiles so tmux is found on M-series Macs where
        // /opt/homebrew/bin is not in the default GUI app PATH.
        var cmd = "if [ -x /usr/libexec/path_helper ]; then eval $(/usr/libexec/path_helper -s); fi; "
        cmd += "[ -f ~/.zprofile ] && source ~/.zprofile; "
        cmd += "[ -f ~/.zshrc ] && source ~/.zshrc; "
        cmd += "tmux set-option -t \(shellEscape(target)) status off 2>/dev/null; "
        cmd += "exec tmux new-session -t \(shellEscape(tmuxSession)) -s \(shellEscape(viewSession))"
        cmd += " \\; set-option destroy-unattached on"
        cmd += " \\; set-option status off"
        if let win = windowSpec {
            cmd += " \\; select-window -t :\(shellEscape(win))"
        }

        terminalView?.startProcess(
            executable: "/bin/zsh",
            args: ["-c", cmd],
            environment: nil,
            execName: "zsh"
        )
    }

    func updateStatus(_ status: AgentStatus) {
        let displayName = agent.name.isEmpty ? agent.id : agent.name
        label.stringValue = "\(displayName) — \(status.rawValue)"
        label.textColor = statusColor(for: status)
    }

    /// Explicit cleanup — tears down the terminal view (timer, monitor, process).
    /// Safe to call multiple times.
    func tearDown() {
        terminalView?.tearDown()
    }

    func terminate() {
        tearDown()
    }
}
