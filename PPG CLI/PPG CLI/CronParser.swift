import Foundation

// MARK: - Parsed Cron Expression

/// Pre-parsed cron expression for efficient reuse.
struct CronExpression {
    let raw: String
    let minutes: Set<Int>
    let hours: Set<Int>
    let daysOfMonth: Set<Int>
    let months: Set<Int>
    let daysOfWeek: Set<Int>
    /// Whether the DOM field was explicitly restricted (not "*")
    let domRestricted: Bool
    /// Whether the DOW field was explicitly restricted (not "*")
    let dowRestricted: Bool
}

// MARK: - Cron Parser (Swift-native)

struct CronParser {

    // MARK: - Parsing

    /// Parse a cron expression string into a reusable CronExpression.
    static func parse(_ expr: String) -> CronExpression? {
        let parts = expr.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        guard parts.count == 5 else { return nil }

        return CronExpression(
            raw: expr,
            minutes: parseField(parts[0], range: 0...59),
            hours: parseField(parts[1], range: 0...23),
            daysOfMonth: parseField(parts[2], range: 1...31),
            months: parseField(parts[3], range: 1...12),
            daysOfWeek: parseDowField(parts[4]),
            domRestricted: parts[2] != "*",
            dowRestricted: parts[4] != "*"
        )
    }

    // MARK: - DOW Field Parsing

    /// Parse DOW field with range 0...7, mapping 7 → 0 (both mean Sunday, matching cron-parser).
    private static func parseDowField(_ field: String) -> Set<Int> {
        var result = parseField(field, range: 0...7)
        // Cron convention: 7 is an alias for 0 (Sunday)
        if result.contains(7) {
            result.remove(7)
            result.insert(0)
        }
        return result
    }

    // MARK: - Occurrences (with smart advancement)

    /// Generate all occurrences of a cron expression within a date range.
    /// Uses standard cron semantics: when both DOM and DOW are restricted (not *),
    /// a minute matches if EITHER the DOM or the DOW matches (OR, not AND).
    ///
    /// Uses smart date-advancement to skip non-matching months, days, and hours
    /// instead of iterating every minute.
    static func occurrences(of expr: String, from start: Date, to end: Date) -> [Date] {
        guard let parsed = parse(expr) else { return [] }
        return occurrences(of: parsed, from: start, to: end)
    }

    /// Generate occurrences from a pre-parsed CronExpression.
    static func occurrences(of cron: CronExpression, from start: Date, to end: Date) -> [Date] {
        let cal = Calendar.current
        var results: [Date] = []
        var current = cal.dateInterval(of: .minute, for: start)?.start ?? start

        let maxIterations = 525960 // ~1 year of minutes as safety cap

        var iterations = 0
        while current <= end && iterations < maxIterations {
            iterations += 1
            let comps = cal.dateComponents([.minute, .hour, .day, .month, .year, .weekday], from: current)
            guard let minute = comps.minute,
                  let hour = comps.hour,
                  let day = comps.day,
                  let month = comps.month,
                  let weekday = comps.weekday else {
                current = cal.date(byAdding: .minute, value: 1, to: current) ?? end
                continue
            }

            // Smart advancement: skip non-matching months
            if !cron.months.contains(month) {
                // Advance to start of next month
                if let nextMonth = cal.date(byAdding: .month, value: 1, to: cal.date(from: DateComponents(year: comps.year, month: month, day: 1))!) {
                    current = nextMonth
                    continue
                }
                current = cal.date(byAdding: .minute, value: 1, to: current) ?? end
                continue
            }

            // Calendar weekday: 1=Sun. Cron: 0=Sun
            let cronDow = (weekday - 1) % 7

            // Smart advancement: skip non-matching days
            let dateMatch: Bool
            if cron.domRestricted && cron.dowRestricted {
                dateMatch = cron.daysOfMonth.contains(day) || cron.daysOfWeek.contains(cronDow)
            } else {
                dateMatch = cron.daysOfMonth.contains(day) && cron.daysOfWeek.contains(cronDow)
            }

            if !dateMatch {
                // Skip to start of next day
                if let nextDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: current)) {
                    current = nextDay
                    continue
                }
                current = cal.date(byAdding: .minute, value: 1, to: current) ?? end
                continue
            }

            // Smart advancement: skip non-matching hours
            if !cron.hours.contains(hour) {
                if let nextHour = cal.date(byAdding: .hour, value: 1, to: cal.date(from: DateComponents(year: comps.year, month: month, day: day, hour: hour))!) {
                    current = nextHour
                    continue
                }
                current = cal.date(byAdding: .minute, value: 1, to: current) ?? end
                continue
            }

            // Check minute match
            if cron.minutes.contains(minute) {
                results.append(current)
            }

