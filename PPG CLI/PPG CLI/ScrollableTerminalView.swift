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
        applyTerminalTheme(forceRefresh: false)

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
            guard let self,
                  let key = notification.userInfo?[AppSettingsManager.changedKeyUserInfoKey] as? AppSettingsKey else { return }
            switch key {
            case .terminalFont, .terminalFontSize:
                self.applyFont()
            case .appearanceMode:
                // Run on next cycle to ensure the window/view effectiveAppearance is already updated.
                DispatchQueue.main.async { [weak self] in
                    self?.applyTerminalTheme(forceRefresh: true)
                }
            default:
                break
            }
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleScrollEvent(event)
        }

        // Accept file drops — sends shell-escaped paths to the terminal PTY
        registerForDraggedTypes([.fileURL])
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTerminalTheme(forceRefresh: true)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyTerminalTheme(forceRefresh: true)
    }

    private func applyTerminalTheme(forceRefresh: Bool) {
        let appearance = window?.effectiveAppearance ?? NSApp.appearance ?? effectiveAppearance
        let resolvedBackground = Theme.terminalBackground.resolvedColor(for: appearance)
        let resolvedForeground = Theme.terminalForeground.resolvedColor(for: appearance)
        let term = terminalView.getTerminal()

        // Keep the terminal engine's default colors in sync with native colors so
        // OSC 10/11 queries (used by TUIs like Codex) report the active theme.
        term.backgroundColor = makeTerminalColor(from: resolvedBackground)
        term.foregroundColor = makeTerminalColor(from: resolvedForeground)

        terminalView.nativeBackgroundColor = resolvedBackground
        terminalView.nativeForegroundColor = resolvedForeground
        terminalView.installColors(ansiPalette(for: appearance))
        terminalView.layer?.backgroundColor = resolvedBackground.cgColor
        layer?.backgroundColor = resolvedBackground.cgColor

        guard forceRefresh else { return }

        // SwiftTerm caches attributes per color/font; invalidate and repaint all rows.
        terminalView.colorChanged(source: term, idx: nil)
        term.refresh(startRow: 0, endRow: term.rows)
        terminalView.needsDisplay = true
        terminalView.font = terminalView.font
    }

    private func ansiPalette(for appearance: NSAppearance) -> [SwiftTerm.Color] {
        let isDark = appearance.isDark
        let palette: [(CGFloat, CGFloat, CGFloat)] = isDark ? [
            (0.11, 0.11, 0.12), // 0 black
            (0.78, 0.35, 0.35), // 1 red
            (0.43, 0.68, 0.47), // 2 green
            (0.79, 0.67, 0.40), // 3 yellow
            (0.43, 0.61, 0.90), // 4 blue
            (0.72, 0.53, 0.86), // 5 magenta
            (0.39, 0.72, 0.78), // 6 cyan
            (0.68, 0.68, 0.70), // 7 white
            (0.34, 0.35, 0.37), // 8 bright black
            (0.89, 0.48, 0.48), // 9 bright red
            (0.55, 0.84, 0.60), // 10 bright green
            (0.90, 0.78, 0.50), // 11 bright yellow
            (0.54, 0.70, 0.94), // 12 bright blue
            (0.80, 0.63, 0.91), // 13 bright magenta
            (0.49, 0.79, 0.84), // 14 bright cyan
            (0.94, 0.94, 0.95), // 15 bright white
        ] : [
            (0.17, 0.17, 0.18), // 0 black
            (0.71, 0.23, 0.23), // 1 red
            (0.18, 0.49, 0.20), // 2 green
            (0.55, 0.43, 0.12), // 3 yellow
            (0.18, 0.37, 0.69), // 4 blue
            (0.48, 0.25, 0.64), // 5 magenta
            (0.12, 0.44, 0.52), // 6 cyan
            (0.87, 0.86, 0.82), // 7 white
            (0.43, 0.43, 0.45), // 8 bright black
            (0.82, 0.31, 0.31), // 9 bright red
            (0.25, 0.58, 0.30), // 10 bright green
            (0.64, 0.52, 0.18), // 11 bright yellow
            (0.25, 0.47, 0.78), // 12 bright blue
            (0.58, 0.35, 0.75), // 13 bright magenta
            (0.20, 0.54, 0.63), // 14 bright cyan
            (0.99, 0.99, 0.99), // 15 bright white
        ]

        return palette.map { makeTerminalColor(red: $0.0, green: $0.1, blue: $0.2) }
    }

    private func makeTerminalColor(red: CGFloat, green: CGFloat, blue: CGFloat) -> SwiftTerm.Color {
        let r = UInt16((max(0, min(1, red)) * 65535).rounded())
        let g = UInt16((max(0, min(1, green)) * 65535).rounded())
        let b = UInt16((max(0, min(1, blue)) * 65535).rounded())
        return SwiftTerm.Color(red: r, green: g, blue: b)
    }

    private func makeTerminalColor(from color: NSColor) -> SwiftTerm.Color {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return makeTerminalColor(red: r, green: g, blue: b)
    }

    // MARK: - Drag & Drop (file paths into terminal)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else {
            return []
        }
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderWidth = 0
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderWidth = 0

        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else {
            return false
        }

        let escaped = urls.map { shellEscapedPath($0.path) }.joined(separator: " ")
        terminalView.send(txt: escaped)
        return true
    }

    private func shellEscapedPath(_ path: String) -> String {
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Scroll Interception

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
