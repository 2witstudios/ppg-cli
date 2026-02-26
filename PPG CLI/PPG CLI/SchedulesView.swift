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

// MARK: - Cron Parser

/// Computes occurrences of a 5-field cron expression within a date range.
struct CronParser {
    let minute: CronField
    let hour: CronField
    let dayOfMonth: CronField
    let month: CronField
    let dayOfWeek: CronField

    /// Whether this schedule fires very frequently (every 5 minutes or less).
    var isHighFrequency: Bool {
        // If every minute or step-based with small intervals
        if minute.isWildcard && hour.isWildcard { return true }
        if case .step(_, let step) = minute, step <= 5, hour.isWildcard { return true }
        return false
    }

    /// Approximate number of occurrences per hour
    var occurrencesPerHour: Int {
        if minute.isWildcard { return 60 }
        if case .step(_, let step) = minute { return 60 / step }
        return minute.values(in: 0...59).count
    }

    indirect enum CronField {
        case wildcard
        case values([Int])
        case step(base: CronField, Int)

        var isWildcard: Bool {
            if case .wildcard = self { return true }
            return false
        }

        func matches(_ value: Int) -> Bool {
            switch self {
            case .wildcard:
                return true
            case .values(let vals):
                return vals.contains(value)
            case .step(let base, let step):
                switch base {
                case .wildcard:
                    return value % step == 0
                case .values(let vals):
                    guard let start = vals.first else { return false }
                    if value < start { return false }
                    return (value - start) % step == 0
                default:
                    return false
                }
            }
        }

        func values(in range: ClosedRange<Int>) -> [Int] {
            switch self {
            case .wildcard:
                return Array(range)
            case .values(let vals):
                return vals.filter { range.contains($0) }
            case .step(let base, let step):
                var result: [Int] = []
                switch base {
                case .wildcard:
                    var v = range.lowerBound
                    // Align to step
                    if v % step != 0 { v += (step - v % step) }
                    while v <= range.upperBound {
                        result.append(v)
                        v += step
                    }
                case .values(let vals):
                    guard let start = vals.first else { return [] }
                    var v = start
                    while v <= range.upperBound {
                        if range.contains(v) { result.append(v) }
                        v += step
                    }
                default:
                    break
                }
                return result
            }
        }
    }

    init?(_ expression: String) {
        let parts = expression.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 5 else { return nil }

        guard let min = Self.parseField(parts[0], range: 0...59),
              let hr = Self.parseField(parts[1], range: 0...23),
              let dom = Self.parseField(parts[2], range: 1...31),
              let mon = Self.parseField(parts[3], range: 1...12),
              let dow = Self.parseField(parts[4], range: 0...6) else { return nil }

        self.minute = min
        self.hour = hr
        self.dayOfMonth = dom
        self.month = mon
        self.dayOfWeek = dow
    }

    static func parseField(_ field: String, range: ClosedRange<Int>) -> CronField? {
        // Handle step: */5, 1-10/2
        if field.contains("/") {
            let slashParts = field.split(separator: "/", maxSplits: 1)
            guard slashParts.count == 2, let step = Int(slashParts[1]), step > 0 else { return nil }
            let baseStr = String(slashParts[0])
            if baseStr == "*" {
                return .step(base: .wildcard, step)
            } else if let base = parseField(baseStr, range: range) {
                return .step(base: base, step)
            }
            return nil
        }

        if field == "*" { return .wildcard }

        // Handle lists: 1,3,5
        if field.contains(",") {
            var vals: [Int] = []
            for part in field.split(separator: ",") {
                let s = String(part)
                if s.contains("-") {
                    guard let rangeVals = parseRange(s) else { return nil }
                    vals.append(contentsOf: rangeVals)
                } else if let v = Int(s), range.contains(v) {
                    vals.append(v)
                } else {
                    return nil
                }
            }
            return .values(vals.sorted())
        }

        // Handle ranges: 1-5
        if field.contains("-") {
            guard let vals = parseRange(field) else { return nil }
            return .values(vals)
        }

        // Single value
        if let v = Int(field), range.contains(v) {
            return .values([v])
        }

        return nil
    }

    private static func parseRange(_ s: String) -> [Int]? {
        let parts = s.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, let lo = Int(parts[0]), let hi = Int(parts[1]), lo <= hi else { return nil }
        return Array(lo...hi)
    }

    /// Compute all occurrences within [start, end).
    func occurrences(from start: Date, to end: Date, calendar: Calendar = .current) -> [Date] {
        // For high frequency schedules, limit results
        let maxResults = isHighFrequency ? 1 : 500
        var results: [Date] = []
        var current = calendar.startOfDay(for: start)

        while current < end && results.count < maxResults {
            let comps = calendar.dateComponents([.year, .month, .day, .weekday], from: current)
            guard let m = comps.month, let d = comps.day, let wd = comps.weekday else {
                current = calendar.date(byAdding: .day, value: 1, to: current) ?? end
                continue
            }

            // weekday: Calendar uses 1=Sun, 2=Mon... cron uses 0=Sun, 1=Mon...
            let cronDow = wd - 1

            if month.matches(m) && dayOfMonth.matches(d) && dayOfWeek.matches(cronDow) {
                let hours = hour.values(in: 0...23)
                let minutes = minute.values(in: 0...59)

                for h in hours {
                    for min in minutes {
                        guard let date = calendar.date(bySettingHour: h, minute: min, second: 0, of: current) else { continue }
                        if date >= start && date < end {
                            results.append(date)
                            if results.count >= maxResults { return results }
                        }
                    }
                }
            }

            current = calendar.date(byAdding: .day, value: 1, to: current) ?? end
        }

        return results
    }

