import AppKit

// MARK: - Split Tree Model

enum SplitDirection {
    case horizontal  // top/bottom
    case vertical    // left/right
}

indirect enum PaneSplitNode {
    case leaf(id: String, entry: TabEntry?)
    case split(direction: SplitDirection, first: PaneSplitNode, second: PaneSplitNode, ratio: CGFloat)

    static let maxLeaves = 6

    var leafCount: Int {
        switch self {
        case .leaf: return 1
        case .split(_, let first, let second, _):
            return first.leafCount + second.leafCount
        }
    }

    func allLeafIds() -> [String] {
        switch self {
        case .leaf(let id, _): return [id]
        case .split(_, let first, let second, _):
            return first.allLeafIds() + second.allLeafIds()
        }
    }

    func findLeaf(id: String) -> PaneSplitNode? {
        switch self {
        case .leaf(let leafId, _):
            return leafId == id ? self : nil
        case .split(_, let first, let second, _):
            return first.findLeaf(id: id) ?? second.findLeaf(id: id)
        }
    }

    func entry(forLeafId id: String) -> TabEntry? {
        switch self {
        case .leaf(let leafId, let entry):
            return leafId == id ? entry : nil
        case .split(_, let first, let second, _):
            return first.entry(forLeafId: id) ?? second.entry(forLeafId: id)
        }
    }

    /// Replace the entry in a specific leaf.
    func settingEntry(_ entry: TabEntry?, forLeafId targetId: String) -> PaneSplitNode {
        switch self {
        case .leaf(let id, _):
            if id == targetId {
                return .leaf(id: id, entry: entry)
            }
            return self
        case .split(let dir, let first, let second, let ratio):
            return .split(
                direction: dir,
                first: first.settingEntry(entry, forLeafId: targetId),
                second: second.settingEntry(entry, forLeafId: targetId),
                ratio: ratio
            )
        }
    }

    /// Split a leaf into two. Returns nil if max leaves would be exceeded or target not found.
    func splittingLeaf(id targetId: String, direction: SplitDirection, newLeafId: String, currentCount: Int) -> PaneSplitNode? {
        guard currentCount < PaneSplitNode.maxLeaves else { return nil }

        switch self {
        case .leaf(let id, let entry):
            guard id == targetId else { return nil }
            return .split(
                direction: direction,
                first: .leaf(id: id, entry: entry),
                second: .leaf(id: newLeafId, entry: nil),
                ratio: 0.5
            )
        case .split(let dir, let first, let second, let ratio):
            if let newFirst = first.splittingLeaf(id: targetId, direction: direction, newLeafId: newLeafId, currentCount: currentCount) {
                return .split(direction: dir, first: newFirst, second: second, ratio: ratio)
            }
            if let newSecond = second.splittingLeaf(id: targetId, direction: direction, newLeafId: newLeafId, currentCount: currentCount) {
                return .split(direction: dir, first: first, second: newSecond, ratio: ratio)
            }
            return nil
        }
    }

    /// Remove a leaf. If this collapses a split, the remaining sibling replaces it.
    func removingLeaf(id targetId: String) -> PaneSplitNode? {
        switch self {
        case .leaf(let id, _):
            return id == targetId ? nil : self
        case .split(_, let first, let second, _):
            let newFirst = first.removingLeaf(id: targetId)
            let newSecond = second.removingLeaf(id: targetId)

            switch (newFirst, newSecond) {
            // Target was in first child, which was removed — collapse to second
            case (nil, let remaining): return remaining
            // Target was in second child, which was removed — collapse to first
            case (let remaining, nil): return remaining
            // Both children still exist — target was not a direct leaf, reconstruct
            case (let f?, let s?):
                // Only reconstruct if something actually changed
                return .split(direction: self.splitDirection!, first: f, second: s, ratio: self.splitRatio!)
            }
        }
    }

    // Helpers for accessing split properties without re-destructuring
    private var splitDirection: SplitDirection? {
        if case .split(let dir, _, _, _) = self { return dir }
        return nil
    }

    private var splitRatio: CGFloat? {
        if case .split(_, _, _, let ratio) = self { return ratio }
        return nil
    }

    /// Convert to a serializable layout node (entry IDs only, no views).
    func toLayoutNode() -> GridLayoutNode {
        switch self {
        case .leaf(_, let entry):
            return .leaf(entryId: entry?.id)
        case .split(let direction, let first, let second, let ratio):
            let dirStr = direction == .horizontal ? "horizontal" : "vertical"
            return .split(direction: dirStr, ratio: ratio, first: first.toLayoutNode(), second: second.toLayoutNode())
        }
    }

    /// Reconstruct from a layout node, generating fresh leaf IDs.
    static func fromLayoutNode(_ node: GridLayoutNode, idGenerator: inout Int) -> PaneSplitNode {
        if node.isLeaf {
            idGenerator += 1
            // Entry will be filled in later by the caller
            return .leaf(id: "pane-\(idGenerator)", entry: nil)
        }
        guard let children = node.children, children.count == 2,
              let dirStr = node.direction else {
            idGenerator += 1
            return .leaf(id: "pane-\(idGenerator)", entry: nil)
        }
        let direction: SplitDirection = dirStr == "horizontal" ? .horizontal : .vertical
        let first = fromLayoutNode(children[0], idGenerator: &idGenerator)
        let second = fromLayoutNode(children[1], idGenerator: &idGenerator)
        return .split(direction: direction, first: first, second: second, ratio: node.ratio ?? 0.5)
    }
}

