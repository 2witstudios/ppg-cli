import AppKit

// MARK: - Data Model

struct ScheduleInfo {
    let name: String
    let cronExpression: String
    let type: String          // "swarm" or "prompt"
    let target: String        // swarm/prompt template name
    let projectRoot: String
    let projectName: String
    let filePath: String      // path to schedules.yaml
    let vars: [(String, String)]
}

/// A computed calendar event from a schedule + cron occurrence.
struct CalendarEvent {
    let schedule: ScheduleInfo
    let date: Date
    let color: NSColor
    let isHighFrequency: Bool
}

// MARK: - Calendar View Mode

enum CalendarViewMode: Int {
    case day = 0
    case week = 1
    case month = 2
}

// MARK: - Project Color Palette

private let projectColors: [NSColor] = [
    .systemBlue, .systemPurple, .systemTeal, .systemOrange,
    .systemPink, .systemIndigo, .systemGreen, .systemBrown,
    .systemCyan, .systemMint
]

private func colorForProject(_ name: String) -> NSColor {
    let hash = abs(name.hashValue)
    return projectColors[hash % projectColors.count]
}

// MARK: - SchedulesView (Calendar)

class SchedulesView: NSView {

    // MARK: - Header Controls
    private let headerBar = NSView()
    private let headerLabel = NSTextField(labelWithString: "Schedules")
    private let daemonDot = NSView()
    private let daemonButton = NSButton()
    private let prevButton = NSButton()
    private let todayButton = NSButton()
    private let nextButton = NSButton()
    private let dateLabel = NSTextField(labelWithString: "")
    private let viewSegment = NSSegmentedControl(labels: ["Day", "Week", "Month"], trackingMode: .selectOne, target: nil, action: nil)
    private let newButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "No schedules found")

    // MARK: - Content Area
    private let contentContainer = NSView()
    private var monthView: CalendarMonthView?
    private var weekView: CalendarWeekView?
    private var dayView: CalendarDayView?

    // MARK: - State
    private var schedules: [ScheduleInfo] = []
    private var events: [CalendarEvent] = []
    private var currentDate = Date()
    private var viewMode: CalendarViewMode = .month
    private var daemonRunning = false
    private var projects: [ProjectContext] = []

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
        self.projects = projects
        schedules = Self.scanSchedules(projects: projects)
        emptyLabel.isHidden = !schedules.isEmpty
        recomputeEvents()
        updateDateLabel()
        refreshCurrentView()
        checkDaemonStatus()
    }

    // MARK: - File Scanning (unchanged from original)

    static func scanSchedules(projects: [ProjectContext]) -> [ScheduleInfo] {
        var results: [ScheduleInfo] = []

        for ctx in projects {
            let filePath = (ctx.projectRoot as NSString).appendingPathComponent(".ppg/schedules.yaml")
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

            let entries = parseSchedulesYAML(content)
            for entry in entries {
                results.append(ScheduleInfo(
                    name: entry.name,
                    cronExpression: entry.cron,
                    type: entry.type,
                    target: entry.target,
                    projectRoot: ctx.projectRoot,
                    projectName: ctx.projectName,
                    filePath: filePath,
                    vars: entry.vars
                ))
            }
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Simple YAML Parser

    private struct ParsedSchedule {
        var name: String
        var cron: String
        var type: String
        var target: String
        var vars: [(String, String)]
    }

    private static func parseSchedulesYAML(_ content: String) -> [ParsedSchedule] {
        var results: [ParsedSchedule] = []
        let lines = content.components(separatedBy: .newlines)

        var inSchedules = false
        var current: ParsedSchedule? = nil
        var inVars = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if !line.hasPrefix(" ") && !line.hasPrefix("\t") && !line.hasPrefix("-") {
                if let c = current {
                    results.append(c)
                    current = nil
                }
                inVars = false
                inSchedules = trimmed.hasPrefix("schedules:")
                continue
            }

            guard inSchedules else { continue }

            if trimmed.hasPrefix("- ") || trimmed == "-" {
                if let c = current { results.append(c) }
                current = ParsedSchedule(name: "", cron: "", type: "", target: "", vars: [])
                inVars = false
                let afterDash = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !afterDash.isEmpty {
                    applyKeyValue(afterDash, to: &current!, inVars: &inVars)
                }
            } else if current != nil {
                applyKeyValue(trimmed, to: &current!, inVars: &inVars)
            }
        }
        if let c = current { results.append(c) }
        return results
    }

    private static func applyKeyValue(_ trimmed: String, to entry: inout ParsedSchedule, inVars: inout Bool) {
        if trimmed.hasPrefix("name:") { entry.name = yamlValue(trimmed); inVars = false }
        else if trimmed.hasPrefix("cron:") { entry.cron = yamlValue(trimmed); inVars = false }
        else if trimmed.hasPrefix("swarm:") { entry.type = "swarm"; entry.target = yamlValue(trimmed); inVars = false }
        else if trimmed.hasPrefix("prompt:") { entry.type = "prompt"; entry.target = yamlValue(trimmed); inVars = false }
        else if trimmed.hasPrefix("vars:") { inVars = true }
        else if inVars && trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let k = parts[0].trimmingCharacters(in: .whitespaces)
                let v = parts[1].trimmingCharacters(in: .whitespaces)
                entry.vars.append((k, stripQuotes(v)))
            }
        }
    }

    static func yamlValue(_ line: String) -> String {
        guard let colonIdx = line.range(of: ":") else { return "" }
        return stripQuotes(String(line[colonIdx.upperBound...]).trimmingCharacters(in: .whitespaces))
    }

    private static func stripQuotes(_ s: String) -> String {
        var value = s
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    // MARK: - Event Computation

    private func recomputeEvents() {
        let cal = Calendar.current
        let (start, end) = dateRangeForCurrentView(calendar: cal)
        var allEvents: [CalendarEvent] = []

        for schedule in schedules {
            guard let expr = try? CronParser.parse(schedule.cronExpression) else { continue }
            let color = colorForProject(schedule.projectName)
            let highFreq = CronParser.isHighFrequency(expr)

            if highFreq {
                // For high-frequency crons, generate one event per day
                var day = start
                while day < end {
                    allEvents.append(CalendarEvent(schedule: schedule, date: day, color: color, isHighFrequency: true))
                    day = cal.date(byAdding: .day, value: 1, to: day) ?? end
                }
            } else {
                let occurrences = CronParser.occurrences(of: expr, from: start, to: end, calendar: cal, limit: 2000)
                for date in occurrences {
                    allEvents.append(CalendarEvent(schedule: schedule, date: date, color: color, isHighFrequency: false))
                }
            }
        }

        events = allEvents
    }

    private func dateRangeForCurrentView(calendar cal: Calendar) -> (Date, Date) {
        switch viewMode {
        case .month:
            // First day of month's week to last day of month's last week
            let comps = cal.dateComponents([.year, .month], from: currentDate)
            let firstOfMonth = cal.date(from: comps)!
            let firstWeekday = cal.component(.weekday, from: firstOfMonth) // 1=Sun
            let startOffset = -(firstWeekday - cal.firstWeekday + 7) % 7
            let start = cal.date(byAdding: .day, value: startOffset, to: firstOfMonth)!
            let end = cal.date(byAdding: .day, value: 42, to: start)! // 6 weeks
            return (start, end)
        case .week:
            let weekday = cal.component(.weekday, from: currentDate)
            let startOffset = -(weekday - cal.firstWeekday + 7) % 7
            let start = cal.startOfDay(for: cal.date(byAdding: .day, value: startOffset, to: currentDate)!)
            let end = cal.date(byAdding: .day, value: 7, to: start)!
            return (start, end)
        case .day:
            let start = cal.startOfDay(for: currentDate)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
        }
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = Theme.contentBackground.resolvedCGColor(for: effectiveAppearance)

        // Header bar
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerBar)

        // Title
        headerLabel.font = .boldSystemFont(ofSize: 14)
        headerLabel.textColor = Theme.primaryText
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(headerLabel)

        // Daemon dot
        daemonDot.translatesAutoresizingMaskIntoConstraints = false
        daemonDot.wantsLayer = true
        daemonDot.layer?.cornerRadius = 5
        daemonDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        headerBar.addSubview(daemonDot)

        // Daemon button
        daemonButton.bezelStyle = .accessoryBarAction
        daemonButton.title = "Start Daemon"
        daemonButton.font = .systemFont(ofSize: 11)
        daemonButton.isBordered = false
        daemonButton.contentTintColor = Theme.primaryText
        daemonButton.target = self
        daemonButton.action = #selector(daemonToggleClicked)
        daemonButton.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(daemonButton)

        // Navigation: < Today >
        prevButton.bezelStyle = .accessoryBarAction
        prevButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous")
        prevButton.isBordered = false
        prevButton.contentTintColor = Theme.primaryText
        prevButton.target = self
        prevButton.action = #selector(prevClicked)
        prevButton.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(prevButton)

        todayButton.bezelStyle = .accessoryBarAction
        todayButton.title = "Today"
        todayButton.font = .systemFont(ofSize: 11)
        todayButton.isBordered = false
        todayButton.contentTintColor = Theme.primaryText
        todayButton.target = self
        todayButton.action = #selector(todayClicked)
        todayButton.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(todayButton)

        nextButton.bezelStyle = .accessoryBarAction
        nextButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next")
        nextButton.isBordered = false
        nextButton.contentTintColor = Theme.primaryText
        nextButton.target = self
        nextButton.action = #selector(nextClicked)
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(nextButton)

        // Date label
        dateLabel.font = .systemFont(ofSize: 13, weight: .medium)
        dateLabel.textColor = Theme.primaryText
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(dateLabel)

        // View segment
        viewSegment.selectedSegment = 2 // Month default
        viewSegment.target = self
        viewSegment.action = #selector(viewModeChanged)
        viewSegment.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(viewSegment)

        // New schedule button
        newButton.bezelStyle = .accessoryBarAction
        newButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Schedule")
        newButton.title = " New Schedule"
        newButton.imagePosition = .imageLeading
        newButton.font = .systemFont(ofSize: 11)
        newButton.isBordered = false
        newButton.contentTintColor = Theme.primaryText
        newButton.target = self
        newButton.action = #selector(newScheduleClicked)
        newButton.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(newButton)

        // Header separator
        let headerSep = NSBox()
        headerSep.boxType = .separator
        headerSep.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(headerSep)

        // Content container
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)

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
            headerBar.heightAnchor.constraint(equalToConstant: 40),

            headerLabel.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 12),
            headerLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            daemonDot.leadingAnchor.constraint(equalTo: headerLabel.trailingAnchor, constant: 8),
            daemonDot.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            daemonDot.widthAnchor.constraint(equalToConstant: 10),
            daemonDot.heightAnchor.constraint(equalToConstant: 10),

            daemonButton.leadingAnchor.constraint(equalTo: daemonDot.trailingAnchor, constant: 4),
            daemonButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            prevButton.leadingAnchor.constraint(equalTo: daemonButton.trailingAnchor, constant: 16),
            prevButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            todayButton.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 2),
            todayButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            nextButton.leadingAnchor.constraint(equalTo: todayButton.trailingAnchor, constant: 2),
            nextButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            dateLabel.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 12),
            dateLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            newButton.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -8),
            newButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            viewSegment.trailingAnchor.constraint(equalTo: newButton.leadingAnchor, constant: -12),
            viewSegment.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            headerSep.bottomAnchor.constraint(equalTo: headerBar.bottomAnchor),
            headerSep.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            headerSep.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),

            contentContainer.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateDateLabel()
        showMonthView()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.contentBackground.resolvedCGColor(for: effectiveAppearance)
    }

    // MARK: - Date Label

    private func updateDateLabel() {
        let fmt = DateFormatter()
        let cal = Calendar.current

        switch viewMode {
        case .month:
            fmt.dateFormat = "MMMM yyyy"
            dateLabel.stringValue = fmt.string(from: currentDate)
        case .week:
            let weekday = cal.component(.weekday, from: currentDate)
            let startOffset = -(weekday - cal.firstWeekday + 7) % 7
            let weekStart = cal.date(byAdding: .day, value: startOffset, to: currentDate)!
            let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart)!
            fmt.dateFormat = "MMM d"
            let startStr = fmt.string(from: weekStart)
            let endStr = fmt.string(from: weekEnd)
            fmt.dateFormat = ", yyyy"
            let yearStr = fmt.string(from: weekEnd)
            dateLabel.stringValue = "\(startStr) - \(endStr)\(yearStr)"
        case .day:
            fmt.dateFormat = "EEEE, MMMM d, yyyy"
            dateLabel.stringValue = fmt.string(from: currentDate)
        }
    }

    // MARK: - View Switching

    private func refreshCurrentView() {
        switch viewMode {
        case .month: showMonthView()
        case .week: showWeekView()
        case .day: showDayView()
        }
    }

    private func clearContent() {
        monthView?.removeFromSuperview()
        weekView?.removeFromSuperview()
        dayView?.removeFromSuperview()
    }

    private func showMonthView() {
        clearContent()
        let mv = CalendarMonthView()
        mv.translatesAutoresizingMaskIntoConstraints = false
        mv.onDayClicked = { [weak self] date in
            self?.currentDate = date
            self?.viewMode = .day
            self?.viewSegment.selectedSegment = CalendarViewMode.day.rawValue
            self?.recomputeEvents()
            self?.updateDateLabel()
            self?.refreshCurrentView()
        }
        mv.onEventClicked = { [weak self] event, sourceView in
            self?.showEventPopover(for: event, relativeTo: sourceView)
        }
        contentContainer.addSubview(mv)
        NSLayoutConstraint.activate([
            mv.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            mv.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            mv.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            mv.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        monthView = mv
        mv.configure(currentDate: currentDate, events: events)
    }

    private func showWeekView() {
        clearContent()
        let wv = CalendarWeekView()
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.onEventClicked = { [weak self] event, sourceView in
            self?.showEventPopover(for: event, relativeTo: sourceView)
        }
        wv.onEmptySlotClicked = { [weak self] date in
            self?.showNewScheduleDialog(prefilledDate: date)
        }
        contentContainer.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            wv.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        weekView = wv
        wv.configure(currentDate: currentDate, events: events)
    }

    private func showDayView() {
        clearContent()
        let dv = CalendarDayView()
        dv.translatesAutoresizingMaskIntoConstraints = false
        dv.onEventClicked = { [weak self] event, sourceView in
            self?.showEventPopover(for: event, relativeTo: sourceView)
        }
        dv.onEmptySlotClicked = { [weak self] date in
            self?.showNewScheduleDialog(prefilledDate: date)
        }
        contentContainer.addSubview(dv)
        NSLayoutConstraint.activate([
            dv.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            dv.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            dv.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            dv.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        dayView = dv
        dv.configure(currentDate: currentDate, events: events)
    }

    // MARK: - Event Detail Popover

    private func showEventPopover(for event: CalendarEvent, relativeTo sourceView: NSView) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 280, height: 0) // auto-height

        let vc = NSViewController()
        let container = NSView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        // Name
        let nameLabel = NSTextField(labelWithString: event.schedule.name)
        nameLabel.font = .boldSystemFont(ofSize: 14)
        nameLabel.textColor = Theme.primaryText
        stack.addArrangedSubview(nameLabel)

        // Cron expression
        let cronRaw = event.schedule.cronExpression
        let cronHuman = CronParser.humanReadable(cronRaw)
        let cronLabel = NSTextField(labelWithString: "\(cronHuman)  (\(cronRaw))")
        cronLabel.font = .systemFont(ofSize: 11)
        cronLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(cronLabel)

        // Separator
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true

        // Type
        let typeIcon = event.schedule.type == "swarm" ? "arrow.triangle.branch" : "doc.text"
        let typeStr = event.schedule.type == "swarm" ? "Swarm" : "Prompt"
        let typeLabel = makeDetailRow(icon: typeIcon, text: "Type: \(typeStr)")
        stack.addArrangedSubview(typeLabel)

        // Target
        let targetLabel = makeDetailRow(icon: "target", text: "Target: \(event.schedule.target)")
        stack.addArrangedSubview(targetLabel)

        // Project
        let projectLabel = makeDetailRow(icon: "folder", text: "Project: \(event.schedule.projectName)")
        stack.addArrangedSubview(projectLabel)

        // Vars
        if !event.schedule.vars.isEmpty {
            let varsStr = event.schedule.vars.map { "\($0.0)=\($0.1)" }.joined(separator: ", ")
            let varsLabel = makeDetailRow(icon: "list.bullet", text: "Vars: \(varsStr)")
            stack.addArrangedSubview(varsLabel)
        }

        // High frequency indicator
        if event.isHighFrequency {
            let hfLabel = NSTextField(labelWithString: "High-frequency schedule (>48 runs/day)")
            hfLabel.font = .systemFont(ofSize: 10, weight: .medium)
            hfLabel.textColor = .systemOrange
            stack.addArrangedSubview(hfLabel)
        }

        // Buttons
        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8

        let editButton = NSButton(title: "Edit", target: self, action: #selector(editScheduleFromPopover(_:)))
        editButton.bezelStyle = .rounded
        editButton.font = .systemFont(ofSize: 11)
        editButton.tag = schedules.firstIndex(where: { $0.name == event.schedule.name && $0.filePath == event.schedule.filePath }) ?? -1

        let deleteButton = NSButton(title: "Delete", target: self, action: #selector(deleteScheduleFromPopover(_:)))
        deleteButton.bezelStyle = .rounded
        deleteButton.font = .systemFont(ofSize: 11)
        deleteButton.contentTintColor = .systemRed
        deleteButton.tag = editButton.tag

        buttonStack.addArrangedSubview(editButton)
        buttonStack.addArrangedSubview(deleteButton)
        stack.addArrangedSubview(buttonStack)

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        vc.view = container
        popover.contentViewController = vc
        popover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
    }

    private func makeDetailRow(icon: String, text: String) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4
        let img = NSImageView()
        img.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        img.translatesAutoresizingMaskIntoConstraints = false
        img.widthAnchor.constraint(equalToConstant: 14).isActive = true
        img.heightAnchor.constraint(equalToConstant: 14).isActive = true
        img.contentTintColor = .secondaryLabelColor
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = Theme.primaryText
        label.lineBreakMode = .byTruncatingTail
        row.addArrangedSubview(img)
        row.addArrangedSubview(label)
        return row
    }

    // MARK: - Actions

    @objc private func prevClicked() {
        let cal = Calendar.current
        switch viewMode {
        case .month: currentDate = cal.date(byAdding: .month, value: -1, to: currentDate)!
        case .week: currentDate = cal.date(byAdding: .weekOfYear, value: -1, to: currentDate)!
        case .day: currentDate = cal.date(byAdding: .day, value: -1, to: currentDate)!
        }
        recomputeEvents()
        updateDateLabel()
        refreshCurrentView()
    }

    @objc private func nextClicked() {
        let cal = Calendar.current
        switch viewMode {
        case .month: currentDate = cal.date(byAdding: .month, value: 1, to: currentDate)!
        case .week: currentDate = cal.date(byAdding: .weekOfYear, value: 1, to: currentDate)!
        case .day: currentDate = cal.date(byAdding: .day, value: 1, to: currentDate)!
        }
        recomputeEvents()
        updateDateLabel()
        refreshCurrentView()
    }

    @objc private func todayClicked() {
        currentDate = Date()
        recomputeEvents()
        updateDateLabel()
        refreshCurrentView()
    }

    @objc private func viewModeChanged() {
        viewMode = CalendarViewMode(rawValue: viewSegment.selectedSegment) ?? .month
        recomputeEvents()
        updateDateLabel()
        refreshCurrentView()
    }

    @objc private func editScheduleFromPopover(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < schedules.count else { return }
        // Close any open popover
        if let popover = (sender.window?.contentView?.subviews.first as? NSPopover) {
            popover.close()
        }
        showEditScheduleDialog(at: idx)
    }

    @objc private func deleteScheduleFromPopover(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < schedules.count else { return }
        let schedule = schedules[idx]

        let alert = NSAlert()
        alert.messageText = "Delete schedule \"\(schedule.name)\"?"
        alert.informativeText = "This will remove the schedule entry from schedules.yaml."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard let content = try? String(contentsOfFile: schedule.filePath, encoding: .utf8) else { return }
        let filtered = removeScheduleEntry(named: schedule.name, from: content)

        do {
            if filtered.trimmingCharacters(in: .whitespacesAndNewlines) == "schedules:" ||
               filtered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try FileManager.default.removeItem(atPath: schedule.filePath)
            } else {
                try filtered.write(toFile: schedule.filePath, atomically: true, encoding: .utf8)
            }
            configure(projects: projects)
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Failed to Delete"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }

    @objc private func daemonToggleClicked() {
        guard let ctx = projects.first else { return }
        let command = daemonRunning ? "cron stop" : "cron start"
        let projectRoot = ctx.projectRoot
        daemonButton.isEnabled = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = PPGService.shared.runPPGCommand(command, projectRoot: projectRoot)
            DispatchQueue.main.async {
                self?.daemonButton.isEnabled = true
                self?.checkDaemonStatus()
            }
        }
    }

    @objc private func newScheduleClicked() {
        showNewScheduleDialog(prefilledDate: nil)
    }

    // MARK: - Daemon Status

    private func checkDaemonStatus() {
        guard let ctx = projects.first else {
            updateDaemonUI(running: false)
            return
        }
        let projectRoot = ctx.projectRoot
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = PPGService.shared.runPPGCommand("cron status --json", projectRoot: projectRoot)
            let running = result.stdout.contains("\"running\":true") || result.stdout.contains("\"running\": true")
            DispatchQueue.main.async {
                self?.updateDaemonUI(running: running)
            }
        }
    }

    private func updateDaemonUI(running: Bool) {
        daemonRunning = running
        daemonDot.wantsLayer = true
        daemonDot.layer?.cornerRadius = 5
        if running {
            daemonDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
            daemonButton.title = "Stop Daemon"
        } else {
            daemonDot.layer?.backgroundColor = NSColor.systemRed.cgColor
            daemonButton.title = "Start Daemon"
        }
    }

    // MARK: - Schedule CRUD

    private func showNewScheduleDialog(prefilledDate: Date?) {
        guard !projects.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "New Schedule"
        alert.informativeText = ""
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        var y: CGFloat = 300

        func addLabel(_ text: String) {
            y -= 18
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 0, y: y, width: 300, height: 16)
            accessory.addSubview(label)
            y -= 2
        }

        func addPopup(_ items: [String]) -> NSPopUpButton {
            y -= 26
            let popup = NSPopUpButton(frame: NSRect(x: 0, y: y, width: 300, height: 24), pullsDown: false)
            for item in items { popup.addItem(withTitle: item) }
            accessory.addSubview(popup)
            y -= 8
            return popup
        }

        addLabel("Name:")
        y -= 26
        let nameField = NSTextField(frame: NSRect(x: 0, y: y, width: 300, height: 24))
        nameField.placeholderString = "schedule-name"
        accessory.addSubview(nameField)
        y -= 10

        addLabel("Cron Expression:")
        y -= 26
        let cronField = NSTextField(frame: NSRect(x: 0, y: y, width: 300, height: 24))

        // Pre-fill cron from date if provided
        if let date = prefilledDate {
            let cal = Calendar.current
            let minute = cal.component(.minute, from: date)
            let hour = cal.component(.hour, from: date)
            cronField.stringValue = "\(minute) \(hour) * * *"
        } else {
            cronField.placeholderString = "0 9 * * *"
        }
        accessory.addSubview(cronField)
        y -= 4

        // Live preview label
        let previewLabel = NSTextField(labelWithString: "")
        previewLabel.font = .systemFont(ofSize: 10)
        previewLabel.textColor = .tertiaryLabelColor
        y -= 14
        previewLabel.frame = NSRect(x: 0, y: y, width: 300, height: 14)
        accessory.addSubview(previewLabel)
        y -= 6

        addLabel("Type:")
        let typePopup = addPopup(["swarm", "prompt"])

        addLabel("Target (template name):")
        y -= 26
        let targetField = NSTextField(frame: NSRect(x: 0, y: y, width: 300, height: 24))
        targetField.placeholderString = "template-name"
        accessory.addSubview(targetField)
        y -= 10

        addLabel("Project:")
        let projectPopup = addPopup(projects.map { $0.projectName.isEmpty ? $0.projectRoot : $0.projectName })

        // Update preview on cron field change (using delegate would be ideal, but simpler to just show on dialog open)
        if let expr = try? CronParser.parse(cronField.stringValue),
           let next = CronParser.nextOccurrence(of: expr, after: Date()) {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .short
            previewLabel.stringValue = "Next: \(fmt.string(from: next))"
        }

        alert.accessoryView = accessory
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let cron = cronField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !cron.isEmpty else { return }
        let type = typePopup.titleOfSelectedItem ?? "swarm"
        let target = targetField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }

        let projectIdx = projectPopup.indexOfSelectedItem
        guard projectIdx >= 0, projectIdx < projects.count else { return }
        let ctx = projects[projectIdx]

        let ppgDir = (ctx.projectRoot as NSString).appendingPathComponent(".ppg")
        let fm = FileManager.default
        if !fm.fileExists(atPath: ppgDir) {
            try? fm.createDirectory(atPath: ppgDir, withIntermediateDirectories: true)
        }

        let filePath = (ppgDir as NSString).appendingPathComponent("schedules.yaml")
        let entry = "  - name: \(name)\n    \(type): \(target)\n    cron: '\(cron)'\n"

        do {
            if fm.fileExists(atPath: filePath),
               let existing = try? String(contentsOfFile: filePath, encoding: .utf8) {
                let updated = existing.hasSuffix("\n") ? existing + entry : existing + "\n" + entry
                try updated.write(toFile: filePath, atomically: true, encoding: .utf8)
            } else {
                let content = "schedules:\n" + entry
                try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            }
            configure(projects: projects)
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Failed to Create"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }

    private func showEditScheduleDialog(at index: Int) {
        guard index < schedules.count, !projects.isEmpty else { return }
        let schedule = schedules[index]

        let alert = NSAlert()
        alert.messageText = "Edit Schedule"
        alert.informativeText = ""
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        var y: CGFloat = 220

        func addLabel(_ text: String) {
            y -= 18
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 0, y: y, width: 300, height: 16)
            accessory.addSubview(label)
            y -= 2
        }

        addLabel("Name:")
        y -= 26
        let nameField = NSTextField(frame: NSRect(x: 0, y: y, width: 300, height: 24))
        nameField.stringValue = schedule.name
        accessory.addSubview(nameField)
        y -= 10

        addLabel("Cron Expression:")
        y -= 26
        let cronField = NSTextField(frame: NSRect(x: 0, y: y, width: 300, height: 24))
        cronField.stringValue = schedule.cronExpression
        accessory.addSubview(cronField)
        y -= 10

        addLabel("Type:")
        y -= 26
        let typePopup = NSPopUpButton(frame: NSRect(x: 0, y: y, width: 300, height: 24), pullsDown: false)
        typePopup.addItem(withTitle: "swarm")
        typePopup.addItem(withTitle: "prompt")
        typePopup.selectItem(withTitle: schedule.type)
        accessory.addSubview(typePopup)
        y -= 10

        addLabel("Target:")
        y -= 26
        let targetField = NSTextField(frame: NSRect(x: 0, y: y, width: 300, height: 24))
        targetField.stringValue = schedule.target
        accessory.addSubview(targetField)

        alert.accessoryView = accessory
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let newName = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { return }
        let newCron = cronField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !newCron.isEmpty else { return }
        let newType = typePopup.titleOfSelectedItem ?? schedule.type
        let newTarget = targetField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !newTarget.isEmpty else { return }

        guard let content = try? String(contentsOfFile: schedule.filePath, encoding: .utf8) else { return }
        let withoutOld = removeScheduleEntry(named: schedule.name, from: content)
        let newEntry = "  - name: \(newName)\n    \(newType): \(newTarget)\n    cron: '\(newCron)'\n"
        let updated = withoutOld.hasSuffix("\n") ? withoutOld + newEntry : withoutOld + "\n" + newEntry

        do {
            try updated.write(toFile: schedule.filePath, atomically: true, encoding: .utf8)
            configure(projects: projects)
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Failed to Save"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }

    /// Remove a named schedule entry from the YAML content.
    private func removeScheduleEntry(named name: String, from content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        var skipping = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") && trimmed.contains("name:") && trimmed.contains(name) {
                skipping = true; continue
            }
            if trimmed.hasPrefix("- name:") && Self.yamlValue(trimmed.replacingOccurrences(of: "- ", with: "")) == name {
                skipping = true; continue
            }
            if trimmed == "- name: \(name)" || trimmed == "- name: '\(name)'" || trimmed == "- name: \"\(name)\"" {
                skipping = true; continue
            }
            if skipping {
                if trimmed.hasPrefix("- ") || (!line.hasPrefix(" ") && !line.hasPrefix("\t") && !trimmed.isEmpty && !trimmed.hasPrefix("#")) {
                    skipping = false
                } else {
                    continue
                }
            }
            result.append(line)
        }
        return result.joined(separator: "\n")
    }
}