    /// Human-readable description of the cron expression
    func humanDescription(expression: String) -> String {
        let parts = expression.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        guard parts.count == 5 else { return expression }
        let (minStr, hrStr, domStr, monStr, dowStr) = (parts[0], parts[1], parts[2], parts[3], parts[4])

        if minStr == "0" && hrStr != "*" && domStr == "*" && monStr == "*" && dowStr == "*" {
            return "Daily at \(hrStr):00"
        }
        if minStr.hasPrefix("*/") && hrStr == "*" && domStr == "*" && monStr == "*" && dowStr == "*" {
            return "Every \(minStr.dropFirst(2)) min"
        }
        if minStr != "*" && hrStr == "*" && domStr == "*" && monStr == "*" && dowStr == "*" {
            return "Hourly at :\(minStr.count == 1 ? "0\(minStr)" : minStr)"
        }
        if minStr == "*" && hrStr == "*" && domStr == "*" && monStr == "*" && dowStr == "*" {
            return "Every minute"
        }
        if dowStr != "*" && domStr == "*" && monStr == "*" {
            let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            // Could be range like 1-5
            if let d = Int(dowStr), d >= 0, d < 7 {
                return "\(days[d]) at \(hrStr):\(minStr.count == 1 ? "0\(minStr)" : minStr)"
            }
            if dowStr == "1-5" {
                return "Weekdays at \(hrStr):\(minStr.count == 1 ? "0\(minStr)" : minStr)"
            }
        }
        return expression
    }
}

// MARK: - Calendar Event

struct CalendarEvent {
    let date: Date
    let schedule: ScheduleInfo
    let isHighFrequency: Bool
}

// MARK: - Calendar View Mode

enum CalendarViewMode: Int {
    case day = 0
    case week = 1
    case month = 2
}

// MARK: - Project Color Palette

struct ProjectColorPalette {
    private static let colors: [NSColor] = [
        .systemBlue, .systemPurple, .systemTeal, .systemIndigo,
        .systemOrange, .systemPink, .systemGreen, .systemBrown
    ]

    private var colorMap: [String: NSColor] = [:]

    mutating func color(for projectRoot: String) -> NSColor {
        if let c = colorMap[projectRoot] { return c }
        let idx = colorMap.count % Self.colors.count
        let c = Self.colors[idx]
        colorMap[projectRoot] = c
        return c
    }
}

// MARK: - SchedulesView (Calendar)

class SchedulesView: NSView {

    // MARK: - Header Controls
    private let headerBar = NSView()
    private let titleLabel = NSTextField(labelWithString: "Schedules")
    private let daemonDot = NSView()
    private let daemonButton = NSButton()
    private let newButton = NSButton()
    private let viewModeControl = NSSegmentedControl()
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let todayButton = NSButton()
    private let dateLabel = NSTextField(labelWithString: "")

    // MARK: - Calendar Content
    private let calendarScrollView = NSScrollView()
    private let calendarContainer = NSView()
    private let emptyLabel = NSTextField(labelWithString: "No schedules found.\nCreate schedules in .ppg/schedules.yaml")

    // MARK: - State
    private var schedules: [ScheduleInfo] = []
    private var projects: [ProjectContext] = []
    private var viewMode: CalendarViewMode = .week
    private var currentDate = Date()
    private var daemonRunning = false
    private var projectColors = ProjectColorPalette()
    private var events: [CalendarEvent] = []

