import AppKit

// MARK: - Data Models

struct SwarmFileInfo {
    let name: String
    let path: String
    let projectRoot: String
    let projectName: String
    let description: String
    let strategy: String        // "shared" | "isolated"
    let agentCount: Int
}

struct SwarmDetail {
    var name: String
    var description: String
    var strategy: String
    var agents: [SwarmAgentInfo]
}

struct SwarmAgentInfo {
    var prompt: String
    var agent: String?
    var vars: [String: String]
}

// MARK: - SwarmsView

class SwarmsView: NSView, NSTableViewDataSource, NSTableViewDelegate {

    private let splitView = NSSplitView()
    private let listScrollView = NSScrollView()
    private let tableView = NSTableView()
    private let detailScrollView = NSScrollView()
    private let detailStack = NSStackView()
    private let headerLabel = NSTextField(labelWithString: "Swarms (0)")
    private let newButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "No swarms found")

    // Detail form fields
    private let nameField = NSTextField()
    private let descField = NSTextField()
    private let sharedRadio = NSButton(radioButtonWithTitle: "Shared", target: nil, action: nil)
    private let isolatedRadio = NSButton(radioButtonWithTitle: "Isolated", target: nil, action: nil)
    private let agentListStack = NSStackView()
    private let addAgentButton = NSButton()
    private let saveButton = NSButton()
    private let deleteButton = NSButton()

    private var swarms: [SwarmFileInfo] = []
    private var selectedIndex: Int? = nil
    private var currentDetail: SwarmDetail? = nil
    private var currentPath: String? = nil
    private var agentRows: [AgentRowView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    // MARK: - Configure

    func configure(projects: [ProjectContext]) {
        swarms = Self.scanSwarms(projects: projects)
        headerLabel.stringValue = "Swarms (\(swarms.count))"
        tableView.reloadData()
        emptyLabel.isHidden = !swarms.isEmpty
        if let idx = selectedIndex, idx < swarms.count {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        } else {
            selectedIndex = nil
            clearDetailForm()
        }
    }

    // MARK: - File Scanning

    static func scanSwarms(projects: [ProjectContext]) -> [SwarmFileInfo] {
        let fm = FileManager.default
        var results: [SwarmFileInfo] = []

        for ctx in projects {
            let folder = (ctx.projectRoot as NSString).appendingPathComponent(".pg/swarms")
            guard let files = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            for file in files where file.hasSuffix(".yaml") || file.hasSuffix(".yml") {
                let path = (folder as NSString).appendingPathComponent(file)
                guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

                let detail = Self.parseYAML(content)
                let name = (file as NSString).deletingPathExtension
                results.append(SwarmFileInfo(
                    name: detail.name.isEmpty ? name : detail.name,
                    path: path,
                    projectRoot: ctx.projectRoot,
                    projectName: ctx.projectName,
                    description: detail.description,
                    strategy: detail.strategy,
                    agentCount: detail.agents.count
                ))
            }
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Simple YAML Parser

    static func parseYAML(_ content: String) -> SwarmDetail {
        var name = ""
        var description = ""
        var strategy = "shared"
        var agents: [SwarmAgentInfo] = []

        let lines = content.components(separatedBy: .newlines)
        var inAgents = false
        var currentAgent: SwarmAgentInfo? = nil
        var inVars = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Top-level keys
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") && !line.hasPrefix("-") {
                inAgents = false
                inVars = false
                if let agent = currentAgent {
                    agents.append(agent)
                    currentAgent = nil
                }

                if trimmed.hasPrefix("name:") {
                    name = yamlValue(trimmed, key: "name")
                } else if trimmed.hasPrefix("description:") {
                    description = yamlValue(trimmed, key: "description")
                } else if trimmed.hasPrefix("strategy:") {
                    strategy = yamlValue(trimmed, key: "strategy")
                } else if trimmed.hasPrefix("agents:") {
                    inAgents = true
                }
                continue
            }

            if inAgents {
                if trimmed.hasPrefix("- prompt:") || trimmed == "-" {
                    if let agent = currentAgent {
                        agents.append(agent)
                    }
                    if trimmed.hasPrefix("- prompt:") {
                        let promptVal = yamlValue(trimmed.replacingOccurrences(of: "- ", with: ""), key: "prompt")
                        currentAgent = SwarmAgentInfo(prompt: promptVal, agent: nil, vars: [:])
                    } else {
                        currentAgent = SwarmAgentInfo(prompt: "", agent: nil, vars: [:])
                    }
                    inVars = false
                } else if currentAgent != nil {
                    if trimmed.hasPrefix("prompt:") {
                        currentAgent?.prompt = yamlValue(trimmed, key: "prompt")
                    } else if trimmed.hasPrefix("agent:") {
                        currentAgent?.agent = yamlValue(trimmed, key: "agent")
                    } else if trimmed.hasPrefix("vars:") {
                        inVars = true
                    } else if inVars && trimmed.contains(":") {
                        let parts = trimmed.split(separator: ":", maxSplits: 1)
                        if parts.count == 2 {
                            let k = parts[0].trimmingCharacters(in: .whitespaces)
                            let v = parts[1].trimmingCharacters(in: .whitespaces)
                            currentAgent?.vars[k] = v
                        }
                    }
                }
            }
        }

        if let agent = currentAgent {
            agents.append(agent)
        }

        return SwarmDetail(name: name, description: description, strategy: strategy, agents: agents)
    }

    private static func yamlValue(_ line: String, key: String) -> String {
        guard let colonIdx = line.range(of: ":") else { return "" }
        var value = String(line[colonIdx.upperBound...]).trimmingCharacters(in: .whitespaces)
        // Strip quotes
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    // MARK: - YAML Serialization

    static func serializeYAML(_ detail: SwarmDetail) -> String {
        var lines: [String] = []
        lines.append("name: \(detail.name)")
        if !detail.description.isEmpty {
            lines.append("description: \(detail.description)")
        }
        lines.append("strategy: \(detail.strategy)")
        if !detail.agents.isEmpty {
            lines.append("agents:")
            for agent in detail.agents {
                lines.append("  - prompt: \(agent.prompt)")
                if let agentType = agent.agent, !agentType.isEmpty {
                    lines.append("    agent: \(agentType)")
                }
                if !agent.vars.isEmpty {
                    lines.append("    vars:")
                    for (k, v) in agent.vars.sorted(by: { $0.key < $1.key }) {
                        lines.append("      \(k): \(v)")
                    }
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = terminalBackground.cgColor

        // Header
        let headerBar = NSView()
        headerBar.translatesAutoresizingMaskIntoConstraints = false

        headerLabel.font = .boldSystemFont(ofSize: 14)
        headerLabel.textColor = terminalForeground
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(headerLabel)

        newButton.bezelStyle = .accessoryBarAction
        newButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Swarm")
        newButton.title = "New Swarm"
        newButton.imagePosition = .imageLeading
        newButton.font = .systemFont(ofSize: 11)
        newButton.isBordered = false
        newButton.contentTintColor = terminalForeground
        newButton.target = self
        newButton.action = #selector(newSwarmClicked)
        newButton.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(newButton)

        let headerSep = NSBox()
        headerSep.boxType = .separator
        headerSep.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(headerSep)

        addSubview(headerBar)

        // Split view
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(splitView)

        // Left pane: table list
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("swarm"))
        column.title = ""
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowSizeStyle = .medium
        tableView.style = .sourceList
        tableView.backgroundColor = .clear

        listScrollView.documentView = tableView
        listScrollView.hasVerticalScroller = true
        listScrollView.drawsBackground = false
        splitView.addSubview(listScrollView)

        // Right pane: detail form
        let detailContainer = NSView()
        detailContainer.translatesAutoresizingMaskIntoConstraints = false

        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 12
        detailStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        detailStack.translatesAutoresizingMaskIntoConstraints = false

        setupDetailForm()

        detailScrollView.documentView = detailStack
        detailScrollView.hasVerticalScroller = true
        detailScrollView.drawsBackground = true
        detailScrollView.backgroundColor = terminalBackground
        detailScrollView.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(detailScrollView)

        // Button bar
        let buttonBar = NSView()
        buttonBar.translatesAutoresizingMaskIntoConstraints = false

        let btnSep = NSBox()
        btnSep.boxType = .separator
        btnSep.translatesAutoresizingMaskIntoConstraints = false
        buttonBar.addSubview(btnSep)

        saveButton.bezelStyle = .accessoryBarAction
        saveButton.title = "Save"
        saveButton.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
        saveButton.imagePosition = .imageLeading
        saveButton.font = .systemFont(ofSize: 11)
        saveButton.isBordered = false
        saveButton.contentTintColor = terminalForeground
        saveButton.target = self
        saveButton.action = #selector(saveClicked)
        saveButton.isEnabled = false
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        buttonBar.addSubview(saveButton)

        deleteButton.bezelStyle = .accessoryBarAction
        deleteButton.title = "Delete"
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
        deleteButton.imagePosition = .imageLeading
        deleteButton.font = .systemFont(ofSize: 11)
        deleteButton.isBordered = false
        deleteButton.contentTintColor = .systemRed
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)
        deleteButton.isEnabled = false
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        buttonBar.addSubview(deleteButton)

        detailContainer.addSubview(buttonBar)

        NSLayoutConstraint.activate([
            detailScrollView.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            detailScrollView.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detailScrollView.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detailScrollView.bottomAnchor.constraint(equalTo: buttonBar.topAnchor),

            detailStack.leadingAnchor.constraint(equalTo: detailScrollView.contentView.leadingAnchor),
            detailStack.trailingAnchor.constraint(equalTo: detailScrollView.contentView.trailingAnchor),

            buttonBar.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            buttonBar.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            buttonBar.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),
            buttonBar.heightAnchor.constraint(equalToConstant: 36),

            btnSep.topAnchor.constraint(equalTo: buttonBar.topAnchor),
            btnSep.leadingAnchor.constraint(equalTo: buttonBar.leadingAnchor),
            btnSep.trailingAnchor.constraint(equalTo: buttonBar.trailingAnchor),

            saveButton.leadingAnchor.constraint(equalTo: buttonBar.leadingAnchor, constant: 8),
            saveButton.centerYAnchor.constraint(equalTo: buttonBar.centerYAnchor),

            deleteButton.trailingAnchor.constraint(equalTo: buttonBar.trailingAnchor, constant: -8),
            deleteButton.centerYAnchor.constraint(equalTo: buttonBar.centerYAnchor),
        ])

        splitView.addSubview(detailContainer)

        // Empty label
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 36),

            headerLabel.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 12),
            headerLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            newButton.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -8),
            newButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            headerSep.bottomAnchor.constraint(equalTo: headerBar.bottomAnchor),
            headerSep.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            headerSep.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),

            splitView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.splitView.setPosition(220, ofDividerAt: 0)
        }
    }

    private func setupDetailForm() {
        // Name
        let nameRow = makeFormRow(label: "Name:", field: nameField)
        nameField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        nameField.textColor = terminalForeground
        nameField.backgroundColor = terminalBackground
        nameField.drawsBackground = true
        detailStack.addArrangedSubview(nameRow)
        nameRow.translatesAutoresizingMaskIntoConstraints = false
        nameRow.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -24).isActive = true

        // Description
        let descRow = makeFormRow(label: "Description:", field: descField)
        descField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        descField.textColor = terminalForeground
        descField.backgroundColor = terminalBackground
        descField.drawsBackground = true
        detailStack.addArrangedSubview(descRow)
        descRow.translatesAutoresizingMaskIntoConstraints = false
        descRow.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -24).isActive = true

        // Strategy
        let strategyLabel = NSTextField(labelWithString: "Strategy:")
        strategyLabel.font = .systemFont(ofSize: 12)
        strategyLabel.textColor = .secondaryLabelColor

        sharedRadio.target = self
        sharedRadio.action = #selector(strategyChanged)
        sharedRadio.contentTintColor = terminalForeground
        isolatedRadio.target = self
        isolatedRadio.action = #selector(strategyChanged)
        isolatedRadio.contentTintColor = terminalForeground

        let radioStack = NSStackView(views: [sharedRadio, isolatedRadio])
        radioStack.orientation = .horizontal
        radioStack.spacing = 12

        let strategyRow = NSStackView(views: [strategyLabel, radioStack])
        strategyRow.orientation = .horizontal
        strategyRow.spacing = 8
        detailStack.addArrangedSubview(strategyRow)

        // Agents section
        let agentsLabel = NSTextField(labelWithString: "Agents:")
        agentsLabel.font = .boldSystemFont(ofSize: 12)
        agentsLabel.textColor = terminalForeground
        detailStack.addArrangedSubview(agentsLabel)

        agentListStack.orientation = .vertical
        agentListStack.spacing = 8
        agentListStack.translatesAutoresizingMaskIntoConstraints = false
        detailStack.addArrangedSubview(agentListStack)
        agentListStack.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -24).isActive = true

        addAgentButton.bezelStyle = .accessoryBarAction
        addAgentButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Agent")
        addAgentButton.title = "Add Agent"
        addAgentButton.imagePosition = .imageLeading
        addAgentButton.font = .systemFont(ofSize: 11)
        addAgentButton.isBordered = false
        addAgentButton.contentTintColor = terminalForeground
        addAgentButton.target = self
        addAgentButton.action = #selector(addAgentClicked)
        detailStack.addArrangedSubview(addAgentButton)
    }

    private func makeFormRow(label: String, field: NSTextField) -> NSStackView {
        let labelView = NSTextField(labelWithString: label)
        labelView.font = .systemFont(ofSize: 12)
        labelView.textColor = .secondaryLabelColor
        labelView.setContentHuggingPriority(.required, for: .horizontal)

        field.isEditable = true
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel

        let row = NSStackView(views: [labelView, field])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        swarms.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < swarms.count else { return nil }
        let swarm = swarms[row]

        let cell = NSTableCellView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: swarm.name)
        nameLabel.font = .boldSystemFont(ofSize: 12)
        nameLabel.textColor = terminalForeground

        let detail = "\(swarm.agentCount) agent\(swarm.agentCount == 1 ? "" : "s") · \(swarm.strategy)"
        let detailLabel = NSTextField(labelWithString: "\(swarm.projectName) · \(detail)")
        detailLabel.font = .systemFont(ofSize: 10)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        stack.addArrangedSubview(nameLabel)
        stack.addArrangedSubview(detailLabel)

        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        38
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < swarms.count else {
            selectedIndex = nil
            clearDetailForm()
            return
        }
        selectedIndex = row
        loadSwarmDetail(at: row)
        saveButton.isEnabled = true
        deleteButton.isEnabled = true
    }

    // MARK: - Detail Form

    private func loadSwarmDetail(at index: Int) {
        let swarm = swarms[index]
        guard let content = try? String(contentsOfFile: swarm.path, encoding: .utf8) else { return }
        let detail = Self.parseYAML(content)
        currentDetail = detail
        currentPath = swarm.path

        nameField.stringValue = detail.name
        descField.stringValue = detail.description
        sharedRadio.state = detail.strategy == "shared" ? .on : .off
        isolatedRadio.state = detail.strategy == "isolated" ? .on : .off

        rebuildAgentRows(detail.agents)
    }

    private func clearDetailForm() {
        nameField.stringValue = ""
        descField.stringValue = ""
        sharedRadio.state = .on
        isolatedRadio.state = .off
        currentDetail = nil
        currentPath = nil
        saveButton.isEnabled = false
        deleteButton.isEnabled = false
        rebuildAgentRows([])
    }

    private func rebuildAgentRows(_ agents: [SwarmAgentInfo]) {
        for row in agentRows {
            agentListStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        agentRows = []

        for (i, agent) in agents.enumerated() {
            let row = AgentRowView(agent: agent, index: i)
            row.onRemove = { [weak self] idx in
                self?.removeAgentRow(at: idx)
            }
            agentRows.append(row)
            agentListStack.addArrangedSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalTo: agentListStack.widthAnchor).isActive = true
        }
    }

    private func removeAgentRow(at index: Int) {
        guard index < agentRows.count else { return }
        let row = agentRows[index]
        agentListStack.removeArrangedSubview(row)
        row.removeFromSuperview()
        agentRows.remove(at: index)
        // Re-index
        for (i, r) in agentRows.enumerated() {
            r.index = i
        }
    }

    private func collectDetailFromForm() -> SwarmDetail {
        let agents: [SwarmAgentInfo] = agentRows.map { row in
            SwarmAgentInfo(
                prompt: row.promptField.stringValue,
                agent: row.agentField.stringValue.isEmpty ? nil : row.agentField.stringValue,
                vars: [:]
            )
        }
        return SwarmDetail(
            name: nameField.stringValue,
            description: descField.stringValue,
            strategy: sharedRadio.state == .on ? "shared" : "isolated",
            agents: agents
        )
    }

    // MARK: - Actions

    @objc private func strategyChanged() {
        // Ensure mutual exclusion
        if sharedRadio.state == .on {
            isolatedRadio.state = .off
        } else {
            sharedRadio.state = .off
        }
    }

    @objc private func addAgentClicked() {
        let agent = SwarmAgentInfo(prompt: "", agent: nil, vars: [:])
        let row = AgentRowView(agent: agent, index: agentRows.count)
        row.onRemove = { [weak self] idx in
            self?.removeAgentRow(at: idx)
        }
        agentRows.append(row)
        agentListStack.addArrangedSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalTo: agentListStack.widthAnchor).isActive = true
    }

    @objc private func saveClicked() {
        guard let path = currentPath else { return }
        let detail = collectDetailFromForm()
        let yaml = Self.serializeYAML(detail)

        do {
            try yaml.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to Save"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func deleteClicked() {
        guard let idx = selectedIndex, idx < swarms.count else { return }
        let swarm = swarms[idx]

        let alert = NSAlert()
        alert.messageText = "Delete \"\(swarm.name)\"?"
        alert.informativeText = "This will permanently delete the swarm file."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try FileManager.default.removeItem(atPath: swarm.path)
            swarms.remove(at: idx)
            headerLabel.stringValue = "Swarms (\(swarms.count))"
            selectedIndex = nil
            clearDetailForm()
            tableView.reloadData()
            emptyLabel.isHidden = !swarms.isEmpty
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Failed to Delete"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }

    @objc private func newSwarmClicked() {
        let projects = OpenProjects.shared.projects
        guard !projects.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "New Swarm"
        alert.informativeText = "Enter a name for the swarm:"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let accessory = NSStackView()
        accessory.orientation = .vertical
        accessory.spacing = 8

        let nameInput = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        nameInput.placeholderString = "swarm-name"
        accessory.addArrangedSubview(nameInput)

        let projectPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 24), pullsDown: false)
        for ctx in projects {
            projectPopup.addItem(withTitle: ctx.projectName.isEmpty ? ctx.projectRoot : ctx.projectName)
        }
        accessory.addArrangedSubview(projectPopup)

        accessory.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            accessory.widthAnchor.constraint(equalToConstant: 240),
        ])

        alert.accessoryView = accessory
        alert.window.initialFirstResponder = nameInput

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = nameInput.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let projectIdx = projectPopup.indexOfSelectedItem
        guard projectIdx >= 0, projectIdx < projects.count else { return }
        let ctx = projects[projectIdx]

        let folder = (ctx.projectRoot as NSString).appendingPathComponent(".pg/swarms")
        let fm = FileManager.default
        if !fm.fileExists(atPath: folder) {
            try? fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }

        let filename = name.hasSuffix(".yaml") ? name : "\(name).yaml"
        let path = (folder as NSString).appendingPathComponent(filename)
        let skeleton = SwarmDetail(
            name: name,
            description: "",
            strategy: "shared",
            agents: [SwarmAgentInfo(prompt: "", agent: "claude", vars: [:])]
        )
        let yaml = Self.serializeYAML(skeleton)

        do {
            try yaml.write(toFile: path, atomically: true, encoding: .utf8)
            configure(projects: OpenProjects.shared.projects)
            if let idx = swarms.firstIndex(where: { $0.path == path }) {
                tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
                loadSwarmDetail(at: idx)
                selectedIndex = idx
            }
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Failed to Create"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }
}

