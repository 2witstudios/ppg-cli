import SwiftUI
import SwiftTerm

// MARK: - Glass Theme

/// Centralized glass effect and color configuration for iOS 26+.
/// Mirrors the macOS Theme.swift color values for visual consistency.
enum GlassTheme {

    // MARK: - ANSI Terminal Palette

    /// 16-color ANSI palette matching macOS ScrollableTerminalView colors.
    static func ansiPalette() -> [SwiftTerm.Color] {
        let palette: [(CGFloat, CGFloat, CGFloat)] = [
            (0.11, 0.11, 0.12), // 0 black
            (0.78, 0.35, 0.35), // 1 red
            (0.43, 0.68, 0.47), // 2 green
            (0.79, 0.67, 0.40), // 3 yellow
            (0.43, 0.61, 0.90), // 4 blue
            (0.72, 0.53, 0.86), // 5 magenta
            (0.39, 0.72, 0.78), // 6 cyan
            (0.68, 0.68, 0.70), // 7 white
            (0.34, 0.35, 0.37), // 8 bright black
            (0.89, 0.48, 0.48), // 9 bright red
            (0.55, 0.84, 0.60), // 10 bright green
            (0.90, 0.78, 0.50), // 11 bright yellow
            (0.54, 0.70, 0.94), // 12 bright blue
            (0.80, 0.63, 0.91), // 13 bright magenta
            (0.49, 0.79, 0.84), // 14 bright cyan
            (0.94, 0.94, 0.95), // 15 bright white
        ]
        return palette.map { makeTerminalColor(red: $0.0, green: $0.1, blue: $0.2) }
    }

    static func makeTerminalColor(red: CGFloat, green: CGFloat, blue: CGFloat) -> SwiftTerm.Color {
        SwiftTerm.Color(
            red: UInt16((max(0, min(1, red)) * 65535).rounded()),
            green: UInt16((max(0, min(1, green)) * 65535).rounded()),
            blue: UInt16((max(0, min(1, blue)) * 65535).rounded())
        )
    }

    // MARK: - Terminal Colors

    static let terminalBackground = SwiftUI.Color(red: 0.11, green: 0.11, blue: 0.12)
    static let terminalForeground = SwiftUI.Color(red: 0.85, green: 0.85, blue: 0.87)

    // MARK: - Card Styling

    static let cardCornerRadius: CGFloat = 8
    static let cardPadding: CGFloat = 8

    // MARK: - Heatmap Levels (dark mode)

    static func heatmapColor(level: Int) -> SwiftUI.Color {
        switch level {
        case 0: SwiftUI.Color(red: 0.16, green: 0.16, blue: 0.17)
        case 1: SwiftUI.Color(red: 0.06, green: 0.27, blue: 0.14)
        case 2: SwiftUI.Color(red: 0.0,  green: 0.41, blue: 0.18)
        case 3: SwiftUI.Color(red: 0.15, green: 0.57, blue: 0.25)
        default: SwiftUI.Color(red: 0.24, green: 0.75, blue: 0.35)
        }
    }
}

// MARK: - Glass Card Modifier

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = GlassTheme.cardCornerRadius
    var padding: CGFloat = GlassTheme.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = GlassTheme.cardCornerRadius, padding: CGFloat = GlassTheme.cardPadding) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}
