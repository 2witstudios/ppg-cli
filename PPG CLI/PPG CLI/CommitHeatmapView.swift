import AppKit

/// GitHub-style commit heatmap: 7 rows (days) x 13 columns (weeks) = 91 days of history.
class CommitHeatmapView: NSView {

    struct HeatmapData {
        /// Maps "YYYY-MM-DD" date strings to commit counts.
        let commitsByDate: [String: Int]
    }

    // MARK: - Configuration

    private static let cellSize: CGFloat = 10
    private static let cellGap: CGFloat = 2
    private static let stride: CGFloat = cellSize + cellGap   // 12
    private static let rows = 7
    private static let cols = 13
    private static let dayLabelWidth: CGFloat = 24
    private static let monthLabelHeight: CGFloat = 14

    // 5-level green color scale (empty → bright green)
    private static let levelColors: [NSColor] = [
        NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1.0),  // level 0 — empty
        NSColor(srgbRed: 0.06, green: 0.27, blue: 0.14, alpha: 1.0),  // level 1
        NSColor(srgbRed: 0.0,  green: 0.41, blue: 0.18, alpha: 1.0),  // level 2
        NSColor(srgbRed: 0.15, green: 0.57, blue: 0.25, alpha: 1.0),  // level 3
        NSColor(srgbRed: 0.24, green: 0.75, blue: 0.35, alpha: 1.0),  // level 4
    ]

    private var data: HeatmapData?
    private var trackingArea: NSTrackingArea?

    // Pre-computed grid: (date, count, rect) for each cell
    private var cellInfos: [(date: String, count: Int, rect: NSRect)] = []

    // MARK: - Public API

    func configure(heatmapData: HeatmapData) {
        self.data = heatmapData
        recomputeCells()
        needsDisplay = true
    }

    // MARK: - Intrinsic Size

    override var intrinsicContentSize: NSSize {
        let width = Self.dayLabelWidth + CGFloat(Self.cols) * Self.stride
        let height = Self.monthLabelHeight + CGFloat(Self.rows) * Self.stride
        return NSSize(width: width, height: height)
    }

    // MARK: - Layout

    private func recomputeCells() {
        cellInfos.removeAll(keepingCapacity: true)
        guard let data = data else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let originX = Self.dayLabelWidth
        let originY: CGFloat = 0  // grid starts at bottom

        // Compute the start date: go back 90 days from today (91 days total including today).
        // Align to the start of a week (Sunday = column 0).
        let daysBack = 90
        guard let startDate = calendar.date(byAdding: .day, value: -daysBack, to: today) else { return }

        // Iterate 91 days
        for dayOffset in 0...daysBack {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else { continue }
            let dateStr = formatter.string(from: date)
            let count = data.commitsByDate[dateStr] ?? 0

            // Row = weekday (0=Sun at top, 6=Sat at bottom).  We draw bottom-up, so invert.
            let weekday = calendar.component(.weekday, from: date) - 1  // 0-based, 0=Sun
            let row = 6 - weekday  // bottom=Sat, top=Sun → visually Mon=row5, Wed=row3, Fri=row1

            // Column = week offset from startDate
            let daysSinceStart = calendar.dateComponents([.day], from: startDate, to: date).day ?? 0
            let startWeekday = calendar.component(.weekday, from: startDate) - 1
            let col = (daysSinceStart + startWeekday) / 7

            guard col >= 0, col < Self.cols else { continue }

            let x = originX + CGFloat(col) * Self.stride
            let y = originY + CGFloat(row) * Self.stride
            let rect = NSRect(x: x, y: y, width: Self.cellSize, height: Self.cellSize)
            cellInfos.append((date: dateStr, count: count, rect: rect))
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let maxCount = cellInfos.map(\.count).max() ?? 1

        // Draw cells
        for info in cellInfos {
            let level: Int
            if info.count == 0 {
                level = 0
            } else {
                let ratio = Double(info.count) / Double(max(maxCount, 1))
                level = min(4, Int(ratio * 4.0) + 1)
            }
            let color = Self.levelColors[level]
            ctx.setFillColor(color.cgColor)

            let path = CGPath(roundedRect: info.rect, cornerWidth: 2, cornerHeight: 2, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()
        }

        // Day labels (left side)
        let dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let labelFont = NSFont.systemFont(ofSize: 9)
        let labelColor = NSColor.secondaryLabelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: labelColor,
        ]
        // Only show Mon, Wed, Fri
        for (idx, label) in dayLabels.enumerated() {
            guard idx == 1 || idx == 3 || idx == 5 else { continue }
            let row = 6 - idx  // same inversion as grid
            let y = CGFloat(row) * Self.stride
            let str = NSAttributedString(string: label, attributes: attrs)
            str.draw(at: NSPoint(x: 0, y: y))
        }

        // Month labels (top)
        drawMonthLabels(ctx: ctx, attrs: attrs)
    }

    private func drawMonthLabels(ctx: CGContext, attrs: [NSAttributedString.Key: Any]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -90, to: today) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        let topY = CGFloat(Self.rows) * Self.stride + 1

        var lastMonth = -1
        for col in 0..<Self.cols {
            // The date at row 0 (Sunday) of this column
            let startWeekday = calendar.component(.weekday, from: startDate) - 1
            let dayOffset = col * 7 - startWeekday
            guard let colDate = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else { continue }
            let month = calendar.component(.month, from: colDate)
            if month != lastMonth {
                lastMonth = month
                let label = NSAttributedString(string: formatter.string(from: colDate), attributes: attrs)
                let x = Self.dayLabelWidth + CGFloat(col) * Self.stride
                label.draw(at: NSPoint(x: x, y: topY))
            }
        }
    }

    // MARK: - Tooltip

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        for info in cellInfos {
            if info.rect.contains(loc) {
                toolTip = "\(info.date): \(info.count) commit\(info.count == 1 ? "" : "s")"
                return
            }
        }
        toolTip = nil
    }
}