    // MARK: - Drawing state
    private var eventViews: [NSView] = []
    private var activePopover: NSPopover?

    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 60
    private let headerHeight: CGFloat = 40
    private let dayHeaderHeight: CGFloat = 50
    private let monthCellPadding: CGFloat = 2
    private let timeGutterWidth: CGFloat = 56

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
        computeEvents()
        renderCalendar()
        checkDaemonStatus()
        emptyLabel.isHidden = !schedules.isEmpty
    }

    // MARK: - File Scanning (reused from original)

    static func scanSchedules(projects: [ProjectContext]) -> [ScheduleInfo] {
        let fm = FileManager.default
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
                if trimmed.hasPrefix("schedules:") {
                    inSchedules = true
                } else {
                    inSchedules = false
                }
                continue
            }

            guard inSchedules else { continue }

            if trimmed.hasPrefix("- ") || trimmed == "-" {
                if let c = current {
                    results.append(c)
                }
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
        if let c = current {
            results.append(c)
        }
        return results
    }

    private static func applyKeyValue(_ trimmed: String, to entry: inout ParsedSchedule, inVars: inout Bool) {
        if trimmed.hasPrefix("name:") {
            entry.name = yamlValue(trimmed)
            inVars = false
        } else if trimmed.hasPrefix("cron:") {
            entry.cron = yamlValue(trimmed)
            inVars = false
        } else if trimmed.hasPrefix("swarm:") {
            entry.type = "swarm"
            entry.target = yamlValue(trimmed)
            inVars = false
        } else if trimmed.hasPrefix("prompt:") {
            entry.type = "prompt"
            entry.target = yamlValue(trimmed)
            inVars = false
        } else if trimmed.hasPrefix("vars:") {
            inVars = true
        } else if inVars && trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let k = parts[0].trimmingCharacters(in: .whitespaces)
                let v = parts[1].trimmingCharacters(in: .whitespaces)
                entry.vars.append((k, stripQuotes(v)))
            }
        }
    }

    private static func yamlValue(_ line: String) -> String {
        guard let colonIdx = line.range(of: ":") else { return "" }
        var value = String(line[colonIdx.upperBound...]).trimmingCharacters(in: .whitespaces)
        value = stripQuotes(value)
        return value
    }

    private static func stripQuotes(_ s: String) -> String {
        var value = s
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    // MARK: - Event Computation

    private func computeEvents() {
        events = []
        let (rangeStart, rangeEnd) = dateRange(for: viewMode, around: currentDate)

        for schedule in schedules {
            guard let parser = CronParser(schedule.cronExpression) else { continue }
            let occurrences = parser.occurrences(from: rangeStart, to: rangeEnd)

            if parser.isHighFrequency {
                // For high-frequency schedules, add a single synthetic "repeating" event per day
                let desc = parser.humanDescription(expression: schedule.cronExpression)
                let syntheticSchedule = ScheduleInfo(
                    name: "\(schedule.name) (\(desc))",
                    cronExpression: schedule.cronExpression,
                    type: schedule.type,
                    target: schedule.target,
                    projectRoot: schedule.projectRoot,
                    projectName: schedule.projectName,
                    filePath: schedule.filePath,
                    vars: schedule.vars
                )
                // One event per day in range
                var day = rangeStart
                while day < rangeEnd {
                    events.append(CalendarEvent(date: day, schedule: syntheticSchedule, isHighFrequency: true))
                    day = calendar.date(byAdding: .day, value: 1, to: day)!
                }
            } else {
                for date in occurrences {
                    events.append(CalendarEvent(date: date, schedule: schedule, isHighFrequency: false))
                }
            }
        }
    }

    private func dateRange(for mode: CalendarViewMode, around date: Date) -> (Date, Date) {
        switch mode {
        case .day:
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
        case .week:
            let weekday = calendar.component(.weekday, from: date)
            let startOfWeek = calendar.date(byAdding: .day, value: -(weekday - 1), to: calendar.startOfDay(for: date))!
            let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!
            return (startOfWeek, endOfWeek)
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: date)
            let startOfMonth = calendar.date(from: comps)!
            // Go back to start of the week containing the first day
            let firstWeekday = calendar.component(.weekday, from: startOfMonth)
            let gridStart = calendar.date(byAdding: .day, value: -(firstWeekday - 1), to: startOfMonth)!
            let gridEnd = calendar.date(byAdding: .day, value: 42, to: gridStart)!
            return (gridStart, gridEnd)
        }
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

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = Theme.contentBackground.resolvedCGColor(for: effectiveAppearance)

        // Header bar
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
        daemonButton.title = "Start Daemon"
        daemonButton.font = .systemFont(ofSize: 11)
        daemonButton.isBordered = false
        daemonButton.contentTintColor = Theme.primaryText
        daemonButton.target = self
        daemonButton.action = #selector(daemonToggleClicked)
        daemonButton.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(daemonButton)

        // New Schedule button
        newButton.bezelStyle = .accessoryBarAction
        newButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Schedule")
        newButton.title = "New Schedule"
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

        // Navigation bar
        let navBar = NSView()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(navBar)

        let navSep = NSBox()
        navSep.boxType = .separator
        navSep.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(navSep)

        // Prev/Next/Today
        prevButton.bezelStyle = .accessoryBarAction
        prevButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous")
        prevButton.title = ""
        prevButton.isBordered = false
        prevButton.contentTintColor = Theme.primaryText
        prevButton.target = self
        prevButton.action = #selector(prevClicked)
        prevButton.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(prevButton)

        nextButton.bezelStyle = .accessoryBarAction
        nextButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next")
        nextButton.title = ""
        nextButton.isBordered = false
        nextButton.contentTintColor = Theme.primaryText
        nextButton.target = self
        nextButton.action = #selector(nextClicked)
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(nextButton)

        todayButton.bezelStyle = .accessoryBarAction
        todayButton.title = "Today"
        todayButton.font = .systemFont(ofSize: 11, weight: .medium)
        todayButton.isBordered = false
        todayButton.contentTintColor = Theme.primaryText
        todayButton.target = self
        todayButton.action = #selector(todayClicked)
        todayButton.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(todayButton)

        dateLabel.font = .systemFont(ofSize: 13, weight: .medium)
        dateLabel.textColor = Theme.primaryText
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(dateLabel)

        // View mode segmented control
        viewModeControl.segmentCount = 3
        viewModeControl.setLabel("Day", forSegment: 0)
        viewModeControl.setLabel("Week", forSegment: 1)
        viewModeControl.setLabel("Month", forSegment: 2)
        viewModeControl.setWidth(50, forSegment: 0)
        viewModeControl.setWidth(50, forSegment: 1)
        viewModeControl.setWidth(55, forSegment: 2)
        viewModeControl.selectedSegment = viewMode.rawValue
        viewModeControl.target = self
        viewModeControl.action = #selector(viewModeChanged)
        viewModeControl.translatesAutoresizingMaskIntoConstraints = false
        viewModeControl.controlSize = .small
        navBar.addSubview(viewModeControl)

        // Calendar scroll view
        calendarScrollView.translatesAutoresizingMaskIntoConstraints = false
        calendarScrollView.hasVerticalScroller = true
        calendarScrollView.hasHorizontalScroller = false
        calendarScrollView.drawsBackground = false
        calendarScrollView.backgroundColor = .clear

        calendarContainer.translatesAutoresizingMaskIntoConstraints = false
        calendarContainer.wantsLayer = true
        calendarScrollView.documentView = calendarContainer
        addSubview(calendarScrollView)

        // Empty label
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.maximumNumberOfLines = 2
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            // Header bar
            headerBar.topAnchor.constraint(equalTo: topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            daemonDot.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            daemonDot.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            daemonDot.widthAnchor.constraint(equalToConstant: 10),
            daemonDot.heightAnchor.constraint(equalToConstant: 10),

            daemonButton.leadingAnchor.constraint(equalTo: daemonDot.trailingAnchor, constant: 4),
            daemonButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            newButton.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -8),
            newButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            headerSep.bottomAnchor.constraint(equalTo: headerBar.bottomAnchor),
            headerSep.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            headerSep.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),

            // Nav bar
            navBar.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            navBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            navBar.heightAnchor.constraint(equalToConstant: 36),

            prevButton.leadingAnchor.constraint(equalTo: navBar.leadingAnchor, constant: 8),
            prevButton.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),

            nextButton.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 2),
            nextButton.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),

            todayButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 8),
            todayButton.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),

            dateLabel.leadingAnchor.constraint(equalTo: todayButton.trailingAnchor, constant: 12),
            dateLabel.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),

            viewModeControl.trailingAnchor.constraint(equalTo: navBar.trailingAnchor, constant: -12),
            viewModeControl.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),

            navSep.bottomAnchor.constraint(equalTo: navBar.bottomAnchor),
            navSep.leadingAnchor.constraint(equalTo: navBar.leadingAnchor),
            navSep.trailingAnchor.constraint(equalTo: navBar.trailingAnchor),

            // Calendar
            calendarScrollView.topAnchor.constraint(equalTo: navBar.bottomAnchor),
            calendarScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            calendarScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            calendarScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Empty label
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateDateLabel()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.contentBackground.resolvedCGColor(for: effectiveAppearance)
        renderCalendar()
    }

    // MARK: - Date Label

    private func updateDateLabel() {
        let formatter = DateFormatter()
        switch viewMode {
        case .day:
            formatter.dateFormat = "EEEE, MMMM d, yyyy"
            dateLabel.stringValue = formatter.string(from: currentDate)
        case .week:
            let (start, end) = dateRange(for: .week, around: currentDate)
            let endDay = calendar.date(byAdding: .day, value: -1, to: end)!
            formatter.dateFormat = "MMM d"
            let startStr = formatter.string(from: start)
            formatter.dateFormat = "MMM d, yyyy"
            let endStr = formatter.string(from: endDay)
            dateLabel.stringValue = "\(startStr) – \(endStr)"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            dateLabel.stringValue = formatter.string(from: currentDate)
        }
    }

    // MARK: - Rendering

    private func renderCalendar() {
        // Clear old event views
        for v in eventViews { v.removeFromSuperview() }
        eventViews = []
        for v in calendarContainer.subviews { v.removeFromSuperview() }

        updateDateLabel()

        switch viewMode {
        case .day:
            renderDayView()
        case .week:
            renderWeekView()
        case .month:
            renderMonthView()
        }
    }

    // MARK: - Day View

    private func renderDayView() {
        let contentHeight: CGFloat = 24 * hourHeight + dayHeaderHeight
        let containerWidth = max(calendarScrollView.bounds.width, 300)
        calendarContainer.frame = NSRect(x: 0, y: 0, width: containerWidth, height: contentHeight)

        // Day header
        let dayStart = calendar.startOfDay(for: currentDate)
        let isToday = calendar.isDateInToday(dayStart)

        let dayHeader = NSView(frame: NSRect(x: 0, y: contentHeight - dayHeaderHeight, width: containerWidth, height: dayHeaderHeight))
        dayHeader.wantsLayer = true
        dayHeader.layer?.backgroundColor = Theme.cardHeaderBackground.resolvedCGColor(for: effectiveAppearance)
        calendarContainer.addSubview(dayHeader)

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        let dayNameLabel = NSTextField(labelWithString: formatter.string(from: currentDate).uppercased())
        dayNameLabel.font = .systemFont(ofSize: 10, weight: .medium)
        dayNameLabel.textColor = isToday ? .systemBlue : .secondaryLabelColor
        dayNameLabel.frame = NSRect(x: timeGutterWidth, y: 6, width: 60, height: 14)
        dayHeader.addSubview(dayNameLabel)

        let dayNum = NSTextField(labelWithString: "\(calendar.component(.day, from: currentDate))")
        dayNum.font = .systemFont(ofSize: 20, weight: isToday ? .bold : .regular)
        dayNum.textColor = isToday ? .systemBlue : Theme.primaryText
        dayNum.frame = NSRect(x: timeGutterWidth, y: 20, width: 60, height: 26)
        dayHeader.addSubview(dayNum)

        // Hour grid
        renderTimeGrid(in: calendarContainer, width: containerWidth, columnStart: timeGutterWidth, columnWidth: containerWidth - timeGutterWidth, yOffset: contentHeight - dayHeaderHeight)

        // Events
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let dayEvents = events.filter { $0.date >= dayStart && $0.date < dayEnd }

        for event in dayEvents {
            let y = yPosition(for: event.date, topY: contentHeight - dayHeaderHeight)
            let eventView = createEventView(event: event, frame: NSRect(x: timeGutterWidth + 2, y: y - 22, width: containerWidth - timeGutterWidth - 8, height: 22))
            calendarContainer.addSubview(eventView)
            eventViews.append(eventView)
        }

        // Current time indicator
        if isToday {
            renderCurrentTimeLine(in: calendarContainer, x: timeGutterWidth, width: containerWidth - timeGutterWidth, topY: contentHeight - dayHeaderHeight)
        }

        scrollToCurrentTime(contentHeight: contentHeight)
    }

    // MARK: - Week View

    private func renderWeekView() {
        let contentHeight: CGFloat = 24 * hourHeight + dayHeaderHeight
        let containerWidth = max(calendarScrollView.bounds.width, 300)
        calendarContainer.frame = NSRect(x: 0, y: 0, width: containerWidth, height: contentHeight)

        let (weekStart, _) = dateRange(for: .week, around: currentDate)
        let dayWidth = (containerWidth - timeGutterWidth) / 7

        // Day headers
        let headerBg = NSView(frame: NSRect(x: 0, y: contentHeight - dayHeaderHeight, width: containerWidth, height: dayHeaderHeight))
        headerBg.wantsLayer = true
        headerBg.layer?.backgroundColor = Theme.cardHeaderBackground.resolvedCGColor(for: effectiveAppearance)
        calendarContainer.addSubview(headerBg)

        let formatter = DateFormatter()
        for dayIdx in 0..<7 {
            let dayDate = calendar.date(byAdding: .day, value: dayIdx, to: weekStart)!
            let isToday = calendar.isDateInToday(dayDate)
            let x = timeGutterWidth + CGFloat(dayIdx) * dayWidth

            formatter.dateFormat = "EEE"
            let nameLabel = NSTextField(labelWithString: formatter.string(from: dayDate).uppercased())
            nameLabel.font = .systemFont(ofSize: 9, weight: .medium)
            nameLabel.textColor = isToday ? .systemBlue : .secondaryLabelColor
            nameLabel.alignment = .center
            nameLabel.frame = NSRect(x: x, y: 6, width: dayWidth, height: 12)
            headerBg.addSubview(nameLabel)

            let numStr = "\(calendar.component(.day, from: dayDate))"
            let numLabel = NSTextField(labelWithString: numStr)
            numLabel.font = .systemFont(ofSize: 16, weight: isToday ? .bold : .regular)
            numLabel.textColor = isToday ? .systemBlue : Theme.primaryText
            numLabel.alignment = .center
            numLabel.frame = NSRect(x: x, y: 18, width: dayWidth, height: 24)
            headerBg.addSubview(numLabel)

            // Vertical column separator
            if dayIdx > 0 {
                let sep = NSView(frame: NSRect(x: x, y: 0, width: 1, height: contentHeight - dayHeaderHeight))
                sep.wantsLayer = true
                sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
                calendarContainer.addSubview(sep)
            }
        }

        // Time grid
        renderTimeGrid(in: calendarContainer, width: containerWidth, columnStart: timeGutterWidth, columnWidth: containerWidth - timeGutterWidth, yOffset: contentHeight - dayHeaderHeight)

        // Events per day column
        for dayIdx in 0..<7 {
            let dayDate = calendar.date(byAdding: .day, value: dayIdx, to: weekStart)!
            let dayStart = calendar.startOfDay(for: dayDate)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let x = timeGutterWidth + CGFloat(dayIdx) * dayWidth

            let dayEvents = events.filter { $0.date >= dayStart && $0.date < dayEnd }
            for event in dayEvents {
                let y = yPosition(for: event.date, topY: contentHeight - dayHeaderHeight)
                let eventView = createEventView(event: event, frame: NSRect(x: x + 2, y: y - 20, width: dayWidth - 4, height: 20))
                calendarContainer.addSubview(eventView)
                eventViews.append(eventView)
            }

            // Current time line
            if calendar.isDateInToday(dayDate) {
                renderCurrentTimeLine(in: calendarContainer, x: x, width: dayWidth, topY: contentHeight - dayHeaderHeight)
            }
        }

        scrollToCurrentTime(contentHeight: contentHeight)
    }

    // MARK: - Month View

    private func renderMonthView() {
        let containerWidth = max(calendarScrollView.bounds.width, 300)
        let dayWidth = containerWidth / 7
        let rowCount: CGFloat = 6
        let dayNameHeaderHeight: CGFloat = 24
        let cellHeight: CGFloat = max(100, (calendarScrollView.bounds.height - dayNameHeaderHeight) / rowCount)
        let contentHeight = cellHeight * rowCount + dayNameHeaderHeight

        calendarContainer.frame = NSRect(x: 0, y: 0, width: containerWidth, height: contentHeight)

        let comps = calendar.dateComponents([.year, .month], from: currentDate)
        let startOfMonth = calendar.date(from: comps)!
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let gridStart = calendar.date(byAdding: .day, value: -(firstWeekday - 1), to: startOfMonth)!

        let currentMonth = calendar.component(.month, from: currentDate)

        // Day name headers
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        for (i, name) in dayNames.enumerated() {
            let label = NSTextField(labelWithString: name.uppercased())
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.frame = NSRect(x: CGFloat(i) * dayWidth, y: contentHeight - dayNameHeaderHeight, width: dayWidth, height: dayNameHeaderHeight)
            calendarContainer.addSubview(label)
        }

        // Cells
        for row in 0..<Int(rowCount) {
            for col in 0..<7 {
                let dayOffset = row * 7 + col
                let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: gridStart)!
                let dayMonth = calendar.component(.month, from: dayDate)
                let isCurrentMonth = dayMonth == currentMonth
                let isToday = calendar.isDateInToday(dayDate)

                let x = CGFloat(col) * dayWidth
                let y = contentHeight - dayNameHeaderHeight - CGFloat(row + 1) * cellHeight

                // Cell background
                let cell = MonthDayCell(frame: NSRect(x: x, y: y, width: dayWidth, height: cellHeight))
                cell.isCurrentMonth = isCurrentMonth
                cell.isToday = isToday
                cell.dayNumber = calendar.component(.day, from: dayDate)
                cell.appearance = effectiveAppearance
                cell.onClicked = { [weak self] in
                    self?.handleEmptySlotClick(date: dayDate)
                }
                calendarContainer.addSubview(cell)

                // Events for this day
                let dayStart = calendar.startOfDay(for: dayDate)
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
                let dayEvents = events.filter { $0.date >= dayStart && $0.date < dayEnd }

                let maxVisible = max(1, Int((cellHeight - 24) / 18))
                let formatter = DateFormatter()
                formatter.dateFormat = "h:mm a"

                for (eventIdx, event) in dayEvents.prefix(maxVisible).enumerated() {
                    let pillY = y + cellHeight - 24 - CGFloat(eventIdx + 1) * 18
                    let pill = createMonthEventPill(event: event, frame: NSRect(x: x + 2, y: pillY, width: dayWidth - 4, height: 16), timeFormatter: formatter)
                    calendarContainer.addSubview(pill)
                    eventViews.append(pill)
                }

                if dayEvents.count > maxVisible {
                    let moreY = y + cellHeight - 24 - CGFloat(maxVisible + 1) * 18
                    let moreLabel = NSTextField(labelWithString: "+\(dayEvents.count - maxVisible) more")
                    moreLabel.font = .systemFont(ofSize: 9)
                    moreLabel.textColor = .secondaryLabelColor
                    moreLabel.frame = NSRect(x: x + 4, y: moreY, width: dayWidth - 8, height: 14)
                    calendarContainer.addSubview(moreLabel)
                }
            }
        }

        // Grid lines
        for row in 0...Int(rowCount) {
            let y = contentHeight - dayNameHeaderHeight - CGFloat(row) * cellHeight
            let line = NSView(frame: NSRect(x: 0, y: y, width: containerWidth, height: 1))
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.separatorColor.cgColor
            calendarContainer.addSubview(line)
        }
        for col in 0...7 {
            let x = CGFloat(col) * dayWidth
            let line = NSView(frame: NSRect(x: x, y: 0, width: 1, height: contentHeight - dayNameHeaderHeight))
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.separatorColor.cgColor
            calendarContainer.addSubview(line)
        }
    }

    // MARK: - Shared Rendering Helpers

    private func renderTimeGrid(in container: NSView, width: CGFloat, columnStart: CGFloat, columnWidth: CGFloat, yOffset: CGFloat) {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"

        for hour in 0..<24 {
            let y = yOffset - CGFloat(hour + 1) * hourHeight

            // Hour label
            let timeStr = formatter.string(from: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!)
            let label = NSTextField(labelWithString: timeStr)
            label.font = .systemFont(ofSize: 10)
            label.textColor = .tertiaryLabelColor
            label.alignment = .right
            label.frame = NSRect(x: 0, y: y + hourHeight - 8, width: timeGutterWidth - 8, height: 14)
            container.addSubview(label)

            // Hour line
            let line = NSView(frame: NSRect(x: columnStart, y: y + hourHeight, width: columnWidth, height: 1))
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
            container.addSubview(line)
        }
    }

    private func renderCurrentTimeLine(in container: NSView, x: CGFloat, width: CGFloat, topY: CGFloat) {
        let now = Date()
        let y = yPosition(for: now, topY: topY)

        // Red line
        let line = NSView(frame: NSRect(x: x, y: y, width: width, height: 2))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.systemRed.cgColor
        container.addSubview(line)

        // Red dot
        let dot = NSView(frame: NSRect(x: x - 4, y: y - 4, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        container.addSubview(dot)
    }

    private func yPosition(for date: Date, topY: CGFloat) -> CGFloat {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let fractionalHour = CGFloat(comps.hour ?? 0) + CGFloat(comps.minute ?? 0) / 60.0
        return topY - fractionalHour * hourHeight
    }

    private func scrollToCurrentTime(contentHeight: CGFloat) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let now = Date()
            let comps = self.calendar.dateComponents([.hour], from: now)
            let scrollHour = max(0, (comps.hour ?? 8) - 2)
            let targetY = contentHeight - self.dayHeaderHeight - CGFloat(scrollHour) * self.hourHeight - self.calendarScrollView.bounds.height
            let clampedY = max(0, min(targetY, contentHeight - self.calendarScrollView.bounds.height))
            self.calendarScrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
        }
    }

    // MARK: - Event Views

    private func createEventView(event: CalendarEvent, frame: NSRect) -> NSView {
        let view = EventPillView(frame: frame)
        view.event = event
        var colors = projectColors
        view.color = colors.color(for: event.schedule.projectRoot)
        projectColors = colors
        view.appearance = effectiveAppearance
        view.onClicked = { [weak self] in
            self?.showEventPopover(event: event, relativeTo: view)
        }
        return view
    }

    private func createMonthEventPill(event: CalendarEvent, frame: NSRect, timeFormatter: DateFormatter) -> NSView {
        let view = EventPillView(frame: frame)
        view.event = event
        view.isCompact = true
        var colors = projectColors
        view.color = colors.color(for: event.schedule.projectRoot)
        projectColors = colors
        view.appearance = effectiveAppearance
        view.onClicked = { [weak self] in
            self?.showEventPopover(event: event, relativeTo: view)
        }
        return view
    }

    // MARK: - Event Popover

    private func showEventPopover(event: CalendarEvent, relativeTo view: NSView) {
        activePopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 280, height: 240)

        let vc = NSViewController()
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 240))
        contentView.wantsLayer = true

        var y: CGFloat = 240

        // Name
        y -= 28
        let nameLabel = NSTextField(labelWithString: event.schedule.name)
        nameLabel.font = .boldSystemFont(ofSize: 14)
        nameLabel.textColor = Theme.primaryText
        nameLabel.frame = NSRect(x: 16, y: y, width: 248, height: 20)
        nameLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(nameLabel)

        // Type badge
        y -= 24
        let typeBadge = NSTextField(labelWithString: event.schedule.type == "swarm" ? "SWARM" : "PROMPT")
        typeBadge.font = .systemFont(ofSize: 9, weight: .bold)
        typeBadge.textColor = .white
        typeBadge.wantsLayer = true
        typeBadge.layer?.cornerRadius = 3
        typeBadge.layer?.backgroundColor = (event.schedule.type == "swarm" ? NSColor.systemPurple : NSColor.systemBlue).cgColor
        typeBadge.alignment = .center
        typeBadge.frame = NSRect(x: 16, y: y, width: 52, height: 16)
        contentView.addSubview(typeBadge)

        // Target
        let targetLabel = NSTextField(labelWithString: event.schedule.target)
        targetLabel.font = .systemFont(ofSize: 12)
        targetLabel.textColor = .secondaryLabelColor
        targetLabel.frame = NSRect(x: 74, y: y, width: 190, height: 16)
        contentView.addSubview(targetLabel)

        // Cron
        y -= 22
        let cronIcon = NSTextField(labelWithString: "Cron:")
        cronIcon.font = .systemFont(ofSize: 11, weight: .medium)
        cronIcon.textColor = .secondaryLabelColor
        cronIcon.frame = NSRect(x: 16, y: y, width: 36, height: 16)
        contentView.addSubview(cronIcon)

        let cronLabel = NSTextField(labelWithString: event.schedule.cronExpression)
        cronLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        cronLabel.textColor = Theme.primaryText
        cronLabel.frame = NSRect(x: 56, y: y, width: 208, height: 16)
        contentView.addSubview(cronLabel)

        // Human description
        y -= 18
        if let parser = CronParser(event.schedule.cronExpression) {
            let humanDesc = parser.humanDescription(expression: event.schedule.cronExpression)
            let humanLabel = NSTextField(labelWithString: humanDesc)
            humanLabel.font = .systemFont(ofSize: 10)
            humanLabel.textColor = .tertiaryLabelColor
            humanLabel.frame = NSRect(x: 56, y: y, width: 208, height: 14)
            contentView.addSubview(humanLabel)
        }

        // Project
        y -= 22
        let projIcon = NSTextField(labelWithString: "Project:")
        projIcon.font = .systemFont(ofSize: 11, weight: .medium)
        projIcon.textColor = .secondaryLabelColor
        projIcon.frame = NSRect(x: 16, y: y, width: 50, height: 16)
        contentView.addSubview(projIcon)

        let projLabel = NSTextField(labelWithString: event.schedule.projectName)
        projLabel.font = .systemFont(ofSize: 11)
        projLabel.textColor = Theme.primaryText
        projLabel.frame = NSRect(x: 70, y: y, width: 194, height: 16)
        contentView.addSubview(projLabel)

        // Variables
        if !event.schedule.vars.isEmpty {
            y -= 20
            let varsHeader = NSTextField(labelWithString: "Variables:")
            varsHeader.font = .systemFont(ofSize: 11, weight: .medium)
            varsHeader.textColor = .secondaryLabelColor
            varsHeader.frame = NSRect(x: 16, y: y, width: 80, height: 16)
            contentView.addSubview(varsHeader)

            for (key, value) in event.schedule.vars {
                y -= 16
                let varLabel = NSTextField(labelWithString: "\(key) = \(value)")
                varLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
                varLabel.textColor = Theme.primaryText
                varLabel.frame = NSRect(x: 24, y: y, width: 240, height: 14)
                contentView.addSubview(varLabel)
            }
        }

        // Buttons
        y -= 12
        let sep = NSBox()
        sep.boxType = .separator
        sep.frame = NSRect(x: 0, y: y, width: 280, height: 1)
        contentView.addSubview(sep)

        y -= 32
        let editBtn = NSButton(title: "Edit", target: self, action: #selector(editScheduleFromPopover(_:)))
        editBtn.bezelStyle = .accessoryBarAction
        editBtn.font = .systemFont(ofSize: 11)
        editBtn.frame = NSRect(x: 16, y: y, width: 60, height: 24)
        editBtn.tag = schedules.firstIndex(where: { $0.name == event.schedule.name && $0.filePath == event.schedule.filePath }) ?? -1
        contentView.addSubview(editBtn)

        let deleteBtn = NSButton(title: "Delete", target: self, action: #selector(deleteScheduleFromPopover(_:)))
        deleteBtn.bezelStyle = .accessoryBarAction
        deleteBtn.contentTintColor = .systemRed
        deleteBtn.font = .systemFont(ofSize: 11)
        deleteBtn.frame = NSRect(x: 84, y: y, width: 60, height: 24)
        deleteBtn.tag = editBtn.tag
        contentView.addSubview(deleteBtn)

        // Resize contentView to fit
        let finalHeight = 240 - y + 8
        contentView.frame = NSRect(x: 0, y: 0, width: 280, height: finalHeight)
        // Shift all subviews down if needed
        let shift = finalHeight - 240
        if shift > 0 {
            for sub in contentView.subviews {
                sub.frame.origin.y += shift
            }
        }
        popover.contentSize = NSSize(width: 280, height: finalHeight)

        vc.view = contentView
        popover.contentViewController = vc
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        activePopover = popover
    }

    @objc private func editScheduleFromPopover(_ sender: NSButton) {
        activePopover?.close()
        let idx = sender.tag
        guard idx >= 0, idx < schedules.count else { return }
        let schedule = schedules[idx]
        showEditDialog(for: schedule)
    }

    @objc private func deleteScheduleFromPopover(_ sender: NSButton) {
        activePopover?.close()
        let idx = sender.tag
        guard idx >= 0, idx < schedules.count else { return }
        deleteSchedule(at: idx)
    }

    // MARK: - Empty Slot Click

    private func handleEmptySlotClick(date: Date) {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let hour = comps.hour ?? 9
        let minute = comps.minute ?? 0
        let dow = calendar.component(.weekday, from: date) - 1
        let dom = calendar.component(.day, from: date)
        let mon = calendar.component(.month, from: date)

        // Generate a reasonable cron expression from the clicked time
        let cronExpr = "\(minute) \(hour) \(dom) \(mon) *"
        showNewScheduleDialog(prefillCron: cronExpr)
    }

    // MARK: - Edit Dialog

    private func showEditDialog(for schedule: ScheduleInfo) {
        guard let content = try? String(contentsOfFile: schedule.filePath, encoding: .utf8) else { return }

        let alert = NSAlert()
        alert.messageText = "Edit Schedule: \(schedule.name)"
        alert.informativeText = ""
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 180))
        var y: CGFloat = 180

        func addLabel(_ text: String) {
            y -= 16
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 0, y: y, width: 300, height: 16)
            accessory.addSubview(label)
            y -= 2
        }

        addLabel("Cron Expression:")
        y -= 24
        let cronField = NSTextField(frame: NSRect(x: 0, y: y, width: 300, height: 24))
        cronField.stringValue = schedule.cronExpression
        accessory.addSubview(cronField)
        y -= 12

        addLabel("Type:")
        y -= 24
        let typePopup = NSPopUpButton(frame: NSRect(x: 0, y: y, width: 300, height: 24), pullsDown: false)
        typePopup.addItem(withTitle: "swarm")
        typePopup.addItem(withTitle: "prompt")
        typePopup.selectItem(withTitle: schedule.type)
        accessory.addSubview(typePopup)
        y -= 12

        addLabel("Target:")
        y -= 24
        let targetField = NSTextField(frame: NSRect(x: 0, y: y, width: 300, height: 24))
        targetField.stringValue = schedule.target
        accessory.addSubview(targetField)

        alert.accessoryView = accessory
        alert.window.initialFirstResponder = cronField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let newCron = cronField.stringValue.trimmingCharacters(in: .whitespaces)
        let newType = typePopup.titleOfSelectedItem ?? schedule.type
        let newTarget = targetField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !newCron.isEmpty, !newTarget.isEmpty else { return }

        // Remove old entry and add new one
        let filtered = removeScheduleEntry(named: schedule.name, from: content)
        let entry = "  - name: \(schedule.name)\n    \(newType): \(newTarget)\n    cron: '\(newCron)'\n"
        let updated = filtered.hasSuffix("\n") ? filtered + entry : filtered + "\n" + entry

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

    // MARK: - Delete

    private func deleteSchedule(at index: Int) {
        guard index < schedules.count else { return }
        let schedule = schedules[index]

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

    private func removeScheduleEntry(named name: String, from content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        var skipping = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") && (trimmed.contains("name:") && trimmed.contains(name)) {
                skipping = true
                continue
            }
            if trimmed.hasPrefix("- name:") && Self.yamlValue(trimmed.replacingOccurrences(of: "- ", with: "")) == name {
                skipping = true
                continue
            }
            if trimmed == "- name: \(name)" || trimmed == "- name: '\(name)'" || trimmed == "- name: \"\(name)\"" {
                skipping = true
                continue
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

    // MARK: - Actions

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
        showNewScheduleDialog(prefillCron: nil)
    }

    private func showNewScheduleDialog(prefillCron: String?) {
        guard !projects.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "New Schedule"
        alert.informativeText = ""
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 260))
        var y: CGFloat = 260

        func addLabel(_ text: String) {
            y -= 16
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 0, y: y, width: 260, height: 16)
            accessory.addSubview(label)
            y -= 2
        }

        func addPopup(_ items: [String]) -> NSPopUpButton {
            y -= 24
            let popup = NSPopUpButton(frame: NSRect(x: 0, y: y, width: 260, height: 24), pullsDown: false)
            for item in items { popup.addItem(withTitle: item) }
            accessory.addSubview(popup)
            y -= 8
            return popup
        }

        addLabel("Name:")
        y -= 24
        let nameField = NSTextField(frame: NSRect(x: 0, y: y, width: 260, height: 24))
        nameField.placeholderString = "schedule-name"
        accessory.addSubview(nameField)
        y -= 12

        addLabel("Cron Expression:")
        y -= 24
        let cronField = NSTextField(frame: NSRect(x: 0, y: y, width: 260, height: 24))
        cronField.placeholderString = "0 * * * *"
        if let prefill = prefillCron {
            cronField.stringValue = prefill
        }
        accessory.addSubview(cronField)
        y -= 12

        addLabel("Type:")
        let typePopup = addPopup(["swarm", "prompt"])

        addLabel("Target (template name):")
        y -= 24
        let targetField = NSTextField(frame: NSRect(x: 0, y: y, width: 260, height: 24))
        targetField.placeholderString = "template-name"
        accessory.addSubview(targetField)
        y -= 12

        addLabel("Project:")
        let projectPopup = addPopup(projects.map { $0.projectName.isEmpty ? $0.projectRoot : $0.projectName })

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

    @objc private func viewModeChanged() {
        viewMode = CalendarViewMode(rawValue: viewModeControl.selectedSegment) ?? .week
        computeEvents()
        renderCalendar()
    }

    @objc private func prevClicked() {
        switch viewMode {
        case .day:
            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
        case .week:
            currentDate = calendar.date(byAdding: .weekOfYear, value: -1, to: currentDate)!
        case .month:
            currentDate = calendar.date(byAdding: .month, value: -1, to: currentDate)!
        }
        computeEvents()
        renderCalendar()
    }

    @objc private func nextClicked() {
        switch viewMode {
        case .day:
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        case .week:
            currentDate = calendar.date(byAdding: .weekOfYear, value: 1, to: currentDate)!
        case .month:
            currentDate = calendar.date(byAdding: .month, value: 1, to: currentDate)!
        }
        computeEvents()
        renderCalendar()
    }

    @objc private func todayClicked() {
        currentDate = Date()
        computeEvents()
        renderCalendar()
    }

    override func layout() {
        super.layout()
        // Re-render on resize to update column widths
        if !schedules.isEmpty || !events.isEmpty {
            renderCalendar()
        }
    }
}