// MARK: - Pane Grid Controller

class PaneGridController: NSViewController {

    private(set) var root: PaneSplitNode
    private(set) var focusedLeafId: String
    static var leafIdCounter = 0

    /// Caches: leafId -> PaneCellView
    private(set) var cellViews: [String: PaneCellView] = [:]
    /// Caches: re-usable NSSplitViews keyed by a structural path
    private var splitViews: [String: NSSplitView] = [:]

    /// Callbacks
    var onNewAgent: (() -> Void)?
    var onNewTerminal: (() -> Void)?
    var onPickFromSidebar: (() -> Void)?

    /// Terminal creation callback — called when a cell needs a terminal view for an entry.
    var terminalViewProvider: ((TabEntry) -> NSView)?
    /// Terminal termination callback — called to properly terminate a terminal.
    var terminalTerminator: ((NSView) -> Void)?

    /// Called when a pane's split button is clicked. Parameters: leafId, direction.
    var onSplitPane: ((String, SplitDirection) -> Void)?
    /// Called when a pane's close button is clicked. Parameter: leafId.
    var onClosePane: ((String) -> Void)?

    init() {
        let initialId = "pane-0"
        self.root = .leaf(id: initialId, entry: nil)
        self.focusedLeafId = initialId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = terminalBackground.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rebuild()
    }

    // MARK: - Public API

    /// Replace the entire split tree and rebuild the UI. Used for restoring a persisted layout.
    func replaceRoot(_ newRoot: PaneSplitNode) {
        root = newRoot
        focusedLeafId = root.allLeafIds().first ?? focusedLeafId
        rebuild()
    }

    private func nextLeafId() -> String {
        Self.leafIdCounter += 1
        return "pane-\(Self.leafIdCounter)"
    }

    /// Set the entry for the first leaf, reusing an existing terminal view (used when transitioning from single-pane to grid mode).
    func setInitialEntry(_ entry: TabEntry, existingView: NSView?) {
        let firstId = root.allLeafIds().first ?? focusedLeafId
        root = root.settingEntry(entry, forLeafId: firstId)
        if let cell = cellViews[firstId] {
            if let existingView = existingView {
                cell.showEntryWithView(entry, view: existingView)
            } else {
                cell.showEntry(entry, provider: terminalViewProvider)
            }
        }
    }

    /// Fill the focused pane with an entry.
    /// If the entry is already visible in another pane, move focus there instead of duplicating.
    func fillFocusedPane(with entry: TabEntry) {
        // Check if this entry is already visible in another pane — move focus instead of duplicating
        for leafId in root.allLeafIds() {
            if let existing = root.entry(forLeafId: leafId), existing.id == entry.id {
                setFocus(leafId)
                return
            }
        }

        root = root.settingEntry(entry, forLeafId: focusedLeafId)
        if let cell = cellViews[focusedLeafId] {
            cell.showEntry(entry, provider: terminalViewProvider)
        }
    }

    /// Split the focused pane in the given direction.
    @discardableResult
    func splitFocusedPane(direction: SplitDirection) -> Bool {
        let newId = nextLeafId()
        guard let newRoot = root.splittingLeaf(
            id: focusedLeafId,
            direction: direction,
            newLeafId: newId,
            currentCount: root.leafCount
        ) else {
            return false
        }
        root = newRoot
        focusedLeafId = newId
        rebuild()
        return true
    }

