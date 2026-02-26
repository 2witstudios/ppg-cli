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

// MARK: - Calendar Event

struct CalendarEvent {
    let schedule: ScheduleInfo
    let date: Date
    let isHighFrequency: Bool   // true when interval < 30 min
    let frequencyLabel: String  // e.g. "every 15 min"
}

// MARK: - View Mode

enum CalendarViewMode: Int {
    case day = 0
    case week = 1
    case month = 2
}

// MARK: - Popover Context (for button wiring)

class PopoverContext: NSObject {
    let popover: NSPopover
    let scheduleName: String
    let filePath: String
    init(popover: NSPopover, scheduleName: String, filePath: String) {
        self.popover = popover
        self.scheduleName = scheduleName
        self.filePath = filePath
    }
}

// MARK: - Cron Field Delegate (for live preview)

class CronFieldDelegate: NSObject, NSTextFieldDelegate {
    private let onChange: () -> Void
    init(onChange: @escaping () -> Void) { self.onChange = onChange }
    func controlTextDidChange(_ obj: Notification) { onChange() }
}

// MARK: - Repeat/Time Change Handler (for live preview + show/hide custom field)

class PickerChangeHandler: NSObject {
    private let onChange: () -> Void
    init(onChange: @escaping () -> Void) { self.onChange = onChange; super.init() }
    @objc func valueChanged(_ sender: Any?) { onChange() }
}

// MARK: - Project Colors

struct ProjectColors {
    private static let palette: [NSColor] = [
        .systemBlue, .systemPurple, .systemTeal, .systemIndigo,
        .systemOrange, .systemPink, .systemGreen, .systemYellow
    ]

    /// Stable djb2 hash — deterministic across app launches (unlike Swift's randomized hashValue).
    private static func stableHash(_ string: String) -> UInt {
        var hash: UInt = 5381
        for byte in string.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt(byte)
        }
        return hash
    }

    static func color(for projectName: String) -> NSColor {
        let hash = stableHash(projectName)
        return palette[Int(hash % UInt(palette.count))]
    }
}

// MARK: - Calendar Layout Constants

private enum CalendarLayout {
    static let hourHeight: CGFloat = 60
    static let weekHeaderHeight: CGFloat = 50
    static let dayHeaderHeight: CGFloat = 40
    static let timeGutterWidth: CGFloat = 56
    /// Total height for a 24-hour time grid + header
    static func totalHeight(headerHeight: CGFloat) -> CGFloat {
        CGFloat(24) * hourHeight + headerHeight
    }
}

// MARK: - Shared Calendar Drawing Helpers

