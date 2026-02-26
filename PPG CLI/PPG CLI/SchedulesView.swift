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

// MARK: - Cron Parser (Swift-native)

struct CronParser {
    /// Generate all occurrences of a cron expression within a date range.
    static func occurrences(of expr: String, from start: Date, to end: Date) -> [Date] {
        let parts = expr.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        guard parts.count == 5 else { return [] }

        let minuteField = parseField(parts[0], range: 0...59)
        let hourField = parseField(parts[1], range: 0...23)
        let domField = parseField(parts[2], range: 1...31)
        let monthField = parseField(parts[3], range: 1...12)
        let dowField = parseField(parts[4], range: 0...6)

        let cal = Calendar.current
        var results: [Date] = []
        var current = cal.date(bySetting: .second, value: 0, of: start) ?? start
        // Align to start of minute
        current = cal.dateInterval(of: .minute, for: current)?.start ?? current

        // Cap iterations to avoid runaway loops
        let maxIterations = 525960 // ~1 year of minutes
        var iterations = 0

        while current <= end && iterations < maxIterations {
            iterations += 1
            let comps = cal.dateComponents([.minute, .hour, .day, .month, .weekday], from: current)
            guard let minute = comps.minute,
                  let hour = comps.hour,
                  let day = comps.day,
                  let month = comps.month,
                  let weekday = comps.weekday else {
                current = cal.date(byAdding: .minute, value: 1, to: current) ?? end
                continue
            }

            // Calendar weekday: 1=Sun. Cron: 0=Sun
            let cronDow = (weekday - 1) % 7

            if minuteField.contains(minute) &&
               hourField.contains(hour) &&
               domField.contains(day) &&
               monthField.contains(month) &&
               dowField.contains(cronDow) {
                results.append(current)
            }

            current = cal.date(byAdding: .minute, value: 1, to: current) ?? end
        }
        return results
    }

    /// Detect if a cron expression fires more often than every 30 minutes.
    static func isHighFrequency(_ expr: String) -> (Bool, String) {
        let parts = expr.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        guard parts.count == 5 else { return (false, "") }

        let minPart = parts[0]
        let hourPart = parts[1]

        // Check */N pattern where N < 30
        if minPart.hasPrefix("*/"), let n = Int(minPart.dropFirst(2)), n < 30, hourPart == "*" {
            return (true, "every \(n) min")
        }
        // Check comma-separated list with many values
        if hourPart == "*" && minPart.contains(",") {
            let vals = parseField(minPart, range: 0...59)
            if vals.count > 2 {
                return (true, "\(vals.count)x/hr")
            }
        }
        return (false, "")
    }

    /// Parse a single cron field into a set of matching integer values.
    static func parseField(_ field: String, range: ClosedRange<Int>) -> Set<Int> {
        var result = Set<Int>()
        let parts = field.split(separator: ",").map(String.init)
        for part in parts {
            if part == "*" {
                result.formUnion(Set(range))
            } else if part.contains("/") {
                let slashParts = part.split(separator: "/").map(String.init)
                guard slashParts.count == 2, let step = Int(slashParts[1]), step > 0 else { continue }
                let basePart = slashParts[0]
                let baseRange: ClosedRange<Int>
                if basePart == "*" {
                    baseRange = range
                } else if basePart.contains("-") {
                    let dashParts = basePart.split(separator: "-").map(String.init)
                    if dashParts.count == 2, let lo = Int(dashParts[0]), let hi = Int(dashParts[1]) {
                        baseRange = max(lo, range.lowerBound)...min(hi, range.upperBound)
                    } else {
                        continue
                    }
                } else if let val = Int(basePart) {
                    baseRange = val...range.upperBound
                } else {
                    continue
                }
                var v = baseRange.lowerBound
                while v <= baseRange.upperBound {
                    result.insert(v)
                    v += step
                }
            } else if part.contains("-") {
                let dashParts = part.split(separator: "-").map(String.init)
                if dashParts.count == 2, let lo = Int(dashParts[0]), let hi = Int(dashParts[1]) {
                    for v in max(lo, range.lowerBound)...min(hi, range.upperBound) {
                        result.insert(v)
                    }
                }
            } else if let val = Int(part), range.contains(val) {
                result.insert(val)
            }
        }
        return result
    }