// MARK: - CalendarMonthView

class CalendarMonthView: NSView {

    var onDayClicked: ((Date) -> Void)?
    var onEventClicked: ((CalendarEvent, NSView) -> Void)?

    private let dayHeaders = ["S", "M", "T", "W", "T", "F", "S"]
    private var dayCells: [DayCellView] = []
    private var headerLabels: [NSTextField] = []
    private let gridContainer = NSView()
    private let headerRow = NSView()

    private var currentDate = Date()
    private var events: [CalendarEvent] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupGrid()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGrid()
    }

    func configure(currentDate: Date, events: [CalendarEvent]) {
        self.currentDate = currentDate
        self.events = events
        layoutDays()
    }

    private func setupGrid() {
        wantsLayer = true

        // Day-of-week headers
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerRow)

        for (_, day) in dayHeaders.enumerated() {
            let label = NSTextField(labelWithString: day)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .tertiaryLabelColor
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            headerRow.addSubview(label)
            headerLabels.append(label)
        }

        // Grid of 42 cells (6 rows x 7 cols)
        gridContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gridContainer)

        for _ in 0..<42 {
            let cell = DayCellView()
            cell.translatesAutoresizingMaskIntoConstraints = false
            gridContainer.addSubview(cell)
            dayCells.append(cell)
        }

        NSLayoutConstraint.activate([
            headerRow.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            headerRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerRow.heightAnchor.constraint(equalToConstant: 20),

            gridContainer.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 2),
            gridContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            gridContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            gridContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let cellW = w / 7.0

        // Position header labels
        for (i, label) in headerLabels.enumerated() {
            label.frame = NSRect(x: CGFloat(i) * cellW, y: 0, width: cellW, height: 20)
        }

        // Position day cells
        let gridH = gridContainer.bounds.height
        let cellH = gridH / 6.0
        for i in 0..<42 {
            let row = i / 7
            let col = i % 7
            let x = CGFloat(col) * cellW
            let y = gridH - CGFloat(row + 1) * cellH
            dayCells[i].frame = NSRect(x: x, y: y, width: cellW, height: cellH)
        }
    }

    private func layoutDays() {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: currentDate)
        let firstOfMonth = cal.date(from: comps)!
        let currentMonth = cal.component(.month, from: currentDate)

        let firstWeekday = cal.component(.weekday, from: firstOfMonth) // 1=Sun
        let startOffset = -(firstWeekday - cal.firstWeekday + 7) % 7
        let gridStart = cal.date(byAdding: .day, value: startOffset, to: firstOfMonth)!

        let today = cal.startOfDay(for: Date())

        for i in 0..<42 {
            let cellDate = cal.date(byAdding: .day, value: i, to: gridStart)!
            let cellMonth = cal.component(.month, from: cellDate)
            let isCurrentMonth = cellMonth == currentMonth
            let isToday = cal.isDate(cellDate, inSameDayAs: today)

            // Find events for this day
            let dayStart = cal.startOfDay(for: cellDate)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
            let dayEvents = events.filter { $0.date >= dayStart && $0.date < dayEnd }

            dayCells[i].configure(
                day: cal.component(.day, from: cellDate),
                date: cellDate,
                isCurrentMonth: isCurrentMonth,
                isToday: isToday,
                events: dayEvents
            )
            dayCells[i].onClicked = { [weak self] date in
                self?.onDayClicked?(date)
            }
            dayCells[i].onEventClicked = { [weak self] event, view in
                self?.onEventClicked?(event, view)
            }
        }
    }
}