/// Shared drawing routines used by Week and Day calendar views.
enum CalendarDrawing {
    /// Draw the hour grid lines and time labels.
    static func drawHourGrid(
        ctx: CGContext,
        bounds: NSRect,
        gridTop: CGFloat,
        hourHeight: CGFloat,
        gutterWidth: CGFloat,
        timeFontSize: CGFloat = 9
    ) {
        ctx.setLineWidth(0.5)
        for hour in 0...24 {
            let y = gridTop - CGFloat(hour) * hourHeight
            ctx.setStrokeColor(NSColor.separatorColor.withAlphaComponent(hour % 6 == 0 ? 0.5 : 0.2).cgColor)
            ctx.move(to: CGPoint(x: gutterWidth, y: y))
            ctx.addLine(to: CGPoint(x: bounds.width, y: y))
            ctx.strokePath()

            if hour < 24 {
                let h = hour == 0 ? "12 AM" : hour < 12 ? "\(hour) AM" : hour == 12 ? "12 PM" : "\(hour - 12) PM"
                let timeAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: timeFontSize, weight: .regular),
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]
                NSAttributedString(string: h, attributes: timeAttrs).draw(at: NSPoint(x: 4, y: y - timeFontSize * 0.7))
            }
        }
    }

    /// Draw the red current-time indicator line with a dot.
    static func drawCurrentTimeLine(
        ctx: CGContext,
        gridTop: CGFloat,
        hourHeight: CGFloat,
        leftX: CGFloat,
        rightX: CGFloat,
        dotX: CGFloat,
        lineWidth: CGFloat = 1.5,
        dotRadius: CGFloat = 4
    ) {
        let now = Date()
        let cal = Calendar.current
        let nowHour = cal.component(.hour, from: now)
        let nowMinute = cal.component(.minute, from: now)
        let nowY = gridTop - (CGFloat(nowHour) + CGFloat(nowMinute) / 60.0) * hourHeight

        ctx.setStrokeColor(NSColor.systemRed.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.move(to: CGPoint(x: leftX, y: nowY))
        ctx.addLine(to: CGPoint(x: rightX, y: nowY))
        ctx.strokePath()

        ctx.setFillColor(NSColor.systemRed.cgColor)
        ctx.fillEllipse(in: NSRect(x: dotX - dotRadius, y: nowY - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
    }

    /// Draw a high-frequency "all-day stripe" event.
    static func drawHighFrequencyStripe(
        ctx: CGContext,
        rect: NSRect,
        color: NSColor,
        label: String,
        gridTop: CGFloat,
        fontSize: CGFloat = 10
    ) {
        ctx.setFillColor(color.withAlphaComponent(0.06).cgColor)
        let path = CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.setStrokeColor(color.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(path)
        ctx.strokePath()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: color
        ]
        NSAttributedString(string: label, attributes: attrs).draw(at: NSPoint(x: rect.minX + 4, y: gridTop - fontSize - 8))
    }

    /// Draw a normal (timed) event block with left accent bar.
    static func drawTimedEvent(
        ctx: CGContext,
        rect: NSRect,
        color: NSColor,
        label: String,
        isHovered: Bool,
        fontSize: CGFloat = 10
    ) {
        ctx.setFillColor(color.withAlphaComponent(isHovered ? 0.25 : 0.15).cgColor)
        let path = CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()

        // Left accent bar
        ctx.setFillColor(color.cgColor)
        ctx.fill(NSRect(x: rect.minX, y: rect.minY, width: 3, height: rect.height))

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: color
        ]
        let attrStr = NSAttributedString(string: label, attributes: attrs)
        let textY = rect.minY + max((rect.height - fontSize - 4) / 2, 2)
        attrStr.draw(in: NSRect(x: rect.minX + 6, y: textY, width: rect.width - 10, height: fontSize + 4))
    }

    /// Compute the typeIcon prefix for a schedule.
    static func typeIcon(for schedule: ScheduleInfo) -> String {
        schedule.type == "swarm" ? "S" : "P"
    }
}

// MARK: - SchedulesView (Calendar)

class SchedulesView: NSView {

    // Header
    private let headerBar = NSView()
    private let titleLabel = NSTextField(labelWithString: "Calendar")
    private let daemonDot = NSView()
    private let daemonButton = NSButton()
    private let viewSwitcher = NSSegmentedControl()
    private let prevButton = NSButton()
    private let todayButton = NSButton()
    private let nextButton = NSButton()
    private let dateLabel = NSTextField(labelWithString: "")
    private let newButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "")

    // State
    private var schedules: [ScheduleInfo] = []
    private var projects: [ProjectContext] = []
    private var daemonRunning = false
    private var currentDate = Date()
    private var viewMode: CalendarViewMode = .month

    // Calendar body
    private let calendarScrollView = NSScrollView()
    private let calendarContainer = NSView()
    private var monthView: MonthCalendarView?
    private var weekView: WeekCalendarView?
    private var dayView: DayCalendarView?

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
        checkDaemonStatus()
        refreshCalendar()
    }

    // MARK: - File Scanning (preserved from original)

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

    // MARK: - Simple YAML Parser (preserved)

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
                if let c = current { results.append(c); current = nil }
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
                if !afterDash.isEmpty { applyKeyValue(afterDash, to: &current!, inVars: &inVars) }
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
                entry.vars.append((parts[0].trimmingCharacters(in: .whitespaces), stripQuotes(parts[1].trimmingCharacters(in: .whitespaces))))
            }
        }
    }

    static func yamlValue(_ line: String) -> String {
        guard let colonIdx = line.range(of: ":") else { return "" }
        return stripQuotes(String(line[colonIdx.upperBound...]).trimmingCharacters(in: .whitespaces))
    }

    private static func stripQuotes(_ s: String) -> String {
        var v = s
        if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        return v
    }

    /// Extract the `name` value from an inline YAML flow mapping like `- { name: foo, cron: ... }`.
    private static func extractInlineName(_ line: String) -> String? {
        // Find "name:" and extract the value up to the next comma or closing brace
        guard let nameRange = line.range(of: "name:") else { return nil }
        let afterName = line[nameRange.upperBound...].trimmingCharacters(in: .whitespaces)
        let endIdx = afterName.firstIndex(where: { $0 == "," || $0 == "}" }) ?? afterName.endIndex
        return stripQuotes(String(afterName[afterName.startIndex..<endIdx]).trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Daemon Status

    private func checkDaemonStatus() {
        guard let ctx = projects.first else { updateDaemonUI(running: false); return }
        let projectRoot = ctx.projectRoot
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = PPGService.shared.runPPGCommand("cron status --json", projectRoot: projectRoot)
            let running = result.stdout.contains("\"running\":true") || result.stdout.contains("\"running\": true")
            DispatchQueue.main.async { self?.updateDaemonUI(running: running) }
        }
    }

    private func updateDaemonUI(running: Bool) {
        daemonRunning = running
        daemonDot.wantsLayer = true
        daemonDot.layer?.cornerRadius = 5
        daemonDot.layer?.backgroundColor = (running ? NSColor.systemGreen : NSColor.systemRed).cgColor
        daemonButton.title = running ? "Stop" : "Start"
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = Theme.contentBackground.resolvedCGColor(for: effectiveAppearance)

        // --- Header Bar ---
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerBar)

        // Title
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.textColor = Theme.primaryText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(titleLabel)

        // Daemon dot
        daemonDot.translatesAutoresizingMaskIntoConstraints = false
        daemonDot.wantsLayer = true
        daemonDot.layer?.cornerRadius = 5
        daemonDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        headerBar.addSubview(daemonDot)

        // Daemon button
        daemonButton.bezelStyle = .accessoryBarAction
        daemonButton.title = "Start"
        daemonButton.font = .systemFont(ofSize: 11)
        daemonButton.isBordered = false
        daemonButton.contentTintColor = Theme.primaryText
        daemonButton.target = self
        daemonButton.action = #selector(daemonToggleClicked)
        daemonButton.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(daemonButton)

        // View switcher: Day | Week | Month
        viewSwitcher.segmentCount = 3
        viewSwitcher.setLabel("Day", forSegment: 0)
        viewSwitcher.setLabel("Week", forSegment: 1)
        viewSwitcher.setLabel("Month", forSegment: 2)
        viewSwitcher.setWidth(50, forSegment: 0)
        viewSwitcher.setWidth(50, forSegment: 1)
        viewSwitcher.setWidth(55, forSegment: 2)
        viewSwitcher.selectedSegment = 2 // default: month
        viewSwitcher.target = self
        viewSwitcher.action = #selector(viewModeChanged)
        viewSwitcher.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(viewSwitcher)

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

        // New Schedule button
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

        let headerSep = NSBox()
        headerSep.boxType = .separator
        headerSep.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(headerSep)

        // --- Calendar Body ---
        calendarScrollView.translatesAutoresizingMaskIntoConstraints = false
        calendarScrollView.hasVerticalScroller = true
        calendarScrollView.hasHorizontalScroller = false
        calendarScrollView.drawsBackground = false
        calendarScrollView.autohidesScrollers = true
        addSubview(calendarScrollView)

        calendarContainer.translatesAutoresizingMaskIntoConstraints = false
        calendarScrollView.documentView = calendarContainer

        // Empty hint banner (overlay inside calendar)
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        calendarContainer.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            daemonDot.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            daemonDot.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            daemonDot.widthAnchor.constraint(equalToConstant: 10),
            daemonDot.heightAnchor.constraint(equalToConstant: 10),

            daemonButton.leadingAnchor.constraint(equalTo: daemonDot.trailingAnchor, constant: 4),
            daemonButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            viewSwitcher.centerXAnchor.constraint(equalTo: headerBar.centerXAnchor),
            viewSwitcher.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            prevButton.leadingAnchor.constraint(equalTo: viewSwitcher.trailingAnchor, constant: 16),
            prevButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            todayButton.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 4),
            todayButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            nextButton.leadingAnchor.constraint(equalTo: todayButton.trailingAnchor, constant: 4),
            nextButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            dateLabel.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 12),
            dateLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            newButton.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -8),
            newButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            headerSep.bottomAnchor.constraint(equalTo: headerBar.bottomAnchor),
            headerSep.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            headerSep.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),

            calendarScrollView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            calendarScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            calendarScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            calendarScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: calendarContainer.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: calendarContainer.topAnchor, constant: 12),
        ])

        updateDateLabel()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.contentBackground.resolvedCGColor(for: effectiveAppearance)
    }

    // MARK: - Calendar Refresh

    private func refreshCalendar() {
        updateDateLabel()

        // Remove old views
        monthView?.removeFromSuperview(); monthView = nil
        weekView?.removeFromSuperview(); weekView = nil
        dayView?.removeFromSuperview(); dayView = nil

        let events = generateEvents()
        let owner = self

        switch viewMode {
        case .month:
            let mv = MonthCalendarView(date: currentDate, events: events, owner: owner)
            mv.translatesAutoresizingMaskIntoConstraints = false
            calendarContainer.addSubview(mv)
            NSLayoutConstraint.activate([
                mv.topAnchor.constraint(equalTo: calendarContainer.topAnchor),
                mv.leadingAnchor.constraint(equalTo: calendarContainer.leadingAnchor),
                mv.trailingAnchor.constraint(equalTo: calendarContainer.trailingAnchor),
                mv.widthAnchor.constraint(equalTo: calendarScrollView.widthAnchor),
                mv.heightAnchor.constraint(greaterThanOrEqualTo: calendarScrollView.heightAnchor),
                mv.bottomAnchor.constraint(equalTo: calendarContainer.bottomAnchor),
            ])
            monthView = mv

        case .week:
            let wv = WeekCalendarView(date: currentDate, events: events, owner: owner)
            wv.translatesAutoresizingMaskIntoConstraints = false
            calendarContainer.addSubview(wv)
            NSLayoutConstraint.activate([
                wv.topAnchor.constraint(equalTo: calendarContainer.topAnchor),
                wv.leadingAnchor.constraint(equalTo: calendarContainer.leadingAnchor),
                wv.trailingAnchor.constraint(equalTo: calendarContainer.trailingAnchor),
                wv.widthAnchor.constraint(equalTo: calendarScrollView.widthAnchor),
                wv.heightAnchor.constraint(equalToConstant: CalendarLayout.totalHeight(headerHeight: CalendarLayout.weekHeaderHeight)),
                wv.bottomAnchor.constraint(equalTo: calendarContainer.bottomAnchor),
            ])
            weekView = wv

        case .day:
            let dv = DayCalendarView(date: currentDate, events: events, owner: owner)
            dv.translatesAutoresizingMaskIntoConstraints = false
            calendarContainer.addSubview(dv)
            NSLayoutConstraint.activate([
                dv.topAnchor.constraint(equalTo: calendarContainer.topAnchor),
                dv.leadingAnchor.constraint(equalTo: calendarContainer.leadingAnchor),
                dv.trailingAnchor.constraint(equalTo: calendarContainer.trailingAnchor),
                dv.widthAnchor.constraint(equalTo: calendarScrollView.widthAnchor),
                dv.heightAnchor.constraint(equalToConstant: CalendarLayout.totalHeight(headerHeight: CalendarLayout.dayHeaderHeight)),
                dv.bottomAnchor.constraint(equalTo: calendarContainer.bottomAnchor),
            ])
            dayView = dv
        }

        // Scroll to current time in day/week views
        if viewMode == .week || viewMode == .day {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let cal = Calendar.current
                let hour = cal.component(.hour, from: Date())
                let yOffset = max(0, CGFloat(hour) * 60.0 - 100.0)
                self.calendarScrollView.contentView.scroll(to: NSPoint(x: 0, y: yOffset))
            }
        }
    }

    // MARK: - Generate Events from Schedules

    private func generateEvents() -> [CalendarEvent] {
        let cal = Calendar.current
        var events: [CalendarEvent] = []

        for schedule in schedules {
            let (isHF, freqLabel) = CronParser.isHighFrequency(schedule.cronExpression)
            let (start, end) = dateRangeForCurrentView()

            if isHF {
                // For high-frequency schedules, generate one event per matching day in the range.
                // Check month/DOM/DOW filters so expressions like "*/5 * * * 1" only show on Mondays.
                guard let parsed = CronParser.parse(schedule.cronExpression) else { continue }
                var dayStart = cal.startOfDay(for: start)
                while dayStart <= end {
                    let comps = cal.dateComponents([.day, .month, .weekday], from: dayStart)
                    let day = comps.day ?? 1
                    let month = comps.month ?? 1
                    let cronDow = ((comps.weekday ?? 1) - 1) % 7

                    let monthMatch = parsed.months.contains(month)
                    let dateMatch: Bool
                    if parsed.domRestricted && parsed.dowRestricted {
                        dateMatch = parsed.daysOfMonth.contains(day) || parsed.daysOfWeek.contains(cronDow)
                    } else {
                        dateMatch = parsed.daysOfMonth.contains(day) && parsed.daysOfWeek.contains(cronDow)
                    }

                    if monthMatch && dateMatch {
                        events.append(CalendarEvent(
                            schedule: schedule,
                            date: dayStart,
                            isHighFrequency: true,
                            frequencyLabel: freqLabel
                        ))
                    }
                    guard let nextDay = cal.date(byAdding: .day, value: 1, to: dayStart) else { break }
                    dayStart = nextDay
                }
            } else {
                let occurrences = CronParser.occurrences(of: schedule.cronExpression, from: start, to: end)
                for date in occurrences {
                    events.append(CalendarEvent(
                        schedule: schedule,
                        date: date,
                        isHighFrequency: false,
                        frequencyLabel: ""
                    ))
                }
            }
        }

        return events
    }

    private func dateRangeForCurrentView() -> (Date, Date) {
        let cal = Calendar.current
        let fallbackEnd = cal.startOfDay(for: currentDate)
        switch viewMode {
        case .day:
            let start = cal.startOfDay(for: currentDate)
            guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return (start, start) }
            return (start, end)
        case .week:
            let weekday = cal.component(.weekday, from: currentDate)
            let offset = (weekday - cal.firstWeekday + 7) % 7
            guard let start = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: currentDate)),
                  let end = cal.date(byAdding: .day, value: 7, to: start) else { return (fallbackEnd, fallbackEnd) }
            return (start, end)
        case .month:
            let comps = cal.dateComponents([.year, .month], from: currentDate)
            guard let start = cal.date(from: comps),
                  let end = cal.date(byAdding: .month, value: 1, to: start) else { return (fallbackEnd, fallbackEnd) }
            return (start, end)
        }
    }

    // MARK: - Date Label

    private func updateDateLabel() {
        let fmt = DateFormatter()
        switch viewMode {
        case .day:
            fmt.dateFormat = "EEEE, MMMM d, yyyy"
        case .week:
            let cal = Calendar.current
            let weekday = cal.component(.weekday, from: currentDate)
            let offset = (weekday - cal.firstWeekday + 7) % 7
            guard let weekStart = cal.date(byAdding: .day, value: -offset, to: currentDate),
                  let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) else {
                dateLabel.stringValue = ""
                return
            }
            let sf = DateFormatter()
            sf.dateFormat = "MMM d"
            let ef = DateFormatter()
            ef.dateFormat = "MMM d, yyyy"
            dateLabel.stringValue = "\(sf.string(from: weekStart)) \u{2013} \(ef.string(from: weekEnd))"
            return
        case .month:
            fmt.dateFormat = "MMMM yyyy"
        }
        dateLabel.stringValue = fmt.string(from: currentDate)
    }

    // MARK: - Actions

    @objc private func viewModeChanged() {
        viewMode = CalendarViewMode(rawValue: viewSwitcher.selectedSegment) ?? .week
        refreshCalendar()
    }

    @objc private func prevClicked() {
        let cal = Calendar.current
        switch viewMode {
        case .day:
            currentDate = cal.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
        case .week:
            currentDate = cal.date(byAdding: .weekOfYear, value: -1, to: currentDate) ?? currentDate
        case .month:
            currentDate = cal.date(byAdding: .month, value: -1, to: currentDate) ?? currentDate
        }
        refreshCalendar()
    }

    @objc private func nextClicked() {
        let cal = Calendar.current
        switch viewMode {
        case .day:
            currentDate = cal.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        case .week:
            currentDate = cal.date(byAdding: .weekOfYear, value: 1, to: currentDate) ?? currentDate
        case .month:
            currentDate = cal.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
        }
        refreshCalendar()
    }

    @objc private func todayClicked() {
        currentDate = Date()
        refreshCalendar()
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
        showScheduleDialog(schedule: nil, prefillDate: nil)
    }

    // MARK: - Schedule Dialog (Create / Edit)

    func showScheduleDialog(schedule: ScheduleInfo?, prefillDate: Date?) {
        guard !projects.isEmpty else { return }
        let isEdit = schedule != nil

        let alert = NSAlert()
        alert.messageText = isEdit ? "Edit Schedule" : "New Schedule"
        alert.informativeText = ""
        alert.addButton(withTitle: isEdit ? "Save" : "Create")
        alert.addButton(withTitle: "Cancel")

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 360))
        var y: CGFloat = 360

        func addLabel(_ text: String) {
            y -= 18
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 0, y: y, width: 300, height: 16)
            accessory.addSubview(label)
            y -= 2
        }

        func addField(_ placeholder: String, value: String = "") -> NSTextField {
            y -= 24
            let field = NSTextField(frame: NSRect(x: 0, y: y, width: 300, height: 24))
            field.placeholderString = placeholder
            field.stringValue = value
            accessory.addSubview(field)
            y -= 10
            return field
        }

        func addPopup(_ items: [String], selected: String? = nil) -> NSPopUpButton {
            y -= 24
            let popup = NSPopUpButton(frame: NSRect(x: 0, y: y, width: 300, height: 24), pullsDown: false)
            for item in items { popup.addItem(withTitle: item) }
            if let sel = selected { popup.selectItem(withTitle: sel) }
            accessory.addSubview(popup)
            y -= 10
            return popup
        }

        addLabel("Name:")
        let nameField = addField("schedule-name", value: schedule?.name ?? "")

        // --- Time picker ---
        addLabel("Time:")
        y -= 24
        let timePicker = NSDatePicker(frame: NSRect(x: 0, y: y, width: 300, height: 24))
        timePicker.datePickerStyle = .textFieldAndStepper
        timePicker.datePickerElements = .hourMinute
        // Set initial time
        do {
            let cal = Calendar.current
            var dateComponents = cal.dateComponents([.year, .month, .day], from: Date())
            if let date = prefillDate {
                dateComponents.hour = cal.component(.hour, from: date)
                dateComponents.minute = cal.component(.minute, from: date)
            } else if let existingCron = schedule?.cronExpression {
                let parts = existingCron.split(separator: " ").map(String.init)
                if parts.count == 5, let m = Int(parts[0]), let h = Int(parts[1]) {
                    dateComponents.hour = h
                    dateComponents.minute = m
                } else {
                    dateComponents.hour = cal.component(.hour, from: Date())
                    dateComponents.minute = 0
                }
            } else {
                dateComponents.hour = cal.component(.hour, from: Date())
                dateComponents.minute = 0
            }
            timePicker.dateValue = cal.date(from: dateComponents) ?? Date()
        }
        accessory.addSubview(timePicker)
        y -= 10

        // --- Repeat dropdown ---
        let repeatOptions = ["Every Day", "Every Weekday (Mon–Fri)", "Every Week", "Every Month", "Hourly", "Custom…"]
        addLabel("Repeat:")
        let repeatPopup = addPopup(repeatOptions)

        // --- Hidden custom cron field (shown only for "Custom…") ---
        // Positioned right below repeat dropdown; y not decremented so hidden = no gap
        let customCronInsertY = y  // where the cron section would start
        let customCronHeight: CGFloat = 54  // label(20) + field(34)

        let cronLabelView = NSTextField(labelWithString: "Cron Expression:")
        cronLabelView.font = .systemFont(ofSize: 11, weight: .medium)
        cronLabelView.textColor = .secondaryLabelColor
        cronLabelView.frame = NSRect(x: 0, y: customCronInsertY - 18, width: 300, height: 16)
        cronLabelView.isHidden = true
        accessory.addSubview(cronLabelView)

        let customCronField = NSTextField(frame: NSRect(x: 0, y: customCronInsertY - 44, width: 300, height: 24))
        customCronField.placeholderString = "0 * * * *"
        customCronField.stringValue = schedule?.cronExpression ?? "0 * * * *"
        customCronField.isHidden = true
        accessory.addSubview(customCronField)

        // Track views added after this point so we can shift them when toggling Custom
        let viewsBelowStartIndex = accessory.subviews.count

        // --- Helper: reverse-map existing cron to repeat index ---
        func repeatIndexFromCron(_ cron: String) -> Int {
            let parts = cron.split(separator: " ").map(String.init)
            guard parts.count == 5 else { return 5 }
            let (_, hour, dom, mon, dow) = (parts[0], parts[1], parts[2], parts[3], parts[4])
            if hour != "*" && dom == "*" && mon == "*" && dow == "*" { return 0 }       // Every Day
            if hour != "*" && dom == "*" && mon == "*" && dow == "1-5" { return 1 }     // Weekday
            if hour != "*" && dom == "*" && mon == "*" && dow != "*" { return 2 }       // Every Week
            if hour != "*" && dom != "*" && mon == "*" && dow == "*" { return 3 }       // Every Month
            if hour == "*" && dom == "*" && mon == "*" && dow == "*" { return 4 }       // Hourly
            return 5                                                                      // Custom
        }

        // Pre-select repeat option when editing
        var customCronVisible = false
        if let existingCron = schedule?.cronExpression {
            let idx = repeatIndexFromCron(existingCron)
            repeatPopup.selectItem(at: idx)
            if idx == 5 {
                // Custom — shift y down to make room, then show
                y -= customCronHeight
                cronLabelView.isHidden = false
                customCronField.isHidden = false
                customCronField.stringValue = existingCron
                customCronVisible = true
            }
        }

        // --- Helper: generate cron from picker state ---
        func cronFromPicker() -> String {
            let cal = Calendar.current
            let h = cal.component(.hour, from: timePicker.dateValue)
            let m = cal.component(.minute, from: timePicker.dateValue)

            switch repeatPopup.indexOfSelectedItem {
            case 0: return "\(m) \(h) * * *"           // Every Day
            case 1: return "\(m) \(h) * * 1-5"         // Every Weekday
            case 2:                                      // Every Week
                let dow = cal.component(.weekday, from: Date()) - 1  // 0=Sun
                return "\(m) \(h) * * \(dow)"
            case 3:                                      // Every Month
                let dom = cal.component(.day, from: Date())
                return "\(m) \(h) \(dom) * *"
            case 4: return "\(m) * * * *"               // Hourly
            case 5: return customCronField.stringValue   // Custom
            default: return "\(m) \(h) * * *"
            }
        }

        // --- Live next-run preview ---
        let previewLabel = NSTextField(labelWithString: "")
        previewLabel.font = .systemFont(ofSize: 10)
        previewLabel.textColor = .tertiaryLabelColor
        previewLabel.frame = NSRect(x: 0, y: y - 14, width: 300, height: 14)
        accessory.addSubview(previewLabel)
        y -= 18

        func updateCronPreview() {
            let cronText = cronFromPicker().trimmingCharacters(in: .whitespaces)
            if let next = CronParser.nextOccurrence(of: cronText, after: Date()) {
                let fmt = DateFormatter()
                fmt.dateStyle = .medium
                fmt.timeStyle = .short
                previewLabel.stringValue = "Next: \(fmt.string(from: next))"
            } else if cronText.isEmpty {
                previewLabel.stringValue = ""
            } else {
                previewLabel.stringValue = "Invalid cron expression"
            }
        }

        // --- Wire up change handlers ---
        let pickerHandler = PickerChangeHandler(onChange: {
            let isCustom = repeatPopup.indexOfSelectedItem == 5
            let wasVisible = !cronLabelView.isHidden
            cronLabelView.isHidden = !isCustom
            customCronField.isHidden = !isCustom

            // Shift views below and resize accessory when toggling Custom
            if isCustom && !wasVisible {
                // Reveal: shift views below down
                for i in viewsBelowStartIndex..<accessory.subviews.count {
                    let v = accessory.subviews[i]
                    if v !== cronLabelView && v !== customCronField {
                        v.frame.origin.y -= customCronHeight
                    }
                }
                accessory.frame.size.height += customCronHeight
            } else if !isCustom && wasVisible {
                // Hide: shift views below back up
                for i in viewsBelowStartIndex..<accessory.subviews.count {
                    let v = accessory.subviews[i]
                    if v !== cronLabelView && v !== customCronField {
                        v.frame.origin.y += customCronHeight
                    }
                }
                accessory.frame.size.height -= customCronHeight
            }
            updateCronPreview()
        })
        repeatPopup.target = pickerHandler
        repeatPopup.action = #selector(PickerChangeHandler.valueChanged(_:))
        timePicker.target = pickerHandler
        timePicker.action = #selector(PickerChangeHandler.valueChanged(_:))
        // Retain the handler
        objc_setAssociatedObject(accessory, "pickerHandler", pickerHandler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // Wire up custom cron field for live preview when typing
        let cronDelegate = CronFieldDelegate(onChange: updateCronPreview)
        customCronField.delegate = cronDelegate
        objc_setAssociatedObject(customCronField, "cronDelegate", cronDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // Show initial preview
        updateCronPreview()

        addLabel("Type:")
        let typePopup = addPopup(["swarm", "prompt"], selected: schedule?.type)

        addLabel("Target (template name):")
        let targetField = addField("template-name", value: schedule?.target ?? "")

        addLabel("Project:")
        let projectNames = projects.map { $0.projectName.isEmpty ? $0.projectRoot : $0.projectName }
        let projectPopup = addPopup(projectNames, selected: nil)
        if let s = schedule, let idx = projects.firstIndex(where: { $0.projectRoot == s.projectRoot }) {
            projectPopup.selectItem(at: idx)
        }

        alert.accessoryView = accessory
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let cron = cronFromPicker().trimmingCharacters(in: .whitespaces)
        guard !cron.isEmpty else { return }
        let type = typePopup.titleOfSelectedItem ?? "swarm"
        let target = targetField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }

        let projectIdx = projectPopup.indexOfSelectedItem
        guard projectIdx >= 0, projectIdx < projects.count else { return }
        let ctx = projects[projectIdx]

        // Preserve existing vars when editing
        let vars: [(String, String)] = isEdit ? (schedule?.vars ?? []) : []

        if isEdit, let oldSchedule = schedule {
            // Atomic edit: remove old + add new in a single file write to prevent data loss
            replaceScheduleEntry(old: oldSchedule, name: name, cron: cron, type: type, target: target, vars: vars, context: ctx)
        } else {
            addScheduleEntry(name: name, cron: cron, type: type, target: target, vars: vars, context: ctx)
        }
    }

    /// Escape a YAML scalar value — quote it if it contains special characters.
    private static func yamlEscape(_ value: String) -> String {
        let needsQuoting = value.isEmpty
            || value.contains(":")
            || value.contains("#")
            || value.contains("{")
            || value.contains("}")
            || value.contains("[")
            || value.contains("]")
            || value.contains(",")
            || value.contains("&")
            || value.contains("*")
            || value.contains("?")
            || value.contains("|")
            || value.contains(">")
            || value.contains("'")
            || value.contains("\"")
            || value.contains("%")
            || value.contains("@")
            || value.contains("`")
            || value.hasPrefix(" ")
            || value.hasSuffix(" ")
        if needsQuoting {
            // Use single quotes, escaping embedded single quotes by doubling them
            return "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
        }
        return value
    }

    private func addScheduleEntry(name: String, cron: String, type: String, target: String, vars: [(String, String)], context: ProjectContext) {
        let ppgDir = (context.projectRoot as NSString).appendingPathComponent(".ppg")
        let fm = FileManager.default
        if !fm.fileExists(atPath: ppgDir) {
            try? fm.createDirectory(atPath: ppgDir, withIntermediateDirectories: true)
        }

        let filePath = (ppgDir as NSString).appendingPathComponent("schedules.yaml")

        // Build properly escaped YAML entry
        var entry = "  - name: \(Self.yamlEscape(name))\n"
        entry += "    \(type): \(Self.yamlEscape(target))\n"
        entry += "    cron: '\(cron)'\n"
        if !vars.isEmpty {
            entry += "    vars:\n"
            for (k, v) in vars {
                entry += "      \(Self.yamlEscape(k)): \(Self.yamlEscape(v))\n"
            }
        }

        do {
            if fm.fileExists(atPath: filePath),
               let existing = try? String(contentsOfFile: filePath, encoding: .utf8) {
                let updated = existing.hasSuffix("\n") ? existing + entry : existing + "\n" + entry
                try updated.write(toFile: filePath, atomically: true, encoding: .utf8)
            } else {
                try ("schedules:\n" + entry).write(toFile: filePath, atomically: true, encoding: .utf8)
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

    /// Atomic replace: removes old entry and appends new entry in a single file write.
    private func replaceScheduleEntry(old: ScheduleInfo, name: String, cron: String, type: String, target: String, vars: [(String, String)], context: ProjectContext) {
        guard let content = try? String(contentsOfFile: old.filePath, encoding: .utf8) else {
            // Fallback: just add the new entry
            addScheduleEntry(name: name, cron: cron, type: type, target: target, vars: vars, context: context)
            return
        }

        // Remove old entry in memory
        let filtered = removeScheduleEntry(named: old.name, from: content)

        // Build new entry
        var entry = "  - name: \(Self.yamlEscape(name))\n"
        entry += "    \(type): \(Self.yamlEscape(target))\n"
        entry += "    cron: '\(cron)'\n"
        if !vars.isEmpty {
            entry += "    vars:\n"
            for (k, v) in vars {
                entry += "      \(Self.yamlEscape(k)): \(Self.yamlEscape(v))\n"
            }
        }

        // Append new entry to filtered content
        let base = filtered.hasSuffix("\n") ? filtered : filtered + "\n"
        let updated = base + entry

        do {
            try updated.write(toFile: old.filePath, atomically: true, encoding: .utf8)
            configure(projects: projects)
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Failed to Update"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }

    // MARK: - Delete Schedule

    func deleteSchedule(_ schedule: ScheduleInfo) {
        let alert = NSAlert()
        alert.messageText = "Delete schedule \"\(schedule.name)\"?"
        alert.informativeText = "This will remove the schedule entry from schedules.yaml."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        deleteScheduleEntry(schedule)
        configure(projects: projects)
    }

    private func deleteScheduleEntry(_ schedule: ScheduleInfo) {
        guard let content = try? String(contentsOfFile: schedule.filePath, encoding: .utf8) else { return }
        let filtered = removeScheduleEntry(named: schedule.name, from: content)

        do {
            if filtered.trimmingCharacters(in: .whitespacesAndNewlines) == "schedules:" ||
               filtered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try FileManager.default.removeItem(atPath: schedule.filePath)
            } else {
                try filtered.write(toFile: schedule.filePath, atomically: true, encoding: .utf8)
            }
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Failed to Delete"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }

    private func removeScheduleEntry(named name: String, from content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        var skipping = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Exact name matching: use yamlValue extraction or literal comparison
            if trimmed.hasPrefix("- name:") && Self.yamlValue(trimmed.replacingOccurrences(of: "- ", with: "")) == name {
                skipping = true; continue
            }
            if trimmed == "- name: \(name)" || trimmed == "- name: '\(name)'" || trimmed == "- name: \"\(name)\"" {
                skipping = true; continue
            }
            // Inline flow style: { name: X, ... }
            if trimmed.hasPrefix("- {") && trimmed.contains("name:") {
                let extracted = Self.extractInlineName(trimmed)
                if extracted == name { skipping = true; continue }
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

    // MARK: - Event Popover

    func showEventPopover(for event: CalendarEvent, relativeTo rect: NSRect, of view: NSView) {
        let vc = NSViewController()
        let popoverView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 200))

        var y: CGFloat = 180

        let nameLabel = NSTextField(labelWithString: event.schedule.name)
        nameLabel.font = .boldSystemFont(ofSize: 14)
        nameLabel.textColor = Theme.primaryText
        nameLabel.frame = NSRect(x: 12, y: y, width: 256, height: 20)
        popoverView.addSubview(nameLabel)
        y -= 24

        let typeIcon = event.schedule.type == "swarm" ? "S" : "P"
        let typeBadge = NSTextField(labelWithString: "[\(typeIcon)] \(event.schedule.type)")
        typeBadge.font = .systemFont(ofSize: 11, weight: .medium)
        typeBadge.textColor = ProjectColors.color(for: event.schedule.projectName)
        typeBadge.frame = NSRect(x: 12, y: y, width: 256, height: 16)
        popoverView.addSubview(typeBadge)
        y -= 20

        let targetLabel = NSTextField(labelWithString: "Target: \(event.schedule.target)")
        targetLabel.font = .systemFont(ofSize: 11)
        targetLabel.textColor = .secondaryLabelColor
        targetLabel.frame = NSRect(x: 12, y: y, width: 256, height: 16)
        popoverView.addSubview(targetLabel)
        y -= 18

        let humanCron = CronParser.humanReadable(event.schedule.cronExpression)
        let cronLabel = NSTextField(labelWithString: "\(humanCron)  (\(event.schedule.cronExpression))")
        cronLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        cronLabel.textColor = .secondaryLabelColor
        cronLabel.frame = NSRect(x: 12, y: y, width: 256, height: 16)
        popoverView.addSubview(cronLabel)
        y -= 18

        let projectLabel = NSTextField(labelWithString: "Project: \(event.schedule.projectName)")
        projectLabel.font = .systemFont(ofSize: 11)
        projectLabel.textColor = .secondaryLabelColor
        projectLabel.frame = NSRect(x: 12, y: y, width: 256, height: 16)
        popoverView.addSubview(projectLabel)
        y -= 22

        if !event.schedule.vars.isEmpty {
            let varsStr = event.schedule.vars.map { "\($0.0)=\($0.1)" }.joined(separator: ", ")
            let varsLabel = NSTextField(labelWithString: "Vars: \(varsStr)")
            varsLabel.font = .systemFont(ofSize: 10)
            varsLabel.textColor = .tertiaryLabelColor
            varsLabel.frame = NSRect(x: 12, y: y, width: 256, height: 14)
            popoverView.addSubview(varsLabel)
            y -= 20
        }

        // Buttons
        let editBtn = NSButton(title: "Edit", target: nil, action: nil)
        editBtn.bezelStyle = .rounded
        editBtn.frame = NSRect(x: 12, y: 10, width: 70, height: 28)
        popoverView.addSubview(editBtn)

        let deleteBtn = NSButton(title: "Delete", target: nil, action: nil)
        deleteBtn.bezelStyle = .rounded
        deleteBtn.contentTintColor = .systemRed
        deleteBtn.frame = NSRect(x: 90, y: 10, width: 70, height: 28)
        popoverView.addSubview(deleteBtn)

        vc.view = popoverView

        let popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 280, height: 200)

        // Wire up button actions via PopoverContext (avoids fragile tag-based index lookup)
        let schedule = event.schedule
        let ctx = PopoverContext(popover: popover, scheduleName: schedule.name, filePath: schedule.filePath)
        editBtn.target = self
        editBtn.action = #selector(editFromPopover(_:))
        editBtn.cell?.representedObject = ctx

        deleteBtn.target = self
        deleteBtn.action = #selector(deleteFromPopover(_:))
        deleteBtn.cell?.representedObject = ctx

        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
    }

    @objc private func editFromPopover(_ sender: NSButton) {
        guard let ctx = sender.cell?.representedObject as? PopoverContext else { return }
        ctx.popover.close()
        guard let schedule = schedules.first(where: { $0.name == ctx.scheduleName && $0.filePath == ctx.filePath }) else { return }
        showScheduleDialog(schedule: schedule, prefillDate: nil)
    }

    @objc private func deleteFromPopover(_ sender: NSButton) {
        guard let ctx = sender.cell?.representedObject as? PopoverContext else { return }
        ctx.popover.close()
        guard let schedule = schedules.first(where: { $0.name == ctx.scheduleName && $0.filePath == ctx.filePath }) else { return }
        deleteSchedule(schedule)
    }

    // MARK: - Time Slot Click

    func handleTimeSlotClick(date: Date) {
        showScheduleDialog(schedule: nil, prefillDate: date)
    }
}

// MARK: - Month Calendar View

class MonthCalendarView: NSView {
    private let date: Date
    private let events: [CalendarEvent]
    private weak var owner: SchedulesView?
    private let cal = Calendar.current
    private var dayRects: [(NSRect, Date)] = []
    private var pillRects: [(NSRect, CalendarEvent)] = []

    init(date: Date, events: [CalendarEvent], owner: SchedulesView) {
        self.date = date
        self.events = events
        self.owner = owner
        super.init(frame: .zero)
        wantsLayer = true

        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let bounds = self.bounds
        let headerHeight: CGFloat = 30
        let cellPadding: CGFloat = 2

        // Day-of-week headers (locale-aware)
        let orderedDayNames = WeekCalendarView.orderedDayNames(for: cal)
        let colWidth = bounds.width / 7
        for (i, name) in orderedDayNames.enumerated() {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let str = NSAttributedString(string: name, attributes: attrs)
            let x = CGFloat(i) * colWidth + (colWidth - str.size().width) / 2
            str.draw(at: NSPoint(x: x, y: bounds.height - headerHeight + 8))
        }

        // Grid lines
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(0.5)

        // Calculate month grid
        let comps = cal.dateComponents([.year, .month], from: date)
        guard let monthStart = cal.date(from: comps) else { return }
        let firstWeekdayOfMonth = cal.component(.weekday, from: monthStart)
        let firstOffset = (firstWeekdayOfMonth - cal.firstWeekday + 7) % 7
        let daysInMonth = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30

        let gridTop = bounds.height - headerHeight
        let totalCells = firstOffset + daysInMonth
        let rowCount = Int(ceil(Double(totalCells) / 7.0))
        let rowHeight = max(gridTop / CGFloat(rowCount), 80)

        let isToday = cal.isDateInToday

        // Dimmed background color for out-of-month cells
        let dimmedBg = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.08, alpha: 1)
                : NSColor(white: 0.92, alpha: 1)
        }

        dayRects.removeAll()
        pillRects.removeAll()

        // Calculate the first date in the grid (may be from previous month)
        guard let gridStartDate = cal.date(byAdding: .day, value: -firstOffset, to: monthStart) else { return }

        for row in 0..<rowCount {
            for col in 0..<7 {
                let cellIndex = row * 7 + col
                guard let cellDate = cal.date(byAdding: .day, value: cellIndex, to: gridStartDate) else { continue }

                let cellMonth = cal.component(.month, from: cellDate)
                let currentMonth = cal.component(.month, from: date)
                let isCurrentMonth = cellMonth == currentMonth

                let x = CGFloat(col) * colWidth + cellPadding
                let y = gridTop - CGFloat(row + 1) * rowHeight + cellPadding
                let w = colWidth - cellPadding * 2
                let h = rowHeight - cellPadding * 2

                let cellRect = NSRect(x: x, y: y, width: w, height: h)

                dayRects.append((cellRect, cellDate))

                // Out-of-month dimmed background
                if !isCurrentMonth {
                    ctx.setFillColor(dimmedBg.cgColor)
                    ctx.fill(cellRect)
                }

                // Today highlight
                if isToday(cellDate) {
                    ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor)
                    ctx.fill(cellRect)
                }

                // Cell border
                ctx.setStrokeColor(NSColor.separatorColor.cgColor)
                ctx.stroke(cellRect)

                // Day number
                let dayNum = cal.component(.day, from: cellDate)
                let dayStr = "\(dayNum)"
                let dayColor: NSColor
                if !isCurrentMonth {
                    dayColor = NSColor.tertiaryLabelColor
                } else if isToday(cellDate) {
                    dayColor = NSColor.controlAccentColor
                } else {
                    dayColor = Theme.primaryText
                }
                let dayAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: isToday(cellDate) ? 13 : 11, weight: isToday(cellDate) ? .bold : .regular),
                    .foregroundColor: dayColor
                ]
                let dayAttrStr = NSAttributedString(string: dayStr, attributes: dayAttrs)
                dayAttrStr.draw(at: NSPoint(x: x + 4, y: y + h - 18))

                // Events for this day
                let dayEvents = events.filter { cal.isDate($0.date, inSameDayAs: cellDate) }
                let uniqueEvents = Dictionary(grouping: dayEvents, by: { "\($0.schedule.name)|\($0.schedule.filePath)" }).map { $0.value.first! }
                let maxPills = min(uniqueEvents.count, 3)
                let pillAlpha: CGFloat = isCurrentMonth ? 0.2 : 0.1
                for (i, event) in uniqueEvents.prefix(maxPills).enumerated() {
                    let pillY = y + h - 36 - CGFloat(i) * 18
                    guard pillY > y + 2 else { break }
                    let pillRect = NSRect(x: x + 4, y: pillY, width: w - 8, height: 15)
                    let color = ProjectColors.color(for: event.schedule.projectName)
                    ctx.setFillColor(color.withAlphaComponent(pillAlpha).cgColor)
                    let path = CGPath(roundedRect: pillRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
                    ctx.addPath(path)
                    ctx.fillPath()

                    let typeIcon = event.schedule.type == "swarm" ? "S" : "P"
                    let label = event.isHighFrequency ? "\(typeIcon) \(event.schedule.name) (\(event.frequencyLabel))" : "\(typeIcon) \(event.schedule.name)"
                    let pillAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                        .foregroundColor: color.withAlphaComponent(isCurrentMonth ? 1.0 : 0.5)
                    ]
                    let pillStr = NSAttributedString(string: label, attributes: pillAttrs)
                    pillStr.draw(at: NSPoint(x: x + 7, y: pillY + 1))

                    // Store pill rect for click targeting
                    pillRects.append((pillRect, event))
                }

                if uniqueEvents.count > 3 {
                    let moreStr = NSAttributedString(
                        string: "+\(uniqueEvents.count - 3) more",
                        attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.secondaryLabelColor]
                    )
                    moreStr.draw(at: NSPoint(x: x + 4, y: y + 4))
                }
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        // First, hit-test against pill rects for precise event targeting
        for (rect, calEvent) in pillRects {
            if rect.contains(loc) {
                owner?.showEventPopover(for: calEvent, relativeTo: NSRect(x: loc.x, y: loc.y, width: 1, height: 1), of: self)
                return
            }
        }

        // Fall through to day cell click (empty slot)
        for (rect, date) in dayRects {
            if rect.contains(loc) {
                owner?.handleTimeSlotClick(date: date)
                return
            }
        }
    }
}