    /// Close the focused pane.
    @discardableResult
    func closeFocusedPane() -> Bool {
        // Can't close the last pane
        guard root.leafCount > 1 else { return false }

        let closingId = focusedLeafId

        // Terminate terminal in the closing pane
        if let cell = cellViews[closingId] {
            cell.terminateTerminal(using: terminalTerminator)
        }

        guard let newRoot = root.removingLeaf(id: closingId) else { return false }
        root = newRoot

        // Move focus to first remaining leaf
        focusedLeafId = root.allLeafIds().first ?? ""

        // Remove cell view for the closed pane
        cellViews.removeValue(forKey: closingId)

        rebuild()
        return true
    }

    /// Navigate focus spatially through the split tree.
    /// For a given direction, find the nearest split node matching that axis,
    /// then move to the adjacent sibling's nearest leaf.
    func moveFocus(_ direction: SplitDirection, forward: Bool) {
        guard let targetId = findAdjacentLeaf(from: focusedLeafId, in: root, direction: direction, forward: forward) else {
            return
        }
        setFocus(targetId)
    }

    /// Walk up the tree to find the nearest ancestor split matching the requested axis,
    /// then descend into the opposite child to find the closest leaf.
    private func findAdjacentLeaf(from leafId: String, in node: PaneSplitNode, direction: SplitDirection, forward: Bool) -> String? {
        switch node {
        case .leaf:
            return nil
        case .split(let dir, let first, let second, _):
            let firstIds = Set(first.allLeafIds())
            let secondIds = Set(second.allLeafIds())
            let inFirst = firstIds.contains(leafId)
            let inSecond = secondIds.contains(leafId)

            // Recurse into the child containing the focused leaf first,
            // so nested same-axis splits resolve to the nearest neighbor.
            if inFirst {
                if let result = findAdjacentLeaf(from: leafId, in: first, direction: direction, forward: forward) {
                    return result
                }
            } else if inSecond {
                if let result = findAdjacentLeaf(from: leafId, in: second, direction: direction, forward: forward) {
                    return result
                }
            }

            // If no deeper match, check whether this split matches the navigation axis
            if dir == direction {
                if inFirst && forward {
                    // Move from first child to nearest leaf in second child
                    return second.allLeafIds().first
                } else if inSecond && !forward {
                    // Move from second child to nearest leaf in first child (last leaf = closest)
                    return first.allLeafIds().last
                }
            }

            return nil
        }
    }

    func setFocus(_ leafId: String) {
        guard root.findLeaf(id: leafId) != nil else { return }
        let oldFocused = focusedLeafId
        focusedLeafId = leafId
        cellViews[oldFocused]?.updateFocusBorder(focused: false)
        cellViews[leafId]?.updateFocusBorder(focused: true)
        // Make terminal first responder
        cellViews[leafId]?.makeTerminalFirstResponder()
    }

    /// Check if any leaf has a given entry ID.
    func containsEntry(id: String) -> Bool {
        for leafId in root.allLeafIds() {
            if let entry = root.entry(forLeafId: leafId), entry.id == id {
                return true
            }
        }
        return false
    }

    /// Update the status on a visible agent terminal.
    func updateEntry(_ entry: TabEntry) {
        for leafId in root.allLeafIds() {
            if let existing = root.entry(forLeafId: leafId), existing.id == entry.id {
                root = root.settingEntry(entry, forLeafId: leafId)
                cellViews[leafId]?.updateStatus(entry)
                break
            }
        }
    }

    /// Get the entry currently in the focused pane.
    var focusedEntry: TabEntry? {
        root.entry(forLeafId: focusedLeafId)
    }

    /// Terminate all terminal views except the one in the given leaf.
    func terminateAllExcept(leafId: String, using terminator: @escaping (NSView) -> Void) {
        for id in root.allLeafIds() where id != leafId {
            cellViews[id]?.terminateTerminal(using: terminator)
        }
    }

    // MARK: - Rebuild UI