    /// Human-readable description of a cron expression.
    static func humanReadable(_ expr: String) -> String {
        let parts = expr.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        guard parts.count == 5 else { return expr }
        let (min, hour, dom, mon, dow) = (parts[0], parts[1], parts[2], parts[3], parts[4])

        if min == "0" && hour != "*" && dom == "*" && mon == "*" && dow == "*" {
            return "Daily at \(hour):00"
        }
        if min.hasPrefix("*/") && hour == "*" && dom == "*" && mon == "*" && dow == "*" {
            return "Every \(min.dropFirst(2)) minutes"
        }
        if min != "*" && hour == "*" && dom == "*" && mon == "*" && dow == "*" {
            return "Hourly at :\(min.count == 1 ? "0\(min)" : min)"
        }
        if dow != "*" && dom == "*" && mon == "*" {
            let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let dayName = Int(dow).flatMap({ $0 < days.count ? days[$0] : nil }) ?? dow
            return "\(dayName) at \(hour):\(min.count == 1 ? "0\(min)" : min)"
        }
        return expr
    }
}

// MARK: - Project Colors

struct ProjectColors {
    private static let palette: [NSColor] = [
        .systemBlue, .systemPurple, .systemTeal, .systemIndigo,
        .systemOrange, .systemPink, .systemGreen, .systemYellow
    ]

    static func color(for projectName: String) -> NSColor {
        let hash = abs(projectName.hashValue)
        return palette[hash % palette.count]
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
    private let emptyLabel = NSTextField(labelWithString: "No schedules found. Click + New Schedule to create one.")

    // State
    private var schedules: [ScheduleInfo] = []
    private var projects: [ProjectContext] = []
    private var daemonRunning = false
    private var currentDate = Date()
    private var viewMode: CalendarViewMode = .week

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
        calendarScrollView.isHidden = schedules.isEmpty
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
        viewSwitcher.selectedSegment = 1 // default: week
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

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
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
                wv.heightAnchor.constraint(equalToConstant: 1490), // 24hr * 60 + header
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
                dv.heightAnchor.constraint(equalToConstant: 1490),
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
                // For high-frequency schedules, generate one event per day in the range
                var dayStart = cal.startOfDay(for: start)
                while dayStart <= end {
                    events.append(CalendarEvent(
                        schedule: schedule,
                        date: dayStart,
                        isHighFrequency: true,
                        frequencyLabel: freqLabel
                    ))
                    dayStart = cal.date(byAdding: .day, value: 1, to: dayStart) ?? end
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
        switch viewMode {
        case .day:
            let start = cal.startOfDay(for: currentDate)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
        case .week:
            let weekday = cal.component(.weekday, from: currentDate)
            let start = cal.date(byAdding: .day, value: -(weekday - 1), to: cal.startOfDay(for: currentDate))!
            let end = cal.date(byAdding: .day, value: 7, to: start)!
            return (start, end)
        case .month:
            let comps = cal.dateComponents([.year, .month], from: currentDate)
            let start = cal.date(from: comps)!
            let end = cal.date(byAdding: .month, value: 1, to: start)!
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
            let weekStart = cal.date(byAdding: .day, value: -(weekday - 1), to: currentDate)!
            let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart)!
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

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 280))
        var y: CGFloat = 280

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

        addLabel("Cron Expression:")
        var cronDefault = schedule?.cronExpression ?? "0 * * * *"
        if let date = prefillDate {
            let cal = Calendar.current
            let h = cal.component(.hour, from: date)
            let m = cal.component(.minute, from: date)
            cronDefault = "\(m) \(h) * * *"
        }
        let cronField = addField("0 * * * *", value: cronDefault)

        addLabel("Type:")
        let typePopup = addPopup(["swarm", "prompt"], selected: schedule?.type)

        addLabel("Target (template name):")
        let targetField = addField("template-name", value: schedule?.target ?? "")

        addLabel("Project:")
        let projectNames = projects.map { $0.projectName.isEmpty ? $0.projectRoot : $0.projectName }
        let selectedProject = schedule.flatMap { s in projectNames.first(where: { _ in true }) }
        let projectPopup = addPopup(projectNames, selected: selectedProject)
        if let s = schedule, let idx = projects.firstIndex(where: { $0.projectRoot == s.projectRoot }) {
            projectPopup.selectItem(at: idx)
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

        if isEdit, let oldSchedule = schedule {
            // Remove old entry, then add new one
            deleteScheduleEntry(oldSchedule)
        }

        addScheduleEntry(name: name, cron: cron, type: type, target: target, context: ctx)
    }

