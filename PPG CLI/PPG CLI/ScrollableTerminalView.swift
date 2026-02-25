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
    private var settingsObserver: NSObjectProtocol?

    /// Accumulated scroll delta since last frame flush.
    private var accumulatedDelta: CGFloat = 0
    /// Track last scroll direction so we can flush on reversal.
    private var lastScrollDirection: Bool?  // true = up, false = down
    /// Last event location (for computing terminal grid position).
    private var lastScrollLocation: NSPoint = .zero
    /// Display-linked timer that flushes accumulated scroll at screen refresh rate.
    private var scrollFlushTimer: DispatchSourceTimer?
    /// Whether tearDown() has been called.
    private var tornDown = false
    /// Approximate pixels of trackpad scroll delta per terminal scroll tick.
    private static let pixelsPerScrollTick: CGFloat = 30

    init(frame: NSRect, terminalView: LocalProcessTerminalView? = nil) {
        self.terminalView = terminalView ?? LocalProcessTerminalView(frame: frame)
        super.init(frame: frame)

        // Harmonize terminal background with UI chrome (replaces pure black default)
        self.terminalView.nativeBackgroundColor = terminalBackground
        self.terminalView.nativeForegroundColor = terminalForeground
        self.terminalView.layer?.backgroundColor = terminalBackground.cgColor

        self.terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(self.terminalView)
        NSLayoutConstraint.activate([
            self.terminalView.topAnchor.constraint(equalTo: topAnchor),
            self.terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            self.terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            self.terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Apply configured font
        applyFont()

        // Disable mouse reporting so click/drag does native text selection.
        // Scroll-wheel forwarding to tmux is handled separately by handleScrollEvent.
        self.terminalView.allowMouseReporting = false

        // Live-update font when font settings change
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .appSettingsDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            guard let key = notification.userInfo?[AppSettingsManager.changedKeyUserInfoKey] as? AppSettingsKey,
                  key == .terminalFont || key == .terminalFontSize else { return }
            self?.applyFont()
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleScrollEvent(event)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        tearDown()
    }

    /// Explicit cleanup — cancels timer, removes scroll monitor, terminates process.
    /// Safe to call multiple times.
    func tearDown() {
        guard !tornDown else { return }
        tornDown = true
        scrollFlushTimer?.cancel()
        scrollFlushTimer = nil
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        terminalView.process?.terminate()
    }

    private func applyFont() {
        let name = AppSettingsManager.shared.terminalFontName
        let size = AppSettingsManager.shared.terminalFontSize
        if let font = NSFont(name: name, size: size) {
            terminalView.font = font
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

        // Only intercept when: mouse mode is active and we're on the alternate
        // screen buffer (i.e. tmux/vim/less). allowMouseReporting is off for
        // native text selection, but we still forward scroll events here.
        guard term.mouseMode != .off,
              term.isCurrentBufferAlternate else {
            // Let SwiftTerm handle it (normal scrollback)
            return event
        }

        // Filter out sub-pixel noise
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.5 else { return nil }

        // Flush immediately if scroll direction reverses to avoid eating input
        let isUp = delta > 0
        if let lastDir = lastScrollDirection, lastDir != isUp, abs(accumulatedDelta) > 0.5 {
            flushScrollDelta()
        }
        lastScrollDirection = isUp

        // Accumulate delta and record position; flush on next frame tick
        accumulatedDelta += delta
        lastScrollLocation = event.locationInWindow
        startScrollFlushTimerIfNeeded()

        // Consume the event — don't let SwiftTerm's scrollWheel see it
        return nil
    }

    /// Start a display-rate timer (~16ms) to batch accumulated scroll deltas into
    /// a single escape sequence per frame. The timer auto-cancels when idle.
    private func startScrollFlushTimerIfNeeded() {
        guard scrollFlushTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(16), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            self?.flushScrollDelta()
        }
        timer.resume()
        scrollFlushTimer = timer
    }

    private func flushScrollDelta() {
        let delta = accumulatedDelta
        guard abs(delta) > 0.5 else {
            // No accumulated scroll — stop the timer to save CPU
            scrollFlushTimer?.cancel()
            scrollFlushTimer = nil
            lastScrollDirection = nil
            return
        }

        accumulatedDelta = 0

        let term = terminalView.getTerminal()
        guard term.mouseMode != .off, term.isCurrentBufferAlternate else {
            scrollFlushTimer?.cancel()
            scrollFlushTimer = nil
            lastScrollDirection = nil
            return
        }

        let isUp = delta > 0
        let button = isUp ? 4 : 5
        let flags = term.encodeButton(button: button, release: false, shift: false, meta: false, control: false)

        // Compute grid position from the last event location
        let localPoint = terminalView.convert(lastScrollLocation, from: nil)
        let cellWidth = terminalView.bounds.width / CGFloat(term.cols)
        let cellHeight = terminalView.bounds.height / CGFloat(term.rows)
        let x = max(0, min(Int(localPoint.x / cellWidth), term.cols - 1))
        let y = max(0, min(Int((terminalView.bounds.height - localPoint.y) / cellHeight), term.rows - 1))

        // Send proportional number of scroll events based on accumulated delta.
        // This preserves scroll speed while batching to one frame.
        let ticks = max(1, Int(abs(delta) / Self.pixelsPerScrollTick))
        for _ in 0..<ticks {
            term.sendEvent(buttonFlags: flags, x: x, y: y)
        }
    }
}
