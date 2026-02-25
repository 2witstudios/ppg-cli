import AppKit

// MARK: - CommandPalettePanel

class CommandPalettePanel: NSPanel {
    var onDismiss: (() -> Void)?

    private var localMouseMonitor: Any?

    override var canBecomeKey: Bool { true }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 380),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let vc = CommandPaletteViewController()
        contentViewController = vc
    }

    func showRelativeTo(window: NSWindow?) {
        guard let parentWindow = window else { return }

        let parentFrame = parentWindow.frame
        let panelSize = frame.size
        let x = parentFrame.midX - panelSize.width / 2
        let y = parentFrame.midY - panelSize.height / 2 + 60
        setFrameOrigin(NSPoint(x: x, y: y))

        parentWindow.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)

        // Dismiss on click outside
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            if event.window !== self {
                self.dismiss()
                return nil
            }
            return event
        }
    }

    func dismiss() {
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
        parent?.removeChildWindow(self)
        orderOut(nil)
        onDismiss?()
    }

    override func cancelOperation(_ sender: Any?) {
        guard let vc = contentViewController as? CommandPaletteViewController else {
            dismiss()
            return
        }
        vc.handleEscape()
    }

    @discardableResult
    static func show(relativeTo window: NSWindow?, onSelect: @escaping (AgentVariant, String?) -> Void) -> CommandPalettePanel {
        let panel = CommandPalettePanel()
        guard let vc = panel.contentViewController as? CommandPaletteViewController else {
            return panel
        }
        vc.onSelect = { variant, prompt in
            panel.dismiss()
            onSelect(variant, prompt)
        }
        vc.onDismiss = {
            panel.dismiss()
        }
        panel.showRelativeTo(window: window)
        return panel
    }
}

// MARK: - CommandPaletteViewController

class CommandPaletteViewController: NSViewController, NSTextFieldDelegate {

    var onSelect: ((AgentVariant, String?) -> Void)?
    var onDismiss: (() -> Void)?

    private enum Phase {
        case selection
        case prompt(AgentVariant)
    }

    private var phase: Phase = .selection

    // Phase 1 — Selection
    private let searchField = NSTextField()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var filteredVariants: [AgentVariant] = AgentVariant.allVariants
    private var selectedIndex = 0

    // Phase 2 — Prompt
    private let promptHeader = NSStackView()
    private let promptHeaderIcon = NSImageView()
    private let promptHeaderLabel = NSTextField(labelWithString: "")
    private let promptField = NSTextField()
    private let promptHint = NSTextField(labelWithString: "Enter to submit")

    // Shared
    private let containerView = NSView()
    private let separatorView = NSBox()