    func rebuild() {
        // Detach cell views from their parents (but preserve their terminal state).
        // PaneCellViews are reused — only the NSSplitView wrappers are recreated.
        for (_, cell) in cellViews {
            cell.removeFromSuperview()
        }
        for sub in view.subviews {
            sub.removeFromSuperview()
        }

        // Clear old split view cache (cells are reused by buildView via cellView(for:))
        splitViews.removeAll()

        // Prune cell views for leaves that no longer exist in the tree
        let activeIds = Set(root.allLeafIds())
        for id in cellViews.keys where !activeIds.contains(id) {
            cellViews.removeValue(forKey: id)
        }

        let builtView = buildView(for: root, path: "root")
        builtView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(builtView)
        NSLayoutConstraint.activate([
            builtView.topAnchor.constraint(equalTo: view.topAnchor),
            builtView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            builtView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            builtView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Update focus borders
        for (id, cell) in cellViews {
            cell.updateFocusBorder(focused: id == focusedLeafId)
        }
    }

    private func buildView(for node: PaneSplitNode, path: String) -> NSView {
        switch node {
        case .leaf(let id, let entry):
            let cell = cellView(for: id)
            if let entry = entry {
                cell.showEntry(entry, provider: terminalViewProvider)
            } else {
                cell.showPlaceholder(
                    onNewAgent: { [weak self] in self?.onNewAgent?() },
                    onNewTerminal: { [weak self] in self?.onNewTerminal?() },
                    onPickFromSidebar: { [weak self] in self?.onPickFromSidebar?() }
                )
            }
            cell.onClick = { [weak self] in
                self?.setFocus(id)
            }
            cell.onSplitHorizontal = { [weak self] in
                self?.onSplitPane?(id, .horizontal)
            }
            cell.onSplitVertical = { [weak self] in
                self?.onSplitPane?(id, .vertical)
            }
            cell.onClose = { [weak self] in
                self?.onClosePane?(id)
            }
            return cell

        case .split(let direction, let first, let second, let ratio):
            let splitView = NSSplitView()
            splitView.isVertical = (direction == .vertical)
            splitView.dividerStyle = .thin
            splitView.translatesAutoresizingMaskIntoConstraints = false
            splitView.wantsLayer = true

            let firstView = buildView(for: first, path: path + ".0")
            let secondView = buildView(for: second, path: path + ".1")

            splitView.addSubview(firstView)
            splitView.addSubview(secondView)

            let delegate = SplitViewDelegate()
            splitView.delegate = delegate
            // Store delegate to prevent deallocation
            objc_setAssociatedObject(splitView, &splitViewDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

            splitViews[path] = splitView

            // Set initial ratio after layout
            DispatchQueue.main.async { [weak self] in
                self?.applySplitRatio(splitView, ratio: ratio)
            }

            return splitView
        }
    }

    private func applySplitRatio(_ splitView: NSSplitView, ratio: CGFloat) {
        guard splitView.subviews.count == 2 else { return }
        let totalSize = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        let dividerThickness = splitView.dividerThickness
        let firstSize = (totalSize - dividerThickness) * ratio
        splitView.setPosition(firstSize, ofDividerAt: 0)
    }

    private func cellView(for leafId: String) -> PaneCellView {
        if let existing = cellViews[leafId] {
            return existing
        }
        let cell = PaneCellView(leafId: leafId)
        cellViews[leafId] = cell
        return cell
    }
}

// MARK: - Associated Object Key

private var splitViewDelegateKey: UInt8 = 0

// MARK: - Split View Delegate

private class SplitViewDelegate: NSObject, NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return max(proposedMinimumPosition, 100)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let totalSize = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        return min(proposedMaximumPosition, totalSize - 100)
    }

    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        return true
    }
}

// MARK: - Pane Cell View

class PaneCellView: NSView {
    let leafId: String
    private var currentTerminalView: NSView?
    private var placeholderView: PanePlaceholderView?
    private var entryId: String?
    var onClick: (() -> Void)?
    var onSplitHorizontal: (() -> Void)?
    var onSplitVertical: (() -> Void)?
    var onClose: (() -> Void)?

    private let focusBorderLayer = CALayer()
    private static let focusBorderWidth: CGFloat = 2
    private static let focusBorderColor = NSColor.controlAccentColor

    private var hoverOverlay: PaneHoverOverlay?
    private var trackingArea: NSTrackingArea?
    private var fadeOutWork: DispatchWorkItem?