    private func addScheduleEntry(name: String, cron: String, type: String, target: String, context: ProjectContext) {
        let ppgDir = (context.projectRoot as NSString).appendingPathComponent(".ppg")
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

        // Wire up button actions via targets
        let schedule = event.schedule
        editBtn.target = self
        editBtn.action = #selector(editFromPopover(_:))
        editBtn.tag = schedules.firstIndex(where: { $0.name == schedule.name && $0.filePath == schedule.filePath }) ?? 0

        deleteBtn.target = self
        deleteBtn.action = #selector(deleteFromPopover(_:))
        deleteBtn.tag = editBtn.tag

        // Store popover reference for dismissal
        editBtn.cell?.representedObject = popover
        deleteBtn.cell?.representedObject = popover

        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
    }

    @objc private func editFromPopover(_ sender: NSButton) {
        if let popover = sender.cell?.representedObject as? NSPopover { popover.close() }
        guard sender.tag >= 0 && sender.tag < schedules.count else { return }
        let schedule = schedules[sender.tag]
        showScheduleDialog(schedule: schedule, prefillDate: nil)
    }

    @objc private func deleteFromPopover(_ sender: NSButton) {
        if let popover = sender.cell?.representedObject as? NSPopover { popover.close() }
        guard sender.tag >= 0 && sender.tag < schedules.count else { return }
        let schedule = schedules[sender.tag]
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

        // Day-of-week headers
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let colWidth = bounds.width / 7
        for (i, name) in dayNames.enumerated() {
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
        let firstWeekday = cal.component(.weekday, from: monthStart) - 1 // 0-based
        let daysInMonth = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30

        let gridTop = bounds.height - headerHeight
        let rowCount = Int(ceil(Double(firstWeekday + daysInMonth) / 7.0))
        let rowHeight = max(gridTop / CGFloat(rowCount), 80)

        let isToday = cal.isDateInToday

        dayRects.removeAll()

        for row in 0..<rowCount {
            for col in 0..<7 {
                let dayIndex = row * 7 + col - firstWeekday + 1
                guard dayIndex >= 1 && dayIndex <= daysInMonth else { continue }

                let x = CGFloat(col) * colWidth + cellPadding
                let y = gridTop - CGFloat(row + 1) * rowHeight + cellPadding
                let w = colWidth - cellPadding * 2
                let h = rowHeight - cellPadding * 2

                let cellRect = NSRect(x: x, y: y, width: w, height: h)

                guard let cellDate = cal.date(bySetting: .day, value: dayIndex, of: monthStart) else { continue }

                dayRects.append((cellRect, cellDate))

                // Today highlight
                if isToday(cellDate) {
                    ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor)
                    ctx.fill(cellRect)
                }

                // Cell border
                ctx.setStrokeColor(NSColor.separatorColor.cgColor)
                ctx.stroke(cellRect)

                // Day number
                let dayStr = "\(dayIndex)"
                let dayAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: isToday(cellDate) ? 13 : 11, weight: isToday(cellDate) ? .bold : .regular),
                    .foregroundColor: isToday(cellDate) ? NSColor.controlAccentColor : Theme.primaryText
                ]
                let dayAttrStr = NSAttributedString(string: dayStr, attributes: dayAttrs)
                dayAttrStr.draw(at: NSPoint(x: x + 4, y: y + h - 18))

                // Events for this day
                let dayEvents = events.filter { cal.isDate($0.date, inSameDayAs: cellDate) }
                let uniqueEvents = Dictionary(grouping: dayEvents, by: { $0.schedule.name }).map { $0.value.first! }
                let maxPills = min(uniqueEvents.count, 3)
                for (i, event) in uniqueEvents.prefix(maxPills).enumerated() {
                    let pillY = y + h - 36 - CGFloat(i) * 18
                    guard pillY > y + 2 else { break }
                    let pillRect = NSRect(x: x + 4, y: pillY, width: w - 8, height: 15)
                    let color = ProjectColors.color(for: event.schedule.projectName)
                    ctx.setFillColor(color.withAlphaComponent(0.2).cgColor)
                    let path = CGPath(roundedRect: pillRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
                    ctx.addPath(path)
                    ctx.fillPath()

                    let typeIcon = event.schedule.type == "swarm" ? "S" : "P"
                    let label = event.isHighFrequency ? "\(typeIcon) \(event.schedule.name) (\(event.frequencyLabel))" : "\(typeIcon) \(event.schedule.name)"
                    let pillAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                        .foregroundColor: color
                    ]
                    let pillStr = NSAttributedString(string: label, attributes: pillAttrs)
                    pillStr.draw(at: NSPoint(x: x + 7, y: pillY + 1))
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
        for (rect, date) in dayRects {
            if rect.contains(loc) {
                // Check if click is on an event pill
                let dayEvents = events.filter { cal.isDate($0.date, inSameDayAs: date) }
                let uniqueEvents = Dictionary(grouping: dayEvents, by: { $0.schedule.name }).map { $0.value.first! }
                if let clickedEvent = uniqueEvents.first {
                    owner?.showEventPopover(for: clickedEvent, relativeTo: NSRect(x: loc.x, y: loc.y, width: 1, height: 1), of: self)
                } else {
                    owner?.handleTimeSlotClick(date: date)
                }
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
    private let hourHeight: CGFloat = 60
    private let headerHeight: CGFloat = 50
    private let timeGutterWidth: CGFloat = 56
    private var eventRects: [(NSRect, CalendarEvent)] = []
    private var hoveredRect: NSRect? = nil

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

    private func weekStart() -> Date {
        let weekday = cal.component(.weekday, from: date)
        return cal.date(byAdding: .day, value: -(weekday - 1), to: cal.startOfDay(for: date))!
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let bounds = self.bounds
        let weekStartDate = weekStart()
        let colWidth = (bounds.width - timeGutterWidth) / 7

        eventRects.removeAll()

        // Day headers
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "d"

        for i in 0..<7 {
            let dayDate = cal.date(byAdding: .day, value: i, to: weekStartDate)!
            let isToday = cal.isDateInToday(dayDate)
            let x = timeGutterWidth + CGFloat(i) * colWidth

            // Background highlight for today column
            if isToday {
                ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.04).cgColor)
                ctx.fill(NSRect(x: x, y: 0, width: colWidth, height: bounds.height - headerHeight))
            }

            // Header text
            let dayNum = dateFmt.string(from: dayDate)
            let label = "\(dayNames[i]) \(dayNum)"
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

        // Hour grid lines and labels
        ctx.setLineWidth(0.5)
        for hour in 0...24 {
            let y = gridTop - CGFloat(hour) * hourHeight
            ctx.setStrokeColor(NSColor.separatorColor.withAlphaComponent(hour % 6 == 0 ? 0.5 : 0.2).cgColor)
            ctx.move(to: CGPoint(x: timeGutterWidth, y: y))
            ctx.addLine(to: CGPoint(x: bounds.width, y: y))
            ctx.strokePath()

            if hour < 24 {
                let h = hour == 0 ? "12 AM" : hour < 12 ? "\(hour) AM" : hour == 12 ? "12 PM" : "\(hour - 12) PM"
                let timeAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]
                let timeStr = NSAttributedString(string: h, attributes: timeAttrs)
                timeStr.draw(at: NSPoint(x: 4, y: y - 6))
            }
        }

        // Column separators
        for i in 0...7 {
            let x = timeGutterWidth + CGFloat(i) * colWidth
            ctx.setStrokeColor(NSColor.separatorColor.withAlphaComponent(0.3).cgColor)
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: gridTop))
            ctx.strokePath()
        }

        // Current time line
        let now = Date()
        let nowWeekday = cal.component(.weekday, from: now)
        if cal.isDate(now, equalTo: weekStartDate, toGranularity: .weekOfYear) {
            let nowHour = cal.component(.hour, from: now)
            let nowMinute = cal.component(.minute, from: now)
            let nowY = gridTop - (CGFloat(nowHour) + CGFloat(nowMinute) / 60.0) * hourHeight
            let nowX = timeGutterWidth + CGFloat(nowWeekday - 1) * colWidth

            ctx.setStrokeColor(NSColor.systemRed.cgColor)
            ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: timeGutterWidth, y: nowY))
            ctx.addLine(to: CGPoint(x: bounds.width, y: nowY))
            ctx.strokePath()