    // Colors
    private let bgColor = NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 0.95)
    private let textColor = NSColor(srgbRed: 0.85, green: 0.85, blue: 0.87, alpha: 1.0)
    private let dimColor = NSColor(srgbRed: 0.55, green: 0.55, blue: 0.57, alpha: 1.0)
    private let highlightColor = NSColor(white: 0.25, alpha: 1.0)
    private let borderColor = NSColor(white: 0.3, alpha: 0.5)

    override func loadView() {
        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 380))
        self.view = wrapper

        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = bgColor.cgColor
        containerView.layer?.cornerRadius = 12
        containerView.layer?.borderWidth = 1
        containerView.layer?.borderColor = borderColor.cgColor

        // Shadow on wrapper
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 20
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.shadowColor = NSColor(white: 0, alpha: 0.5)
        containerView.shadow = shadow

        containerView.frame = wrapper.bounds
        containerView.autoresizingMask = [.width, .height]
        wrapper.addSubview(containerView)

        setupSearchField()
        setupSeparator()
        setupTableView()
        setupPromptViews()

        showSelectionPhase()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(searchField)
    }

    // MARK: - Setup

    private func setupSearchField() {
        searchField.placeholderString = "Type to filter..."
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.focusRingType = .none
        searchField.drawsBackground = false
        searchField.textColor = textColor
        searchField.font = .systemFont(ofSize: 16)
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(searchField)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            searchField.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    private func setupSeparator() {
        separatorView.boxType = .separator
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(separatorView)

        NSLayoutConstraint.activate([
            separatorView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            separatorView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func setupTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("variant"))
        column.width = 468
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 44
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(tableViewDoubleClick)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
        ])
    }

    private func setupPromptViews() {
        // Header
        promptHeaderIcon.imageScaling = .scaleProportionallyDown
        promptHeaderIcon.translatesAutoresizingMaskIntoConstraints = false
        promptHeaderIcon.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            promptHeaderIcon.widthAnchor.constraint(equalToConstant: 18),
            promptHeaderIcon.heightAnchor.constraint(equalToConstant: 18),
        ])

        promptHeaderLabel.font = .boldSystemFont(ofSize: 16)
        promptHeaderLabel.textColor = textColor
        promptHeaderLabel.isEditable = false
        promptHeaderLabel.isBordered = false
        promptHeaderLabel.drawsBackground = false

        promptHeader.orientation = .horizontal
        promptHeader.spacing = 8
        promptHeader.alignment = .centerY
        promptHeader.addArrangedSubview(promptHeaderIcon)
        promptHeader.addArrangedSubview(promptHeaderLabel)
        promptHeader.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(promptHeader)

        // Prompt field
        promptField.placeholderString = "Enter prompt..."
        promptField.isBordered = false
        promptField.isBezeled = false
        promptField.focusRingType = .none
        promptField.drawsBackground = false
        promptField.textColor = textColor
        promptField.font = .systemFont(ofSize: 16)
        promptField.delegate = self
        promptField.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(promptField)

        // Hint
        promptHint.font = .systemFont(ofSize: 12)
        promptHint.textColor = dimColor
        promptHint.alignment = .center
        promptHint.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(promptHint)

        NSLayoutConstraint.activate([
            promptHeader.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            promptHeader.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            promptHeader.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            promptField.topAnchor.constraint(equalTo: promptHeader.bottomAnchor, constant: 20),
            promptField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            promptField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            promptField.heightAnchor.constraint(equalToConstant: 24),

            promptHint.topAnchor.constraint(equalTo: promptField.bottomAnchor, constant: 16),
            promptHint.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
        ])
    }

    // MARK: - Phase Transitions

    private func showSelectionPhase() {
        phase = .selection
        filteredVariants = AgentVariant.allVariants
        selectedIndex = 0

        searchField.stringValue = ""
        searchField.isHidden = false
        separatorView.isHidden = false
        scrollView.isHidden = false

        promptHeader.isHidden = true
        promptField.isHidden = true
        promptHint.isHidden = true

        tableView.reloadData()
        updateHighlight()

        resizePanel(rowCount: filteredVariants.count)

        DispatchQueue.main.async { [weak self] in
            self?.view.window?.makeFirstResponder(self?.searchField)
        }
    }

    private func showPromptPhase(variant: AgentVariant) {
        phase = .prompt(variant)

        searchField.isHidden = true
        separatorView.isHidden = true
        scrollView.isHidden = true

        let img = NSImage(systemSymbolName: variant.icon, accessibilityDescription: variant.displayName)
        promptHeaderIcon.image = img
        promptHeaderIcon.contentTintColor = textColor
        promptHeaderLabel.stringValue = variant.displayName

        promptField.placeholderString = variant.promptPlaceholder
        promptField.stringValue = ""

        promptHeader.isHidden = false
        promptField.isHidden = false
        promptHint.isHidden = false

        // Resize for prompt phase
        let panelHeight: CGFloat = 130
        if let panel = view.window as? CommandPalettePanel {
            var frame = panel.frame
            let dy = frame.height - panelHeight
            frame.origin.y += dy
            frame.size.height = panelHeight
            panel.setFrame(frame, display: true, animate: true)
        }

        DispatchQueue.main.async { [weak self] in
            self?.view.window?.makeFirstResponder(self?.promptField)
        }
    }

    private func resizePanel(rowCount: Int) {
        let headerHeight: CGFloat = 56 // search + separator + padding
        let rowsHeight = CGFloat(max(rowCount, 1)) * 44
        let bottomPadding: CGFloat = 8
        let panelHeight = min(headerHeight + rowsHeight + bottomPadding, 380)

        if let panel = view.window as? CommandPalettePanel {
            var frame = panel.frame
            let dy = frame.height - panelHeight
            frame.origin.y += dy
            frame.size.height = panelHeight
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    // MARK: - Filtering

    private func filterVariants(query: String) {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            filteredVariants = AgentVariant.allVariants
        } else {
            filteredVariants = AgentVariant.allVariants.filter {
                $0.displayName.lowercased().contains(q) ||
                $0.subtitle.lowercased().contains(q) ||
                $0.id.lowercased().contains(q)
            }
        }
        selectedIndex = filteredVariants.isEmpty ? -1 : 0
        tableView.reloadData()
        updateHighlight()
        resizePanel(rowCount: filteredVariants.count)
    }

    // MARK: - Highlight

    private func updateHighlight() {
        for row in 0..<tableView.numberOfRows {
            if let cellView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) {
                cellView.layer?.backgroundColor = row == selectedIndex
                    ? highlightColor.cgColor
                    : NSColor.clear.cgColor
            }
        }
    }

    // MARK: - Actions

    private func selectCurrentVariant() {
        guard selectedIndex >= 0, selectedIndex < filteredVariants.count else { return }
        let variant = filteredVariants[selectedIndex]
        showPromptPhase(variant: variant)
    }

    private func submitPrompt() {
        guard case .prompt(let variant) = phase else { return }
        let prompt = promptField.stringValue.trimmingCharacters(in: .whitespaces)
        onSelect?(variant, prompt.isEmpty ? nil : prompt)
    }

    func handleEscape() {
        switch phase {
        case .selection:
            onDismiss?()
        case .prompt:
            showSelectionPhase()
        }
    }

    @objc private func tableViewDoubleClick() {
        let row = tableView.clickedRow
        guard row >= 0, row < filteredVariants.count else { return }
        selectedIndex = row
        updateHighlight()
        selectCurrentVariant()
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === searchField {
            filterVariants(query: field.stringValue)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === searchField {
            return handleSearchFieldCommand(commandSelector)
        } else if control === promptField {
            return handlePromptFieldCommand(commandSelector)
        }
        return false
    }

    private func handleSearchFieldCommand(_ sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveUp(_:)):
            if selectedIndex > 0 {
                selectedIndex -= 1
                updateHighlight()
                tableView.scrollRowToVisible(selectedIndex)
            }
            return true
        case #selector(NSResponder.moveDown(_:)):
            if selectedIndex < filteredVariants.count - 1 {
                selectedIndex += 1
                updateHighlight()
                tableView.scrollRowToVisible(selectedIndex)
            }
            return true
        case #selector(NSResponder.insertNewline(_:)):
            selectCurrentVariant()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            handleEscape()
            return true
        default:
            return false
        }
    }

    private func handlePromptFieldCommand(_ sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)):
            submitPrompt()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            handleEscape()
            return true
        default:
            return false
        }
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension CommandPaletteViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredVariants.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let variant = filteredVariants[row]

        let cellView = NSTableCellView()
        cellView.wantsLayer = true
        cellView.layer?.backgroundColor = row == selectedIndex
            ? highlightColor.cgColor
            : NSColor.clear.cgColor
        cellView.layer?.cornerRadius = 6

        // Icon
        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: variant.icon, accessibilityDescription: variant.displayName)
        iconView.contentTintColor = textColor
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // Name
        let nameLabel = NSTextField(labelWithString: variant.displayName)
        nameLabel.font = .boldSystemFont(ofSize: 14)
        nameLabel.textColor = textColor
        nameLabel.drawsBackground = false
        nameLabel.isBordered = false

        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: variant.subtitle)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = dimColor
        subtitleLabel.drawsBackground = false
        subtitleLabel.isBordered = false

        let textStack = NSStackView(views: [nameLabel, subtitleLabel])
        textStack.orientation = .horizontal
        textStack.spacing = 8
        textStack.alignment = .firstBaseline
        textStack.translatesAutoresizingMaskIntoConstraints = false

        cellView.addSubview(iconView)
        cellView.addSubview(textStack)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: cellView.trailingAnchor, constant: -16),
        ])

        return cellView
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        selectedIndex = row
        updateHighlight()
        return false // We handle selection ourselves
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // No-op — we handle selection via selectedIndex
    }
}