    init(leafId: String) {
        self.leafId = leafId
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = terminalBackground.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        // Focus border layer — zPosition keeps it above terminal subviews
        focusBorderLayer.borderWidth = 0
        focusBorderLayer.borderColor = Self.focusBorderColor.cgColor
        focusBorderLayer.cornerRadius = 2
        focusBorderLayer.zPosition = 1000
        layer?.addSublayer(focusBorderLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func layout() {
        super.layout()
        focusBorderLayer.frame = bounds
        hoverOverlay?.updatePosition(in: bounds)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        fadeOutWork?.cancel()
        showHoverOverlay()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        scheduleFadeOut()
    }

    private func showHoverOverlay() {
        // Only show overlay when there's content (not placeholder)
        guard entryId != nil else { return }

        if hoverOverlay == nil {
            let overlay = PaneHoverOverlay()
            overlay.onSplitHorizontal = { [weak self] in self?.onSplitHorizontal?() }
            overlay.onSplitVertical = { [weak self] in self?.onSplitVertical?() }
            overlay.onClose = { [weak self] in self?.onClose?() }
            addSubview(overlay)
            overlay.updatePosition(in: bounds)
            hoverOverlay = overlay
        }
        hoverOverlay?.animator().alphaValue = 1
    }

    private func scheduleFadeOut() {
        fadeOutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self?.hoverOverlay?.animator().alphaValue = 0
            }
        }
        fadeOutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
        super.mouseDown(with: event)
    }

    func updateFocusBorder(focused: Bool) {
        focusBorderLayer.borderWidth = focused ? Self.focusBorderWidth : 0
    }

    func makeTerminalFirstResponder() {
        if let termView = currentTerminalView {
            window?.makeFirstResponder(termView)
        }
    }

    func showEntry(_ entry: TabEntry, provider: ((TabEntry) -> NSView)?) {
        // Remove placeholder if present
        placeholderView?.removeFromSuperview()
        placeholderView = nil

        // If already showing this entry, no-op
        if entryId == entry.id { return }

        // Remove old terminal view
        currentTerminalView?.removeFromSuperview()
        currentTerminalView = nil
        entryId = entry.id

        guard let provider = provider else { return }
        let termView = provider(entry)
        installTerminalView(termView)
    }

    /// Install an already-created terminal view directly (avoids re-creating via provider).
    func showEntryWithView(_ entry: TabEntry, view termView: NSView) {
        placeholderView?.removeFromSuperview()
        placeholderView = nil

        if entryId == entry.id { return }

        currentTerminalView?.removeFromSuperview()
        currentTerminalView = nil
        entryId = entry.id

        // Detach from previous parent if needed
        termView.removeFromSuperview()
        installTerminalView(termView)
    }