            // Red dot
            ctx.setFillColor(NSColor.systemRed.cgColor)
            ctx.fillEllipse(in: NSRect(x: nowX - 4, y: nowY - 4, width: 8, height: 8))
        }

        // Draw events
        for i in 0..<7 {
            let dayDate = cal.date(byAdding: .day, value: i, to: weekStartDate)!
            let dayEvents = events.filter { cal.isDate($0.date, inSameDayAs: dayDate) }

            let x = timeGutterWidth + CGFloat(i) * colWidth + 2

            for event in dayEvents {
                let color = ProjectColors.color(for: event.schedule.projectName)

                if event.isHighFrequency {
                    // Draw as a full-day stripe
                    let stripeRect = NSRect(x: x, y: 2, width: colWidth - 4, height: gridTop - 4)
                    ctx.setFillColor(color.withAlphaComponent(0.06).cgColor)
                    let path = CGPath(roundedRect: stripeRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
                    ctx.addPath(path)
                    ctx.fillPath()

                    ctx.setStrokeColor(color.withAlphaComponent(0.3).cgColor)
                    ctx.setLineWidth(1)
                    ctx.addPath(path)
                    ctx.strokePath()

                    let typeIcon = event.schedule.type == "swarm" ? "S" : "P"
                    let label = "\(typeIcon) \(event.schedule.name) (\(event.frequencyLabel))"
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                        .foregroundColor: color
                    ]
                    NSAttributedString(string: label, attributes: attrs).draw(at: NSPoint(x: x + 4, y: gridTop - 18))

                    eventRects.append((stripeRect, event))
                } else {
                    let eventHour = cal.component(.hour, from: event.date)
                    let eventMinute = cal.component(.minute, from: event.date)
                    let eventY = gridTop - (CGFloat(eventHour) + CGFloat(eventMinute) / 60.0) * hourHeight
                    let eventHeight: CGFloat = max(hourHeight * 0.8, 24)
                    let eventRect = NSRect(x: x, y: eventY - eventHeight, width: colWidth - 4, height: eventHeight)

                    // Hover highlight
                    if let hr = hoveredRect, hr.intersects(eventRect) {
                        ctx.setFillColor(color.withAlphaComponent(0.25).cgColor)
                    } else {
                        ctx.setFillColor(color.withAlphaComponent(0.15).cgColor)
                    }
                    let path = CGPath(roundedRect: eventRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
                    ctx.addPath(path)
                    ctx.fillPath()

                    // Left accent bar
                    ctx.setFillColor(color.cgColor)
                    ctx.fill(NSRect(x: x, y: eventY - eventHeight, width: 3, height: eventHeight))

                    let typeIcon = event.schedule.type == "swarm" ? "S" : "P"
                    let label = "\(typeIcon) \(event.schedule.name)"
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                        .foregroundColor: color
                    ]
                    let attrStr = NSAttributedString(string: label, attributes: attrs)
                    let textY = eventY - eventHeight + max((eventHeight - 14) / 2, 2)
                    attrStr.draw(in: NSRect(x: x + 6, y: textY, width: colWidth - 14, height: 14))

                    eventRects.append((eventRect, event))
                }
            }
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
    private let hourHeight: CGFloat = 60
    private let headerHeight: CGFloat = 40
    private let timeGutterWidth: CGFloat = 56
    private var eventRects: [(NSRect, CalendarEvent)] = []
    private var hoveredRect: NSRect? = nil

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
        let dayStart = cal.startOfDay(for: date)
        let isToday = cal.isDateInToday(dayStart)

        eventRects.removeAll()

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
        let contentWidth = bounds.width - timeGutterWidth

        // Hour grid
        ctx.setLineWidth(0.5)
        for hour in 0...24 {
            let y = gridTop - CGFloat(hour) * hourHeight
            ctx.setStrokeColor(NSColor.separatorColor.withAlphaComponent(hour % 6 == 0 ? 0.5 : 0.2).cgColor)
            ctx.move(to: CGPoint(x: timeGutterWidth, y: y))
            ctx.addLine(to: CGPoint(x: bounds.width, y: y))
            ctx.strokePath()

            if hour < 24 {
                let h = hour == 0 ? "12 AM" : hour < 12 ? "\(hour) AM" : hour == 12 ? "12 PM" : "\(hour - 12) PM"
                let timeAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]
                NSAttributedString(string: h, attributes: timeAttrs).draw(at: NSPoint(x: 4, y: y - 7))
            }
        }

        // Current time line
        if isToday {
            let now = Date()
            let nowHour = cal.component(.hour, from: now)
            let nowMinute = cal.component(.minute, from: now)
            let nowY = gridTop - (CGFloat(nowHour) + CGFloat(nowMinute) / 60.0) * hourHeight

            ctx.setStrokeColor(NSColor.systemRed.cgColor)
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: timeGutterWidth, y: nowY))
            ctx.addLine(to: CGPoint(x: bounds.width, y: nowY))
            ctx.strokePath()

            ctx.setFillColor(NSColor.systemRed.cgColor)
            ctx.fillEllipse(in: NSRect(x: timeGutterWidth - 5, y: nowY - 5, width: 10, height: 10))
        }

        // Events
        let dayEvents = events.filter { cal.isDate($0.date, inSameDayAs: dayStart) }

        for event in dayEvents {
            let color = ProjectColors.color(for: event.schedule.projectName)
            let x = timeGutterWidth + 4

            if event.isHighFrequency {
                let stripeRect = NSRect(x: x, y: 2, width: contentWidth - 8, height: gridTop - 4)
                ctx.setFillColor(color.withAlphaComponent(0.06).cgColor)
                let path = CGPath(roundedRect: stripeRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
                ctx.addPath(path)
                ctx.fillPath()
                ctx.setStrokeColor(color.withAlphaComponent(0.3).cgColor)
                ctx.setLineWidth(1)
                ctx.addPath(path)
                ctx.strokePath()

                let typeIcon = event.schedule.type == "swarm" ? "S" : "P"
                let label = "\(typeIcon) \(event.schedule.name) \u{2014} \(event.frequencyLabel)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: color
                ]
                NSAttributedString(string: label, attributes: attrs).draw(at: NSPoint(x: x + 6, y: gridTop - 20))

                eventRects.append((stripeRect, event))
            } else {
                let eventHour = cal.component(.hour, from: event.date)
                let eventMinute = cal.component(.minute, from: event.date)
                let eventY = gridTop - (CGFloat(eventHour) + CGFloat(eventMinute) / 60.0) * hourHeight
                let eventHeight: CGFloat = hourHeight * 0.9
                let eventRect = NSRect(x: x, y: eventY - eventHeight, width: contentWidth - 8, height: eventHeight)

                if let hr = hoveredRect, hr.intersects(eventRect) {
                    ctx.setFillColor(color.withAlphaComponent(0.25).cgColor)
                } else {
                    ctx.setFillColor(color.withAlphaComponent(0.15).cgColor)
                }
                let path = CGPath(roundedRect: eventRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
                ctx.addPath(path)
                ctx.fillPath()

                // Left accent bar
                ctx.setFillColor(color.cgColor)
                ctx.fill(NSRect(x: x, y: eventY - eventHeight, width: 3, height: eventHeight))

                // Event text
                let typeIcon = event.schedule.type == "swarm" ? "S" : "P"
                let timeFmt = DateFormatter()
                timeFmt.dateFormat = "h:mm a"
                let timeStr = timeFmt.string(from: event.date)

                let nameStr = NSAttributedString(string: "[\(typeIcon)] \(event.schedule.name)", attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: color
                ])
                nameStr.draw(at: NSPoint(x: x + 8, y: eventY - 18))

                let detailStr = NSAttributedString(string: "\(timeStr) \u{2022} \(event.schedule.target) \u{2022} \(event.schedule.projectName)", attributes: [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: color.withAlphaComponent(0.8)
                ])
                detailStr.draw(at: NSPoint(x: x + 8, y: eventY - 34))

                let cronStr = NSAttributedString(string: CronParser.humanReadable(event.schedule.cronExpression), attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor
                ])
                cronStr.draw(at: NSPoint(x: x + 8, y: eventY - 48))

                eventRects.append((eventRect, event))
            }
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
