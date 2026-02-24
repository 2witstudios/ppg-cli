import AppKit
import SwiftTerm

/// Wraps a `LocalProcessTerminalView` and intercepts scroll-wheel events to forward
/// them as mouse wheel escape sequences when the alternate screen buffer is active.
///
/// Without this, SwiftTerm's `scrollWheel` silently drops scroll events on the
/// alternate buffer (tmux, vim, less, etc.) because `canScroll` returns false when
/// `isCurrentBufferAlternate`. The scroll event is swallowed and never forwarded.
///
/// We use `NSEvent.addLocalMonitorForEvents` to intercept scroll events before they
/// reach SwiftTerm's non-overridable `scrollWheel`. When tmux-style forwarding is
/// needed, we encode the scroll as mouse button 4/5 and send via the terminal's
/// mouse protocol. Otherwise we let the event pass through to SwiftTerm normally.
class ScrollableTerminalView: NSView {
    let terminalView: LocalProcessTerminalView
    private var scrollMonitor: Any?
    private var lastScrollTime: CFTimeInterval = 0

    init(frame: NSRect, terminalView: LocalProcessTerminalView? = nil) {
        self.terminalView = terminalView ?? LocalProcessTerminalView(frame: frame)
        super.init(frame: frame)

        // Harmonize terminal background with UI chrome (replaces pure black default)
        self.terminalView.nativeBackgroundColor = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 0.7)
        self.terminalView.nativeForegroundColor = NSColor(srgbRed: 0.85, green: 0.85, blue: 0.87, alpha: 1.0)
        self.terminalView.layer?.backgroundColor = self.terminalView.nativeBackgroundColor.cgColor

        self.terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(self.terminalView)
        NSLayoutConstraint.activate([
            self.terminalView.topAnchor.constraint(equalTo: topAnchor),
            self.terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            self.terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            self.terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleScrollEvent(event)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
    }

    // Forward process management to the inner terminal view
    var process: LocalProcess? { terminalView.process }

    func startProcess(executable: String, args: [String], environment: [String]?, execName: String?) {
        terminalView.startProcess(executable: executable, args: args, environment: environment, execName: execName)
    }

    // Forward appearance properties
    var allowMouseReporting: Bool {
        get { terminalView.allowMouseReporting }
        set { terminalView.allowMouseReporting = newValue }
    }

    private func handleScrollEvent(_ event: NSEvent) -> NSEvent? {
        // Only intercept events targeting our inner terminal view
        guard let targetView = event.window?.contentView?.hitTest(event.locationInWindow),
              targetView === terminalView || targetView.isDescendant(of: terminalView) else {
            return event
        }

        let term = terminalView.getTerminal()

        // Only intercept when: mouse reporting is on, mouse mode is active,
        // and we're on the alternate screen buffer (i.e. tmux/vim/less).
        guard terminalView.allowMouseReporting,
              term.mouseMode != .off,
              term.isCurrentBufferAlternate else {
            // Let SwiftTerm handle it (normal scrollback)
            return event
        }

        // Filter out tiny deltas and throttle to ~20 events/sec max
        let delta = event.scrollingDeltaY
        guard abs(delta) > 1.0 else { return nil }

        let now = CACurrentMediaTime()
        guard now - lastScrollTime > 0.05 else { return nil }
        lastScrollTime = now

        let isUp = delta > 0
        // Mouse button 4 = scroll up, button 5 = scroll down
        let button = isUp ? 4 : 5
        let flags = term.encodeButton(button: button, release: false, shift: false, meta: false, control: false)

        // Compute the grid cell position from the event location
        let localPoint = terminalView.convert(event.locationInWindow, from: nil)
        let cellWidth = terminalView.bounds.width / CGFloat(term.cols)
        let cellHeight = terminalView.bounds.height / CGFloat(term.rows)
        let x = max(0, min(Int(localPoint.x / cellWidth), term.cols - 1))
        // NSView coordinates have origin at bottom-left; convert to top-left for terminal grid
        let y = max(0, min(Int((terminalView.bounds.height - localPoint.y) / cellHeight), term.rows - 1))

        // One scroll event per wheel tick — tmux accumulates naturally
        term.sendEvent(buttonFlags: flags, x: x, y: y)

        // Consume the event — don't let SwiftTerm's scrollWheel see it
        return nil
    }
}