// MARK: - Week Calendar View

class WeekCalendarView: NSView {
    private let date: Date
    private let events: [CalendarEvent]
    private weak var owner: SchedulesView?
    private let cal = Calendar.current
    private let hourHeight = CalendarLayout.hourHeight
    private let headerHeight = CalendarLayout.weekHeaderHeight
    private let timeGutterWidth = CalendarLayout.timeGutterWidth
    private var eventRects: [(NSRect, CalendarEvent)] = []
    private var hoveredRect: NSRect? = nil
    private var lastLayoutBounds: NSRect = .zero

    init(date: Date, events: [CalendarEvent], owner: SchedulesView) {
        self.date = date
        self.events = events
        self.owner = owner
        super.init(frame: .zero)
        wantsLayer = true

        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea)

        postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(boundsDidChange), name: NSView.frameDidChangeNotification, object: self)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func weekStart() -> Date {
        let weekday = cal.component(.weekday, from: date)
        let offset = (weekday - cal.firstWeekday + 7) % 7
        return cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: date)) ?? cal.startOfDay(for: date)
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        computeLayout()
        needsDisplay = true
    }

    private func computeLayout() {
        let bounds = self.bounds
        guard bounds != lastLayoutBounds else { return }
        lastLayoutBounds = bounds

        let weekStartDate = weekStart()
        let colWidth = (bounds.width - timeGutterWidth) / 7
        let gridTop = bounds.height - headerHeight

        eventRects.removeAll()

        for i in 0..<7 {
            guard let dayDate = cal.date(byAdding: .day, value: i, to: weekStartDate) else { continue }
            let dayEvents = events.filter { cal.isDate($0.date, inSameDayAs: dayDate) }
            let x = timeGutterWidth + CGFloat(i) * colWidth + 2

            for event in dayEvents {
                if event.isHighFrequency {
                    let stripeRect = NSRect(x: x, y: 2, width: colWidth - 4, height: gridTop - 4)
                    eventRects.append((stripeRect, event))
                } else {
                    let eventHour = cal.component(.hour, from: event.date)
                    let eventMinute = cal.component(.minute, from: event.date)
                    let eventY = gridTop - (CGFloat(eventHour) + CGFloat(eventMinute) / 60.0) * hourHeight
                    let eventHeight: CGFloat = max(hourHeight * 0.7, 32)
                    let eventRect = NSRect(x: x, y: eventY - eventHeight, width: colWidth - 4, height: eventHeight)
                    eventRects.append((eventRect, event))
                }
            }
        }

        window?.invalidateCursorRects(for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Ensure layout is computed
        if bounds != lastLayoutBounds { computeLayout() }

        let bounds = self.bounds
        let weekStartDate = weekStart()
        let colWidth = (bounds.width - timeGutterWidth) / 7

        // Day headers
        let orderedDayNames = Self.orderedDayNames(for: cal)
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "d"

        for i in 0..<7 {
            guard let dayDate = cal.date(byAdding: .day, value: i, to: weekStartDate) else { continue }
            let isToday = cal.isDateInToday(dayDate)
            let x = timeGutterWidth + CGFloat(i) * colWidth

            if isToday {
                ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.04).cgColor)
                ctx.fill(NSRect(x: x, y: 0, width: colWidth, height: bounds.height - headerHeight))
            }

            let dayNum = dateFmt.string(from: dayDate)
            let label = "\(orderedDayNames[i]) \(dayNum)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: isToday ? .bold : .medium),
                .foregroundColor: isToday ? NSColor.controlAccentColor : Theme.primaryText
            ]
            let str = NSAttributedString(string: label, attributes: attrs)
            let labelX = x + (colWidth - str.size().width) / 2
            str.draw(at: NSPoint(x: labelX, y: bounds.height - headerHeight + 18))
        }

        // Header separator
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: 0, y: bounds.height - headerHeight))
        ctx.addLine(to: CGPoint(x: bounds.width, y: bounds.height - headerHeight))
        ctx.strokePath()

        let gridTop = bounds.height - headerHeight

        // Hour grid (shared)
        CalendarDrawing.drawHourGrid(ctx: ctx, bounds: bounds, gridTop: gridTop, hourHeight: hourHeight, gutterWidth: timeGutterWidth)

        // Column separators
        for i in 0...7 {
            let x = timeGutterWidth + CGFloat(i) * colWidth
            ctx.setStrokeColor(NSColor.separatorColor.withAlphaComponent(0.3).cgColor)
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: gridTop))
            ctx.strokePath()
        }

        // Current time line (shared)
        let now = Date()
        let nowWeekday = cal.component(.weekday, from: now)
        if cal.isDate(now, equalTo: weekStartDate, toGranularity: .weekOfYear) {
            let nowOffset = (nowWeekday - cal.firstWeekday + 7) % 7
            let dotX = timeGutterWidth + CGFloat(nowOffset) * colWidth
            CalendarDrawing.drawCurrentTimeLine(ctx: ctx, gridTop: gridTop, hourHeight: hourHeight, leftX: timeGutterWidth, rightX: bounds.width, dotX: dotX)
        }

        // Draw pre-computed event rects
        for (rect, event) in eventRects {
            let color = ProjectColors.color(for: event.schedule.projectName)
            let icon = CalendarDrawing.typeIcon(for: event.schedule)

            if event.isHighFrequency {
                CalendarDrawing.drawHighFrequencyStripe(ctx: ctx, rect: rect, color: color, label: "\(icon) \(event.schedule.name) (\(event.frequencyLabel))", gridTop: gridTop)
            } else {
                let isHovered = hoveredRect.map { $0.intersects(rect) } ?? false
                // Line 1: [S] schedule-name
                CalendarDrawing.drawTimedEvent(ctx: ctx, rect: rect, color: color, label: "\(icon) \(event.schedule.name)", isHovered: isHovered)

                // Line 2: time + target (if room)
                if rect.height >= 32 {
                    let timeFmt = DateFormatter()
                    timeFmt.dateFormat = "h:mm a"
                    let secondLine = "\(timeFmt.string(from: event.date)) \u{2022} \(event.schedule.target)"
                    let secondLineAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 9),
                        .foregroundColor: color.withAlphaComponent(0.7)
                    ]
                    NSAttributedString(string: secondLine, attributes: secondLineAttrs)
                        .draw(in: NSRect(x: rect.minX + 6, y: rect.minY + 2, width: rect.width - 10, height: 12))
                }
            }
        }
    }

    static func orderedDayNames(for cal: Calendar) -> [String] {
        let allDays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let first = cal.firstWeekday // 1=Sun, 2=Mon, etc.
        return (0..<7).map { allDays[($0 + first - 1) % 7] }
    }

    override func resetCursorRects() {
        discardCursorRects()
        for (rect, _) in eventRects {
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        var newHover: NSRect? = nil
        for (rect, _) in eventRects {
            if rect.contains(loc) { newHover = rect; break }
        }
        if newHover != hoveredRect {
            hoveredRect = newHover
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredRect = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        // Check event clicks
        for (rect, calEvent) in eventRects {
            if rect.contains(loc) {
                owner?.showEventPopover(for: calEvent, relativeTo: NSRect(x: loc.x, y: loc.y, width: 1, height: 1), of: self)
                return
            }
        }

        // Empty time slot click
        let weekStartDate = weekStart()
        let colWidth = (bounds.width - timeGutterWidth) / 7
        let gridTop = bounds.height - headerHeight

        if loc.x > timeGutterWidth && loc.y < gridTop {
            let col = Int((loc.x - timeGutterWidth) / colWidth)
            guard col >= 0, col < 7 else { return }
            let hourFloat = (gridTop - loc.y) / hourHeight
            let hour = Int(hourFloat)
            let minute = Int((hourFloat - CGFloat(hour)) * 60)
            let roundedMinute = (minute / 15) * 15

            if let dayDate = cal.date(byAdding: .day, value: col, to: weekStartDate) {
                var comps = cal.dateComponents([.year, .month, .day], from: dayDate)
                comps.hour = hour
                comps.minute = roundedMinute
                if let clickDate = cal.date(from: comps) {
                    owner?.handleTimeSlotClick(date: clickDate)
                }
            }
        }
    }
}

// MARK: - Day Calendar View

class DayCalendarView: NSView {
    private let date: Date
    private let events: [CalendarEvent]
    private weak var owner: SchedulesView?
    private let cal = Calendar.current
    private let hourHeight = CalendarLayout.hourHeight
    private let headerHeight = CalendarLayout.dayHeaderHeight
    private let timeGutterWidth = CalendarLayout.timeGutterWidth
    private var eventRects: [(NSRect, CalendarEvent)] = []
    private var hoveredRect: NSRect? = nil
    private var lastLayoutBounds: NSRect = .zero

    init(date: Date, events: [CalendarEvent], owner: SchedulesView) {
        self.date = date
        self.events = events
        self.owner = owner
        super.init(frame: .zero)
        wantsLayer = true

        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea)

        postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(boundsDidChange), name: NSView.frameDidChangeNotification, object: self)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        computeLayout()
        needsDisplay = true
    }

    private func computeLayout() {
        let bounds = self.bounds
        guard bounds != lastLayoutBounds else { return }
        lastLayoutBounds = bounds

        let dayStart = cal.startOfDay(for: date)
        let gridTop = bounds.height - headerHeight
        let contentWidth = bounds.width - timeGutterWidth
        let x = timeGutterWidth + 4

        eventRects.removeAll()

        let dayEvents = events.filter { cal.isDate($0.date, inSameDayAs: dayStart) }

        for event in dayEvents {
            if event.isHighFrequency {
                let stripeRect = NSRect(x: x, y: 2, width: contentWidth - 8, height: gridTop - 4)
                eventRects.append((stripeRect, event))
            } else {
                let eventHour = cal.component(.hour, from: event.date)
                let eventMinute = cal.component(.minute, from: event.date)
                let eventY = gridTop - (CGFloat(eventHour) + CGFloat(eventMinute) / 60.0) * hourHeight
                let eventHeight: CGFloat = hourHeight * 0.9
                let eventRect = NSRect(x: x, y: eventY - eventHeight, width: contentWidth - 8, height: eventHeight)
                eventRects.append((eventRect, event))
            }
        }

        window?.invalidateCursorRects(for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Ensure layout is computed
        if bounds != lastLayoutBounds { computeLayout() }

        let bounds = self.bounds
        let dayStart = cal.startOfDay(for: date)
        let isToday = cal.isDateInToday(dayStart)

        // Header
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMMM d"
        let headerStr = NSAttributedString(string: fmt.string(from: date), attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: isToday ? NSColor.controlAccentColor : Theme.primaryText
        ])
        headerStr.draw(at: NSPoint(x: timeGutterWidth + 8, y: bounds.height - headerHeight + 12))

        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: 0, y: bounds.height - headerHeight))
        ctx.addLine(to: CGPoint(x: bounds.width, y: bounds.height - headerHeight))
        ctx.strokePath()

        let gridTop = bounds.height - headerHeight

        // Hour grid (shared)
        CalendarDrawing.drawHourGrid(ctx: ctx, bounds: bounds, gridTop: gridTop, hourHeight: hourHeight, gutterWidth: timeGutterWidth, timeFontSize: 10)

        // Current time line (shared)
        if isToday {
            CalendarDrawing.drawCurrentTimeLine(ctx: ctx, gridTop: gridTop, hourHeight: hourHeight, leftX: timeGutterWidth, rightX: bounds.width, dotX: timeGutterWidth, lineWidth: 2, dotRadius: 5)
        }

        // Draw pre-computed event rects
        for (rect, event) in eventRects {
            let color = ProjectColors.color(for: event.schedule.projectName)
            let x = rect.minX
            let icon = CalendarDrawing.typeIcon(for: event.schedule)

            if event.isHighFrequency {
                CalendarDrawing.drawHighFrequencyStripe(ctx: ctx, rect: rect, color: color, label: "\(icon) \(event.schedule.name) \u{2014} \(event.frequencyLabel)", gridTop: gridTop, fontSize: 11)
            } else {
                let isHovered = hoveredRect.map { $0.intersects(rect) } ?? false

                // Day view gets richer event rendering (more space available)
                ctx.setFillColor(color.withAlphaComponent(isHovered ? 0.25 : 0.15).cgColor)
                let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
                ctx.addPath(path)
                ctx.fillPath()

                // Left accent bar
                ctx.setFillColor(color.cgColor)
                ctx.fill(NSRect(x: x, y: rect.minY, width: 3, height: rect.height))

                // Event text — name, time, and cron
                let timeFmt = DateFormatter()
                timeFmt.dateFormat = "h:mm a"
                let timeStr = timeFmt.string(from: event.date)

                NSAttributedString(string: "[\(icon)] \(event.schedule.name)", attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: color
                ]).draw(at: NSPoint(x: x + 8, y: rect.maxY - 18))

                NSAttributedString(string: "\(timeStr) \u{2022} \(event.schedule.target) \u{2022} \(event.schedule.projectName)", attributes: [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: color.withAlphaComponent(0.8)
                ]).draw(at: NSPoint(x: x + 8, y: rect.maxY - 34))

                NSAttributedString(string: CronParser.humanReadable(event.schedule.cronExpression), attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]).draw(at: NSPoint(x: x + 8, y: rect.maxY - 48))
            }
        }
    }

    override func resetCursorRects() {
        discardCursorRects()
        for (rect, _) in eventRects {
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        var newHover: NSRect? = nil
        for (rect, _) in eventRects {
            if rect.contains(loc) { newHover = rect; break }
        }
        if newHover != hoveredRect {
            hoveredRect = newHover
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredRect = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        for (rect, calEvent) in eventRects {
            if rect.contains(loc) {
                owner?.showEventPopover(for: calEvent, relativeTo: NSRect(x: loc.x, y: loc.y, width: 1, height: 1), of: self)
                return
            }
        }

        // Empty slot click
        let gridTop = bounds.height - headerHeight
        if loc.x > timeGutterWidth && loc.y < gridTop {
            let hourFloat = (gridTop - loc.y) / hourHeight
            let hour = Int(hourFloat)
            let minute = Int((hourFloat - CGFloat(hour)) * 60)
            let roundedMinute = (minute / 15) * 15

            var comps = cal.dateComponents([.year, .month, .day], from: date)
            comps.hour = hour
            comps.minute = roundedMinute
            if let clickDate = cal.date(from: comps) {
                owner?.handleTimeSlotClick(date: clickDate)
            }
        }
    }
}