            current = cal.date(byAdding: .minute, value: 1, to: current) ?? end
        }
        return results
    }

    // MARK: - Next Occurrence

    /// Find the next occurrence of a cron expression after a given date.
    /// Returns nil if no occurrence within the next year.
    static func nextOccurrence(of expr: String, after date: Date) -> Date? {
        guard let parsed = parse(expr) else { return nil }
        return nextOccurrence(of: parsed, after: date)
    }

    /// Find the next occurrence of a pre-parsed CronExpression after a given date.
    static func nextOccurrence(of cron: CronExpression, after date: Date) -> Date? {
        let cal = Calendar.current
        let start = cal.date(byAdding: .minute, value: 1, to: date) ?? date
        guard let end = cal.date(byAdding: .year, value: 1, to: date) else { return nil }
        let results = occurrences(of: cron, from: start, to: end)
        return results.first
    }

    // MARK: - High Frequency Detection

    /// Detect if a cron expression fires more often than every 30 minutes.
    /// Uses analytical approach: counts matching minutes × hours.
    static func isHighFrequency(_ expr: String) -> (Bool, String) {
        guard let parsed = parse(expr) else { return (false, "") }

        let minuteCount = parsed.minutes.count
        let hourCount = parsed.hours.count

        // If all hours are active and many minutes per hour, it's high frequency
        if hourCount >= 20 && minuteCount >= 3 {
            // Estimate average interval
            let firesPerHour = minuteCount
            if firesPerHour >= 4 {
                let interval = 60 / firesPerHour
                return (true, "every ~\(interval) min")
            }
            return (true, "\(firesPerHour)x/hr")
        }

        // Check for specific high-frequency patterns for better labels
        let parts = expr.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        guard parts.count == 5 else { return (false, "") }
        let minPart = parts[0]
        let hourPart = parts[1]

        // */N pattern where N < 30
        if minPart.hasPrefix("*/"), let n = Int(minPart.dropFirst(2)), n < 30, hourPart == "*" {
            return (true, "every \(n) min")
        }

        // General threshold: fires per day > 48 (more than every 30 min)
        let firesPerDay = minuteCount * hourCount
        if firesPerDay > 48 {
            let avgInterval = 1440 / firesPerDay // minutes in a day / fires per day
            if avgInterval < 30 {
                return (true, "~\(avgInterval) min avg")
            }
        }

        return (false, "")
    }

    // MARK: - Field Parsing

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

    // MARK: - Human Readable

    /// Human-readable description of a cron expression.
    static func humanReadable(_ expr: String) -> String {
        let parts = expr.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        guard parts.count == 5 else { return expr }
        let (min, hour, dom, mon, dow) = (parts[0], parts[1], parts[2], parts[3], parts[4])

        // "Daily at H:MM"
        if hour != "*" && dom == "*" && mon == "*" && dow == "*" {
            let hourSet = parseField(hour, range: 0...23)
            let minSet = parseField(min, range: 0...59)
            if hourSet.count == 1, minSet.count == 1,
               let h = hourSet.first, let m = minSet.first {
                let formattedMin = String(format: "%02d", m)
                let period = h >= 12 ? "PM" : "AM"
                let displayHour = h == 0 ? 12 : (h > 12 ? h - 12 : h)
                return "Daily at \(displayHour):\(formattedMin) \(period)"
            }
        }

        // "Every N minutes"
        if min.hasPrefix("*/") && hour == "*" && dom == "*" && mon == "*" && dow == "*" {
            return "Every \(min.dropFirst(2)) minutes"
        }

        // "Hourly at :MM"
        if min != "*" && hour == "*" && dom == "*" && mon == "*" && dow == "*" {
            let minSet = parseField(min, range: 0...59)
            if minSet.count == 1, let m = minSet.first {
                return "Hourly at :\(String(format: "%02d", m))"
            }
            return "Hourly at :\(min.count == 1 ? "0\(min)" : min)"
        }

        // "Mon at H:MM" (weekday schedule)
        if dow != "*" && dom == "*" && mon == "*" {
            let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let dowSet = parseDowField(dow)
            let dayNames: String
            if dowSet.count == 1, let d = dowSet.first, d < days.count {
                dayNames = days[d]
            } else {
                dayNames = dowSet.sorted().compactMap { $0 < days.count ? days[$0] : nil }.joined(separator: ", ")
            }
            let minStr = min.count == 1 ? "0\(min)" : min
            let hourSet = parseField(hour, range: 0...23)
            if hourSet.count == 1, let h = hourSet.first {
                let period = h >= 12 ? "PM" : "AM"
                let displayHour = h == 0 ? 12 : (h > 12 ? h - 12 : h)
                let minSet = parseField(min, range: 0...59)
                let formattedMin = minSet.count == 1 ? String(format: "%02d", minSet.first!) : minStr
                return "\(dayNames) at \(displayHour):\(formattedMin) \(period)"
            }
            return "\(dayNames) at \(hour):\(minStr)"
        }

        // "Monthly on the Nth at H:MM"
        if dom != "*" && mon == "*" && dow == "*" {
            let domSet = parseField(dom, range: 1...31)
            if domSet.count == 1, let d = domSet.first {
                let ordinal = Self.ordinalSuffix(d)
                let hourSet = parseField(hour, range: 0...23)
                let minSet = parseField(min, range: 0...59)
                if hourSet.count == 1, let h = hourSet.first,
                   minSet.count == 1, let m = minSet.first {
                    let period = h >= 12 ? "PM" : "AM"
                    let displayHour = h == 0 ? 12 : (h > 12 ? h - 12 : h)
                    return "Monthly on the \(d)\(ordinal) at \(displayHour):\(String(format: "%02d", m)) \(period)"
                }
            }
        }

        return expr
    }

    /// Returns the ordinal suffix for a number (1st, 2nd, 3rd, 4th, etc.)
    private static func ordinalSuffix(_ n: Int) -> String {
        let tens = n % 100
        if tens >= 11 && tens <= 13 { return "th" }
        switch n % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}