// MARK: - DayCellView (Month Grid Cell)

private class DayCellView: NSView {

    var onClicked: ((Date) -> Void)?
    var onEventClicked: ((CalendarEvent, NSView) -> Void)?

    private let dayLabel = NSTextField(labelWithString: "")
    private var eventPills: [EventPillView] = []
    private let moreLabel = NSTextField(labelWithString: "")
    private var cellDate = Date()
    private var isToday = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        dayLabel.font = .systemFont(ofSize: 11)
        dayLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dayLabel)

        moreLabel.font = .systemFont(ofSize: 9)
        moreLabel.textColor = .tertiaryLabelColor
        moreLabel.translatesAutoresizingMaskIntoConstraints = false
        moreLabel.isHidden = true
        addSubview(moreLabel)

        NSLayoutConstraint.activate([
            dayLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            dayLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(cellClicked))
        addGestureRecognizer(click)
    }

    func configure(day: Int, date: Date, isCurrentMonth: Bool, isToday: Bool, events: [CalendarEvent]) {
        self.cellDate = date
        self.isToday = isToday
        dayLabel.stringValue = "\(day)"
        dayLabel.textColor = isCurrentMonth ? Theme.primaryText : .tertiaryLabelColor

        if isToday {
            dayLabel.font = .boldSystemFont(ofSize: 11)
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        } else {
            dayLabel.font = .systemFont(ofSize: 11)
            layer?.backgroundColor = nil
        }

        // Clear old pills
        eventPills.forEach { $0.removeFromSuperview() }
        eventPills.removeAll()
        moreLabel.isHidden = true

        // Show up to 3 event pills
        let maxVisible = 3
        let unique = deduplicateEvents(events)
        let visible = Array(unique.prefix(maxVisible))

        var pillY: CGFloat = bounds.height - 20

        for event in visible {
            let pill = EventPillView()
            pill.configure(event: event)
            pill.frame = NSRect(x: 2, y: pillY - 14, width: bounds.width - 4, height: 14)
            pill.autoresizingMask = [.width]
            pill.onClicked = { [weak self] ev in
                self?.onEventClicked?(ev, pill)
            }
            addSubview(pill)
            eventPills.append(pill)
            pillY -= 15
        }

        if unique.count > maxVisible {
            moreLabel.stringValue = "+\(unique.count - maxVisible) more"
            moreLabel.isHidden = false
            moreLabel.frame = NSRect(x: 4, y: pillY - 12, width: bounds.width - 8, height: 12)
        }
    }

    override func layout() {
        super.layout()
        // Reposition pills on resize
        var pillY: CGFloat = bounds.height - 20
        for pill in eventPills {
            pill.frame = NSRect(x: 2, y: pillY - 14, width: bounds.width - 4, height: 14)
            pillY -= 15
        }
        if !moreLabel.isHidden {
            moreLabel.frame = NSRect(x: 4, y: pillY - 12, width: bounds.width - 8, height: 12)
        }
    }

    private func deduplicateEvents(_ events: [CalendarEvent]) -> [CalendarEvent] {
        // Group high-frequency events by schedule name
        var seen = Set<String>()
        var result: [CalendarEvent] = []
        for event in events {
            let key = "\(event.schedule.name)-\(event.schedule.filePath)"
            if event.isHighFrequency {
                if !seen.contains(key) {
                    seen.insert(key)
                    result.append(event)
                }
            } else {
                if !seen.contains(key) {
                    seen.insert(key)
                    result.append(event)
                }
            }
        }
        return result
    }

    @objc private func cellClicked() {
        onClicked?(cellDate)
    }
}