    private func installTerminalView(_ termView: NSView) {
        termView.isHidden = false
        termView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(termView)

        // TerminalPane has its own 8px leading inset; other views need it from the cell.
        let leadingPadding: CGFloat = (termView is TerminalPane) ? 0 : 8
        NSLayoutConstraint.activate([
            termView.topAnchor.constraint(equalTo: topAnchor),
            termView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingPadding),
            termView.trailingAnchor.constraint(equalTo: trailingAnchor),
            termView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        currentTerminalView = termView
    }

    func showPlaceholder(
        onNewAgent: @escaping () -> Void,
        onNewTerminal: @escaping () -> Void,
        onPickFromSidebar: @escaping () -> Void
    ) {
        currentTerminalView?.removeFromSuperview()
        currentTerminalView = nil
        entryId = nil

        if placeholderView == nil {
            placeholderView = PanePlaceholderView()
        }
        guard let placeholder = placeholderView else { return }

        placeholder.onNewAgent = onNewAgent
        placeholder.onNewTerminal = onNewTerminal
        placeholder.onPickFromSidebar = onPickFromSidebar

        if placeholder.superview != self {
            placeholder.removeFromSuperview()
            placeholder.translatesAutoresizingMaskIntoConstraints = false
            addSubview(placeholder)
            NSLayoutConstraint.activate([
                placeholder.topAnchor.constraint(equalTo: topAnchor),
                placeholder.leadingAnchor.constraint(equalTo: leadingAnchor),
                placeholder.trailingAnchor.constraint(equalTo: trailingAnchor),
                placeholder.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    func updateStatus(_ entry: TabEntry) {
        guard let pane = currentTerminalView as? TerminalPane else { return }
        switch entry {
        case .manifestAgent(let agent, _):
            pane.updateStatus(agent.status)
        case .agentGroup(let agents, _, _):
            pane.updateStatus(agents.first?.status ?? .lost)
        case .sessionEntry:
            break
        }
    }

    /// Detach and return the current terminal view without terminating it.
    func detachTerminalView() -> NSView? {
        guard let termView = currentTerminalView else { return nil }
        termView.removeFromSuperview()
        currentTerminalView = nil
        entryId = nil
        return termView
    }

    func terminateTerminal(using terminator: ((NSView) -> Void)?) {
        guard let termView = currentTerminalView else { return }
        terminator?(termView)
        termView.removeFromSuperview()
        currentTerminalView = nil
        entryId = nil
    }
}

// MARK: - Pane Hover Overlay

class PaneHoverOverlay: NSView {
    var onSplitHorizontal: (() -> Void)?
    var onSplitVertical: (() -> Void)?
    var onClose: (() -> Void)?

    private static let buttonSize: CGFloat = 24
    private static let padding: CGFloat = 6
    private static let spacing: CGFloat = 2

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupButtons()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func setupButtons() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.85).cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 0.3, alpha: 0.5).cgColor

        let splitH = makeButton(
            icon: "rectangle.split.1x2",
            tooltip: "Split Below",
            action: #selector(splitHClicked)
        )
        let splitV = makeButton(
            icon: "rectangle.split.2x1",
            tooltip: "Split Right",
            action: #selector(splitVClicked)
        )
        let close = makeButton(
            icon: "xmark",
            tooltip: "Close Pane",
            action: #selector(closeClicked)
        )

        let stack = NSStackView(views: [splitV, splitH, close])
        stack.orientation = .horizontal
        stack.spacing = Self.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.padding),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.padding),
        ])

        translatesAutoresizingMaskIntoConstraints = false
    }

    private func makeButton(icon: String, tooltip: String, action: Selector) -> NSButton {
        let btn = NSButton()
        btn.bezelStyle = .accessoryBarAction
        btn.isBordered = false
        btn.image = NSImage(systemSymbolName: icon, accessibilityDescription: tooltip)
        btn.imagePosition = .imageOnly
        btn.imageScaling = .scaleProportionallyDown
        btn.contentTintColor = NSColor(white: 0.85, alpha: 1)
        btn.toolTip = tooltip
        btn.target = self
        btn.action = action
        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            btn.heightAnchor.constraint(equalToConstant: Self.buttonSize),
        ])
        return btn
    }

    func updatePosition(in parentBounds: CGRect) {
        guard superview != nil else { return }
        let overlayWidth = Self.padding * 2 + Self.buttonSize * 3 + Self.spacing * 2
        let overlayHeight = Self.padding * 2 + Self.buttonSize
        frame = NSRect(
            x: parentBounds.maxX - overlayWidth - 8,
            y: parentBounds.maxY - overlayHeight - 8,
            width: overlayWidth,
            height: overlayHeight
        )
    }

    // Prevent mouse events on the overlay from falling through to the terminal
    override func mouseDown(with event: NSEvent) {
        // no-op — absorb click
    }

    @objc private func splitHClicked() { onSplitHorizontal?() }
    @objc private func splitVClicked() { onSplitVertical?() }
    @objc private func closeClicked() { onClose?() }
}

// MARK: - Pane Placeholder View

class PanePlaceholderView: NSView {
    var onNewAgent: (() -> Void)?
    var onNewTerminal: (() -> Void)?
    var onPickFromSidebar: (() -> Void)?

    private let stackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = terminalBackground.cgColor

        let titleLabel = NSTextField(labelWithString: "New Pane")
        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        titleLabel.textColor = terminalForeground
        titleLabel.alignment = .center

        let subtitleLabel = NSTextField(labelWithString: "Choose what to display")
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center

        let agentButton = makeButton(title: "New Agent", icon: "cpu", action: #selector(agentClicked))
        let terminalButton = makeButton(title: "New Terminal", icon: "terminal", action: #selector(terminalClicked))
        let sidebarButton = makeButton(title: "Pick from Sidebar", icon: "sidebar.left", action: #selector(sidebarClicked))

        let buttonStack = NSStackView(views: [agentButton, terminalButton, sidebarButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 12

        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 12
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)

        // Add a spacer
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 4).isActive = true
        stackView.addArrangedSubview(spacer)

        stackView.addArrangedSubview(buttonStack)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func makeButton(title: String, icon: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
        button.title = title
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 12)
        button.contentTintColor = terminalForeground
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    @objc private func agentClicked() { onNewAgent?() }
    @objc private func terminalClicked() { onNewTerminal?() }
    @objc private func sidebarClicked() { onPickFromSidebar?() }
}