// MARK: - MonthDayCell

private class MonthDayCell: NSView {
    var isCurrentMonth = true
    var isToday = false
    var dayNumber = 1
    var onClicked: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Background
        if isToday {
            let bg = NSColor.systemBlue.withAlphaComponent(0.08)
            bg.setFill()
            bounds.fill()
        } else if !isCurrentMonth {
            let bg = NSColor(name: nil) { $0.isDark ? NSColor(white: 0.08, alpha: 1) : NSColor(white: 0.92, alpha: 1) }
            bg.setFill()
            bounds.fill()
        }

        // Day number
        let numStr = "\(dayNumber)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: isToday ? .bold : .regular),
            .foregroundColor: isToday ? NSColor.systemBlue : (isCurrentMonth ? Theme.primaryText : NSColor.tertiaryLabelColor),
        ]
        let size = numStr.size(withAttributes: attrs)
        numStr.draw(at: NSPoint(x: 6, y: bounds.height - size.height - 4), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        onClicked?()
    }
}

// MARK: - EventPillView

private class EventPillView: NSView {
    var event: CalendarEvent?
    var color: NSColor = .systemBlue
    var isCompact = false
    var onClicked: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let event = event else { return }

        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        color.withAlphaComponent(0.2).setFill()
        path.fill()
        color.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 0.5
        path.stroke()

        // Color left accent bar
        let accent = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 3, height: bounds.height), xRadius: 1.5, yRadius: 1.5)
        color.setFill()
        accent.fill()

        let schedule = event.schedule
        let maxTextWidth = bounds.width - 10

        if isCompact {
            // Compact: just show name
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: color,
            ]
            let text = event.isHighFrequency ? "\u{21BB} \(schedule.name)" : schedule.name
            text.draw(in: NSRect(x: 6, y: 1, width: maxTextWidth, height: 14), withAttributes: attrs)
        } else {
            // Full: name + type badge
            let typeIcon = schedule.type == "swarm" ? "S" : "P"
            let prefix = event.isHighFrequency ? "\u{21BB} " : ""
            let text = "\(prefix)\(typeIcon) \(schedule.name)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: color,
            ]
            text.draw(in: NSRect(x: 6, y: 2, width: maxTextWidth, height: 16), withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onClicked?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