// MARK: - EventPillView

private class EventPillView: NSView {

    var onClicked: ((CalendarEvent) -> Void)?
    private var event: CalendarEvent?
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 3

        label.font = .systemFont(ofSize: 9, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(pillClicked))
        addGestureRecognizer(click)
    }

    func configure(event: CalendarEvent) {
        self.event = event
        let typeIcon = event.schedule.type == "swarm" ? "S" : "P"
        let suffix = event.isHighFrequency ? " (recurring)" : ""
        label.stringValue = "[\(typeIcon)] \(event.schedule.name)\(suffix)"
        layer?.backgroundColor = event.color.withAlphaComponent(0.85).cgColor
    }

    @objc private func pillClicked() {
        guard let event = event else { return }
        onClicked?(event)
    }
}

// MARK: - CalendarWeekView

class CalendarWeekView: NSView {

    var onEventClicked: ((CalendarEvent, NSView) -> Void)?
    var onEmptySlotClicked: ((Date) -> Void)?

    private let scrollView = NSScrollView()
    private let contentView = NSView()
    private let headerRow = NSView()
    private let gutterWidth: CGFloat = 50
    private let hourHeight: CGFloat = 50
    private let headerHeight: CGFloat = 28
    private var nowLine: NSView?
    private var eventViews: [NSView] = []

