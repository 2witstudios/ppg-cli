import Foundation

// MARK: - CronParser

/// Evaluates 5-field cron expressions and computes occurrences within a date range.
/// Fields: minute (0-59), hour (0-23), day-of-month (1-31), month (1-12), day-of-week (0-6, 0=Sunday).
/// Supports: * (any), N (exact), N-M (range), N,M,O (list), */N (step), N-M/S (range with step).
struct CronParser {

    struct CronExpression {
        let minutes: Set<Int>
        let hours: Set<Int>
        let daysOfMonth: Set<Int>
        let months: Set<Int>
        let daysOfWeek: Set<Int>
        let raw: String
    }

    enum ParseError: Error {
        case invalidFieldCount(String)
        case invalidField(String, String)
    }

    // MARK: - Parsing

    static func parse(_ expression: String) throws -> CronExpression {
        let parts = expression.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 5 else {
            throw ParseError.invalidFieldCount(expression)
        }

        let minutes = try parseField(parts[0], min: 0, max: 59, name: "minute")
        let hours = try parseField(parts[1], min: 0, max: 23, name: "hour")
        let daysOfMonth = try parseField(parts[2], min: 1, max: 31, name: "day-of-month")
        let months = try parseField(parts[3], min: 1, max: 12, name: "month")
        let daysOfWeek = try parseField(parts[4], min: 0, max: 6, name: "day-of-week")

        return CronExpression(
            minutes: minutes,
            hours: hours,
            daysOfMonth: daysOfMonth,
            months: months,
            daysOfWeek: daysOfWeek,
            raw: expression
        )
    }

    private static func parseField(_ field: String, min: Int, max: Int, name: String) throws -> Set<Int> {
        var result = Set<Int>()

        // Handle comma-separated list
        let parts = field.split(separator: ",").map(String.init)
        for part in parts {
            let values = try parsePart(part.trimmingCharacters(in: .whitespaces), min: min, max: max, name: name)
            result.formUnion(values)
        }

        return result
    }

    private static func parsePart(_ part: String, min: Int, max: Int, name: String) throws -> Set<Int> {
        // Check for step: */N or N-M/S
        let stepComponents = part.split(separator: "/", maxSplits: 1).map(String.init)

        if stepComponents.count == 2 {
            guard let step = Int(stepComponents[1]), step > 0 else {
                throw ParseError.invalidField(name, part)
            }
            let range: (Int, Int)
            if stepComponents[0] == "*" {
                range = (min, max)
            } else if stepComponents[0].contains("-") {
                range = try parseRange(stepComponents[0], min: min, max: max, name: name)
            } else {
                // N/S — start at N, step by S
                guard let start = Int(stepComponents[0]), start >= min, start <= max else {
                    throw ParseError.invalidField(name, part)
                }
                range = (start, max)
            }
            var result = Set<Int>()
            var current = range.0
            while current <= range.1 {
                result.insert(current)
                current += step
            }
            return result
        }

        // Wildcard
        if part == "*" {
            return Set(min...max)
        }

        // Range: N-M
        if part.contains("-") {
            let r = try parseRange(part, min: min, max: max, name: name)
            return Set(r.0...r.1)
        }

        // Exact value
        guard let value = Int(part), value >= min, value <= max else {
            throw ParseError.invalidField(name, part)
        }
        return Set([value])
    }

    private static func parseRange(_ part: String, min: Int, max: Int, name: String) throws -> (Int, Int) {
        let rangeParts = part.split(separator: "-", maxSplits: 1).map(String.init)
        guard rangeParts.count == 2,
              let start = Int(rangeParts[0]),
              let end = Int(rangeParts[1]),
              start >= min, end <= max, start <= end else {
            throw ParseError.invalidField(name, part)
        }
        return (start, end)
    }

    // MARK: - Occurrence Computation

    /// Compute all cron occurrences within the given date range.
    /// Returns at most `limit` results.
    static func occurrences(
        of expression: CronExpression,
        from startDate: Date,
        to endDate: Date,
        calendar: Calendar = .current,
        limit: Int = 1000
    ) -> [Date] {
        guard startDate < endDate else { return [] }

        var results: [Date] = []

        // Start from the beginning of the minute of startDate
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: startDate)
        comps.second = 0

        guard var current = calendar.date(from: comps) else { return [] }

        while current <= endDate && results.count < limit {
            let c = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: current)

