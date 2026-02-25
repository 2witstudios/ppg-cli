import AppKit

enum Theme {
    // MARK: - Terminal Colors (adaptive)
    static let terminalBackground = adaptive(dark: (0.11, 0.11, 0.12, 1.0), light: (0.96, 0.955, 0.945, 1.0))
    static let terminalForeground = adaptive(dark: (0.85, 0.85, 0.87, 1.0), light: (0.12, 0.12, 0.14, 1.0))

    // MARK: - Adaptive Chrome
    static let chromeBackground = adaptive(dark: (0.11, 0.11, 0.12, 0.7), light: (0.92, 0.91, 0.90, 0.95))
    static let contentBackground = adaptive(dark: (0.11, 0.11, 0.12, 1.0), light: (0.95, 0.945, 0.935, 1.0))
    static let primaryText = adaptive(dark: (0.85, 0.85, 0.87, 1.0), light: (0.10, 0.10, 0.12, 1.0))

    // MARK: - Cards
    static let cardBackground = adaptive(dark: (0.14, 0.14, 0.15, 1.0), light: (1.0, 1.0, 1.0, 1.0))
    static let cardHeaderBackground = adaptive(dark: (0.16, 0.16, 0.17, 1.0), light: (0.93, 0.925, 0.92, 1.0))
    static let branchTagBackground = adaptiveGray(dark: 0.2, light: 0.85)

    // MARK: - Diff
    static let additionBackground = adaptive(dark: (0.13, 0.22, 0.15, 1.0), light: (0.82, 0.93, 0.84, 1.0))
    static let deletionBackground = adaptive(dark: (0.25, 0.13, 0.13, 1.0), light: (0.94, 0.82, 0.82, 1.0))
    static let additionText = adaptive(dark: (0.55, 0.85, 0.55, 1.0), light: (0.10, 0.42, 0.10, 1.0))
    static let deletionText = adaptive(dark: (0.90, 0.55, 0.55, 1.0), light: (0.58, 0.10, 0.10, 1.0))
    static let hunkSeparator = adaptiveGray(dark: 0.22, light: 0.82)

    // MARK: - Heatmap (adaptive 5 levels)
    static func heatmapLevel(_ level: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            if appearance.isDark {
                switch level {
                case 0: return NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1.0)
                case 1: return NSColor(srgbRed: 0.06, green: 0.27, blue: 0.14, alpha: 1.0)
                case 2: return NSColor(srgbRed: 0.0,  green: 0.41, blue: 0.18, alpha: 1.0)
                case 3: return NSColor(srgbRed: 0.15, green: 0.57, blue: 0.25, alpha: 1.0)
                default: return NSColor(srgbRed: 0.24, green: 0.75, blue: 0.35, alpha: 1.0)
                }
            } else {
                switch level {
                case 0: return NSColor(srgbRed: 0.88, green: 0.87, blue: 0.86, alpha: 1.0)
                case 1: return NSColor(srgbRed: 0.55, green: 0.80, blue: 0.60, alpha: 1.0)
                case 2: return NSColor(srgbRed: 0.35, green: 0.68, blue: 0.42, alpha: 1.0)
                case 3: return NSColor(srgbRed: 0.18, green: 0.58, blue: 0.26, alpha: 1.0)
                default: return NSColor(srgbRed: 0.10, green: 0.48, blue: 0.18, alpha: 1.0)
                }
            }
        }
    }

    // MARK: - Command Palette
    static let paletteBackground = adaptive(dark: (0.13, 0.13, 0.14, 0.95), light: (1.0, 1.0, 1.0, 0.98))
    static let paletteHighlight = adaptiveGray(dark: 0.25, light: 0.88)
    static let paletteBorder = NSColor(name: nil) { $0.isDark ? NSColor(white: 0.3, alpha: 0.5) : NSColor(white: 0.0, alpha: 0.18) }
    static let paletteShadow = NSColor(name: nil) { $0.isDark ? NSColor(white: 0, alpha: 0.5) : NSColor(white: 0, alpha: 0.22) }

    // MARK: - Sidebar
    static let sidebarSelection = NSColor(name: nil) { $0.isDark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.10) }
    static let sidebarHover = NSColor(name: nil) { $0.isDark ? NSColor.white.withAlphaComponent(0.05) : NSColor.black.withAlphaComponent(0.06) }

    // MARK: - Pane Grid
    static let paneOverlayBackground = NSColor(name: nil) { $0.isDark ? NSColor(white: 0.15, alpha: 0.85) : NSColor(white: 0.93, alpha: 0.92) }
    static let paneOverlayBorder = NSColor(name: nil) { $0.isDark ? NSColor(white: 0.3, alpha: 0.5) : NSColor(white: 0.0, alpha: 0.15) }
    static let paneOverlayButtonTint = adaptiveGray(dark: 0.85, light: 0.15)

    // MARK: - Agent Row
    static let agentRowBackground = adaptive(dark: (0.14, 0.14, 0.15, 1.0), light: (0.98, 0.98, 0.98, 1.0))

    // MARK: - Status Color
    static func statusColor(for status: AgentStatus) -> NSColor {
        switch status {
        case .running: return .systemGreen
        case .completed: return .systemBlue
        case .failed: return .systemRed
        case .killed: return .systemOrange
        case .lost, .waiting: return .systemGray
        case .spawning: return .systemYellow
        }
    }

    // MARK: - Helpers

    private static func adaptive(dark: (CGFloat, CGFloat, CGFloat, CGFloat), light: (CGFloat, CGFloat, CGFloat, CGFloat)) -> NSColor {
        NSColor(name: nil) { appearance in
            if appearance.isDark {
                return NSColor(srgbRed: dark.0, green: dark.1, blue: dark.2, alpha: dark.3)
            } else {
                return NSColor(srgbRed: light.0, green: light.1, blue: light.2, alpha: light.3)
            }
        }
    }

    private static func adaptiveGray(dark: CGFloat, light: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            if appearance.isDark {
                return NSColor(white: dark, alpha: 1.0)
            } else {
                return NSColor(white: light, alpha: 1.0)
            }
        }
    }
}

/// NSView subclass that fires a callback when the effective appearance changes.
/// Use as the root view for NSViewControllers that set layer?.backgroundColor with Theme colors.
class ThemeAwareView: NSView {
    var onAppearanceChanged: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChanged?()
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

extension NSColor {
    /// Resolve dynamic NSColor values to a concrete NSColor for the target appearance.
    func resolvedColor(for appearance: NSAppearance) -> NSColor {
        NSColor(cgColor: resolvedCGColor(for: appearance)) ?? self
    }

    /// Resolve dynamic NSColor values to a concrete CGColor for the target appearance.
    func resolvedCGColor(for appearance: NSAppearance) -> CGColor {
        var resolved = cgColor
        appearance.performAsCurrentDrawingAppearance {
            resolved = self.cgColor
        }
        return resolved
    }
}