// MARK: - Agent Row View

class AgentRowView: NSView {
    let promptField = NSTextField()
    let agentField = NSTextField()
    var index: Int
    var onRemove: ((Int) -> Void)?

    init(agent: SwarmAgentInfo, index: Int) {
        self.index = index
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor(srgbRed: 0.14, green: 0.14, blue: 0.15, alpha: 1.0).cgColor

        let promptLabel = NSTextField(labelWithString: "Prompt:")
        promptLabel.font = .systemFont(ofSize: 11)
        promptLabel.textColor = .secondaryLabelColor
        promptLabel.setContentHuggingPriority(.required, for: .horizontal)

        promptField.stringValue = agent.prompt
        promptField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        promptField.textColor = terminalForeground
        promptField.backgroundColor = terminalBackground
        promptField.drawsBackground = true
        promptField.isBordered = true
        promptField.isBezeled = true
        promptField.bezelStyle = .roundedBezel

        let agentLabel = NSTextField(labelWithString: "Agent:")
        agentLabel.font = .systemFont(ofSize: 11)
        agentLabel.textColor = .secondaryLabelColor
        agentLabel.setContentHuggingPriority(.required, for: .horizontal)

        agentField.stringValue = agent.agent ?? ""
        agentField.placeholderString = "claude"
        agentField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        agentField.textColor = terminalForeground
        agentField.backgroundColor = terminalBackground
        agentField.drawsBackground = true
        agentField.isBordered = true
        agentField.isBezeled = true
        agentField.bezelStyle = .roundedBezel

        let removeBtn = NSButton()
        removeBtn.bezelStyle = .accessoryBarAction
        removeBtn.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove")
        removeBtn.isBordered = false
        removeBtn.contentTintColor = .systemRed
        removeBtn.target = self
        removeBtn.action = #selector(removeClicked)
        removeBtn.setContentHuggingPriority(.required, for: .horizontal)

        let promptRow = NSStackView(views: [promptLabel, promptField])
        promptRow.orientation = .horizontal
        promptRow.spacing = 6

        let agentRow = NSStackView(views: [agentLabel, agentField, removeBtn])
        agentRow.orientation = .horizontal
        agentRow.spacing = 6

        let stack = NSStackView(views: [promptRow, agentRow])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    @objc private func removeClicked() {
        onRemove?(index)
    }
}