    private var currentDate = Date()
    private var events: [CalendarEvent] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    func configure(currentDate: Date, events: [CalendarEvent]) {
        self.currentDate = currentDate
        self.events = events
        layoutWeek()
    }

    private func setupView() {
        wantsLayer = true

        // Header row (day labels)
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerRow)

        // Scrollable time grid
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        addSubview(scrollView)

        let totalHeight = hourHeight * 24
        contentView.frame = NSRect(x: 0, y: 0, width: 1, height: totalHeight)
        scrollView.documentView = contentView

        NSLayoutConstraint.activate([
            headerRow.topAnchor.constraint(equalTo: topAnchor),
            headerRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerRow.heightAnchor.constraint(equalToConstant: headerHeight),

            scrollView.topAnchor.constraint(equalTo: headerRow.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func layoutWeek() {
        // Clear previous
        contentView.subviews.forEach { $0.removeFromSuperview() }
        headerRow.subviews.forEach { $0.removeFromSuperview() }
        eventViews.removeAll()

        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: currentDate)
        let startOffset = -(weekday - cal.firstWeekday + 7) % 7
        let weekStart = cal.date(byAdding: .day, value: startOffset, to: currentDate)!

        let totalHeight = hourHeight * 24
        let width = bounds.width
        contentView.frame = NSRect(x: 0, y: 0, width: max(width, 100), height: totalHeight)

        let dayWidth = (width - gutterWidth) / 7.0
        let today = cal.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE d"

        // Draw day headers
        for col in 0..<7 {
            let day = cal.date(byAdding: .day, value: col, to: weekStart)!
            let isToday = cal.isDate(day, inSameDayAs: today)
            let label = NSTextField(labelWithString: fmt.string(from: day))
            label.font = isToday ? .boldSystemFont(ofSize: 11) : .systemFont(ofSize: 11)
            label.textColor = isToday ? .controlAccentColor : Theme.primaryText
            label.alignment = .center
            label.frame = NSRect(x: gutterWidth + CGFloat(col) * dayWidth, y: 0, width: dayWidth, height: headerHeight)
            headerRow.addSubview(label)
        }

        // Draw hour lines and labels
        for hour in 0..<24 {
            let y = totalHeight - CGFloat(hour + 1) * hourHeight
            let label = NSTextField(labelWithString: String(format: "%02d:00", hour))
            label.font = .systemFont(ofSize: 9)
            label.textColor = .tertiaryLabelColor
            label.alignment = .right
            label.frame = NSRect(x: 0, y: y + hourHeight - 10, width: gutterWidth - 6, height: 14)
            contentView.addSubview(label)

            let line = NSView(frame: NSRect(x: gutterWidth, y: y + hourHeight, width: width - gutterWidth, height: 1))
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
            line.autoresizingMask = [.width]
            contentView.addSubview(line)
        }

        // Draw vertical day separators
        for col in 0...7 {
            let x = gutterWidth + CGFloat(col) * dayWidth
            let sep = NSView(frame: NSRect(x: x, y: 0, width: 1, height: totalHeight))
            sep.wantsLayer = true
            sep.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.2).cgColor
            contentView.addSubview(sep)
        }

        // Place events
        for col in 0..<7 {
            let day = cal.date(byAdding: .day, value: col, to: weekStart)!
            let dayStart = cal.startOfDay(for: day)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
            let dayEvents = events.filter { $0.date >= dayStart && $0.date < dayEnd && !$0.isHighFrequency }

            for event in dayEvents {
                let comps = cal.dateComponents([.hour, .minute], from: event.date)
                let minuteOffset = CGFloat(comps.hour! * 60 + comps.minute!)
                let y = totalHeight - (minuteOffset / 60.0) * hourHeight - 25
                let x = gutterWidth + CGFloat(col) * dayWidth + 2
                let eventW = dayWidth - 4

                let eventView = makeEventBlock(event: event, frame: NSRect(x: x, y: y, width: eventW, height: 25))
                contentView.addSubview(eventView)
                eventViews.append(eventView)
            }

            // High-frequency events: show banner at top of day
            let hfEvents = events.filter { $0.date >= dayStart && $0.date < dayEnd && $0.isHighFrequency }
            var hfSeen = Set<String>()
            for event in hfEvents {
                let key = "\(event.schedule.name)"
                guard !hfSeen.contains(key) else { continue }
                hfSeen.insert(key)
                let x = gutterWidth + CGFloat(col) * dayWidth + 2
                let y = totalHeight - 16
                let eventView = makeEventBlock(event: event, frame: NSRect(x: x, y: y, width: dayWidth - 4, height: 14))
                contentView.addSubview(eventView)
                eventViews.append(eventView)
            }
        }

        // "Now" line
        let nowComps = cal.dateComponents([.hour, .minute], from: Date())
        let nowMinute = CGFloat(nowComps.hour! * 60 + nowComps.minute!)
        let nowY = totalHeight - (nowMinute / 60.0) * hourHeight
        let line = NSView(frame: NSRect(x: gutterWidth, y: nowY, width: width - gutterWidth, height: 2))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.systemRed.cgColor
        line.autoresizingMask = [.width]
        contentView.addSubview(line)
        nowLine = line

        // Add click recognizer for empty slots
        let click = NSClickGestureRecognizer(target: self, action: #selector(gridClicked(_:)))
        contentView.addGestureRecognizer(click)

        // Auto-scroll to 8 AM
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let scrollY = totalHeight - 8 * self.hourHeight - self.scrollView.bounds.height / 2
            self.scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, scrollY)))
        }
    }

    private func makeEventBlock(event: CalendarEvent, frame: NSRect) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.cornerRadius = 4
        view.layer?.backgroundColor = event.color.withAlphaComponent(0.85).cgColor

        let label = NSTextField(labelWithString: event.schedule.name)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(eventBlockClicked(_:)))
        view.addGestureRecognizer(click)

        // Store event reference
        objc_setAssociatedObject(view, &CalendarWeekView.eventKey, event.schedule.name, .OBJC_ASSOCIATION_RETAIN)
        return view
    }

    private static var eventKey: UInt8 = 0

    @objc private func eventBlockClicked(_ sender: NSClickGestureRecognizer) {
        guard let view = sender.view,
              let name = objc_getAssociatedObject(view, &CalendarWeekView.eventKey) as? String,
              let event = events.first(where: { $0.schedule.name == name }) else { return }
        onEventClicked?(event, view)
    }

    @objc private func gridClicked(_ sender: NSClickGestureRecognizer) {
        let location = sender.location(in: contentView)
        let totalHeight = hourHeight * 24
        let width = bounds.width
        let dayWidth = (width - gutterWidth) / 7.0

        guard location.x > gutterWidth else { return }
        let col = Int((location.x - gutterWidth) / dayWidth)
        guard col >= 0, col < 7 else { return }

        let minuteFromTop = (totalHeight - location.y) / hourHeight * 60
        let hour = Int(minuteFromTop / 60)
        let minute = (Int(minuteFromTop) % 60 / 30) * 30 // Snap to 30min

        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: currentDate)
        let startOffset = -(weekday - cal.firstWeekday + 7) % 7
        let weekStart = cal.date(byAdding: .day, value: startOffset, to: currentDate)!
        let clickedDay = cal.date(byAdding: .day, value: col, to: weekStart)!

        var comps = cal.dateComponents([.year, .month, .day], from: clickedDay)
        comps.hour = max(0, min(23, hour))
        comps.minute = max(0, min(59, minute))

        if let date = cal.date(from: comps) {
            onEmptySlotClicked?(date)
        }
    }

    override func layout() {
        super.layout()
        layoutWeek()
    }
}