            guard let minute = c.minute, let hour = c.hour,
                  let day = c.day, let month = c.month,
                  let weekday = c.weekday else {
                // Advance by 1 minute
                current = calendar.date(byAdding: .minute, value: 1, to: current) ?? endDate
                continue
            }

            // Calendar weekday is 1=Sunday..7=Saturday, cron is 0=Sunday..6=Saturday
            let cronWeekday = weekday - 1

            if expression.months.contains(month) &&
               expression.daysOfMonth.contains(day) &&
               expression.daysOfWeek.contains(cronWeekday) &&
               expression.hours.contains(hour) &&
               expression.minutes.contains(minute) {
                if current >= startDate {
                    results.append(current)
                }
            }

            // Smart advancement: if month doesn't match, skip to next month
            if !expression.months.contains(month) {
                if let nextMonth = calendar.date(byAdding: .month, value: 1, to: calendar.startOfDay(for: current)) {
                    var nc = calendar.dateComponents([.year, .month], from: nextMonth)
                    nc.day = 1; nc.hour = 0; nc.minute = 0; nc.second = 0
                    current = calendar.date(from: nc) ?? endDate
                    continue
                }
            }

            // If day doesn't match both day-of-month and day-of-week, skip to next day
            if !expression.daysOfMonth.contains(day) || !expression.daysOfWeek.contains(cronWeekday) {
                if let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: current)) {
                    current = nextDay
                    continue
                }
            }

            // If hour doesn't match, skip to next hour
            if !expression.hours.contains(hour) {
                if let nextHour = calendar.date(byAdding: .hour, value: 1, to: current) {
                    var nc = calendar.dateComponents([.year, .month, .day, .hour], from: nextHour)
                    nc.minute = 0; nc.second = 0
                    current = calendar.date(from: nc) ?? endDate
                    continue
                }
            }

            // Advance by 1 minute
            current = calendar.date(byAdding: .minute, value: 1, to: current) ?? endDate
        }

        return results
    }

    /// Check if a cron expression fires more than the given threshold per day.
    static func isHighFrequency(_ expression: CronExpression, threshold: Int = 48) -> Bool {
        // Count: matching minutes × matching hours (for a full day where month/dom/dow all match)
        let matchingMinutes = expression.minutes.count
        let matchingHours = expression.hours.count
        return matchingMinutes * matchingHours > threshold
    }

    // MARK: - Next Run

    /// Compute the next occurrence after `date`.
    static func nextOccurrence(
        of expression: CronExpression,
        after date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let nextMinute = calendar.date(byAdding: .minute, value: 1, to: date) ?? date
        let farFuture = calendar.date(byAdding: .year, value: 1, to: date) ?? date
        let results = occurrences(of: expression, from: nextMinute, to: farFuture, calendar: calendar, limit: 1)
        return results.first
    }

    // MARK: - Human-Readable Description

    static func humanReadable(_ expression: String) -> String {
        let parts = expression.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 5 else { return expression }

        let (min, hour, dom, mon, dow) = (parts[0], parts[1], parts[2], parts[3], parts[4])

        // Daily at specific time
        if min != "*" && hour != "*" && dom == "*" && mon == "*" && dow == "*" {
            if let m = Int(min), let h = Int(hour) {
                return "Every day at \(String(format: "%d:%02d", h, m))"
            }
        }

        // Every N minutes
        if min.hasPrefix("*/"), hour == "*" && dom == "*" && mon == "*" && dow == "*" {
            let interval = String(min.dropFirst(2))
            return "Every \(interval) minutes"
        }

        // Hourly at :MM
        if min != "*" && hour == "*" && dom == "*" && mon == "*" && dow == "*" {
            if let m = Int(min) {
                return "Every hour at :\(String(format: "%02d", m))"
            }
        }

        // Weekly on specific day
        if dow != "*" && dom == "*" && mon == "*" {
            let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            if let d = Int(dow), d >= 0, d < 7 {
                if let m = Int(min), let h = Int(hour) {
                    return "\(days[d]) at \(String(format: "%d:%02d", h, m))"
                }
                return "Every \(days[d])"
            }
        }

        // Monthly on specific day
        if dom != "*" && mon == "*" && dow == "*" {
            if let d = Int(dom), let m = Int(min), let h = Int(hour) {
                let suffix: String
                switch d {
                case 1, 21, 31: suffix = "st"
                case 2, 22: suffix = "nd"
                case 3, 23: suffix = "rd"
                default: suffix = "th"
                }
                return "Monthly on the \(d)\(suffix) at \(String(format: "%d:%02d", h, m))"
            }
        }

        return expression
    }
}