// MARK: - CalendarDayView

class CalendarDayView: NSView {

    var onEventClicked: ((CalendarEvent, NSView) -> Void)?
    var onEmptySlotClicked: ((Date) -> Void)?

    private let scrollView = NSScrollView()
    private let contentView = NSView()
    private let gutterWidth: CGFloat = 60
    private let hourHeight: CGFloat = 60
    private var eventViews: [NSView] = []

    private var currentDate = Date()
    private var events: [CalendarEvent] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    func configure(currentDate: Date, events: [CalendarEvent]) {
        self.currentDate = currentDate
        self.events = events
        layoutDay()
    }

    private func setupView() {
        wantsLayer = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        addSubview(scrollView)

        let totalHeight = hourHeight * 24
        contentView.frame = NSRect(x: 0, y: 0, width: 1, height: totalHeight)
        scrollView.documentView = contentView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func layoutDay() {
        contentView.subviews.forEach { $0.removeFromSuperview() }
        eventViews.removeAll()

        let cal = Calendar.current
        let totalHeight = hourHeight * 24
        let width = bounds.width
        contentView.frame = NSRect(x: 0, y: 0, width: max(width, 100), height: totalHeight)

        let dayStart = cal.startOfDay(for: currentDate)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!

        // Hour lines and labels
        for hour in 0..<24 {
            let y = totalHeight - CGFloat(hour + 1) * hourHeight
            let label = NSTextField(labelWithString: String(format: "%02d:00", hour))
            label.font = .systemFont(ofSize: 10)
            label.textColor = .tertiaryLabelColor
            label.alignment = .right
            label.frame = NSRect(x: 0, y: y + hourHeight - 10, width: gutterWidth - 8, height: 14)
            contentView.addSubview(label)

            let line = NSView(frame: NSRect(x: gutterWidth, y: y + hourHeight, width: width - gutterWidth, height: 1))
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
            line.autoresizingMask = [.width]
            contentView.addSubview(line)
        }

        // Events for this day
        let dayEvents = events.filter { $0.date >= dayStart && $0.date < dayEnd && !$0.isHighFrequency }
        let eventWidth = width - gutterWidth - 20

        for event in dayEvents {
            let comps = cal.dateComponents([.hour, .minute], from: event.date)
            let minuteOffset = CGFloat(comps.hour! * 60 + comps.minute!)
            let y = totalHeight - (minuteOffset / 60.0) * hourHeight - 30

            let view = NSView(frame: NSRect(x: gutterWidth + 4, y: y, width: eventWidth, height: 30))
            view.wantsLayer = true
            view.layer?.cornerRadius = 5
            view.layer?.backgroundColor = event.color.withAlphaComponent(0.85).cgColor

            let typeIcon = event.schedule.type == "swarm" ? "S" : "P"
            let nameLabel = NSTextField(labelWithString: "[\(typeIcon)] \(event.schedule.name)")
            nameLabel.font = .systemFont(ofSize: 11, weight: .medium)
            nameLabel.textColor = .white
            nameLabel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(nameLabel)

            let timeStr = String(format: "%02d:%02d", comps.hour!, comps.minute!)
            let detailLabel = NSTextField(labelWithString: "\(timeStr) - \(event.schedule.target) (\(event.schedule.projectName))")
            detailLabel.font = .systemFont(ofSize: 9)
            detailLabel.textColor = NSColor.white.withAlphaComponent(0.8)
            detailLabel.lineBreakMode = .byTruncatingTail
            detailLabel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(detailLabel)

            NSLayoutConstraint.activate([
                nameLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 3),
                nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
                nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
                detailLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -3),
                detailLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
                detailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            ])

            let click = NSClickGestureRecognizer(target: self, action: #selector(eventClicked(_:)))
            view.addGestureRecognizer(click)
            objc_setAssociatedObject(view, &CalendarDayView.eventKey, event.schedule.name, .OBJC_ASSOCIATION_RETAIN)

            contentView.addSubview(view)
            eventViews.append(view)
        }

        // High-frequency banners
        let hfEvents = events.filter { $0.date >= dayStart && $0.date < dayEnd && $0.isHighFrequency }
        var hfSeen = Set<String>()
        var hfY = totalHeight - 4.0
        for event in hfEvents {
            let key = event.schedule.name
            guard !hfSeen.contains(key) else { continue }
            hfSeen.insert(key)
            hfY -= 18
            let view = NSView(frame: NSRect(x: gutterWidth + 4, y: hfY, width: eventWidth, height: 16))
            view.wantsLayer = true
            view.layer?.cornerRadius = 3
            view.layer?.backgroundColor = event.color.withAlphaComponent(0.7).cgColor
            let label = NSTextField(labelWithString: "\(event.schedule.name) (high-frequency)")
            label.font = .systemFont(ofSize: 9, weight: .medium)
            label.textColor = .white
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            contentView.addSubview(view)
        }

        // "Now" line
        if cal.isDate(currentDate, inSameDayAs: Date()) {
            let nowComps = cal.dateComponents([.hour, .minute], from: Date())
            let nowMinute = CGFloat(nowComps.hour! * 60 + nowComps.minute!)
            let nowY = totalHeight - (nowMinute / 60.0) * hourHeight
            let line = NSView(frame: NSRect(x: gutterWidth, y: nowY, width: width - gutterWidth, height: 2))
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.systemRed.cgColor
            line.autoresizingMask = [.width]
            contentView.addSubview(line)
        }

        // Click for empty slots
        let click = NSClickGestureRecognizer(target: self, action: #selector(gridClicked(_:)))
        contentView.addGestureRecognizer(click)

        // Scroll to 8 AM
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let scrollY = totalHeight - 8 * self.hourHeight - self.scrollView.bounds.height / 2
            self.scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, scrollY)))
        }
    }

    private static var eventKey: UInt8 = 0

    @objc private func eventClicked(_ sender: NSClickGestureRecognizer) {
        guard let view = sender.view,
              let name = objc_getAssociatedObject(view, &CalendarDayView.eventKey) as? String,
              let event = events.first(where: { $0.schedule.name == name }) else { return }
        onEventClicked?(event, view)
    }

    @objc private func gridClicked(_ sender: NSClickGestureRecognizer) {
        let location = sender.location(in: contentView)
        let totalHeight = hourHeight * 24

        guard location.x > gutterWidth else { return }

        let minuteFromTop = (totalHeight - location.y) / hourHeight * 60
        let hour = Int(minuteFromTop / 60)
        let minute = (Int(minuteFromTop) % 60 / 30) * 30

        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: currentDate)
        comps.hour = max(0, min(23, hour))
        comps.minute = max(0, min(59, minute))

        if let date = cal.date(from: comps) {
            onEmptySlotClicked?(date)
        }
    }

    override func layout() {
        super.layout()
        layoutDay()
    }
}
