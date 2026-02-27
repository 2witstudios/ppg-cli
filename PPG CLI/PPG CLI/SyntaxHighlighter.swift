import AppKit

enum SyntaxHighlighter {

    // MARK: - Fonts

    private static let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private static let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
    private static let italicFont: NSFont = {
        NSFontManager.shared.convert(
            NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            toHaveTrait: .italicFontMask
        )
    }()
    private static let boldItalicFont: NSFont = {
        NSFontManager.shared.convert(
            NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
            toHaveTrait: .italicFontMask
        )
    }()

    // MARK: - Markdown Patterns

    private static let headingRegex = try! NSRegularExpression(pattern: "^#{1,6}\\s+.*$", options: .anchorsMatchLines)
    private static let boldRegex = try! NSRegularExpression(pattern: "\\*\\*(?!\\s).+?(?<!\\s)\\*\\*|__(?!\\s).+?(?<!\\s)__")
    private static let italicRegex = try! NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(?!\\s)(.+?)(?<!\\s)(?<!\\*)\\*(?!\\*)|(?<!_)_(?!_)(?!\\s)(.+?)(?<!\\s)(?<!_)_(?!_)")
    private static let inlineCodeRegex = try! NSRegularExpression(pattern: "`[^`]+`")
    private static let codeBlockRegex = try! NSRegularExpression(pattern: "^```.*?^```", options: [.anchorsMatchLines, .dotMatchesLineSeparators])
    private static let linkRegex = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)")
    private static let listRegex = try! NSRegularExpression(pattern: "^(\\s*)([-*]|\\d+\\.)\\s", options: .anchorsMatchLines)
    private static let variableRegex = try! NSRegularExpression(pattern: "\\{\\{\\w+\\}\\}")
    private static let frontmatterRegex = try! NSRegularExpression(pattern: "\\A---\\n.*?\\n---", options: .dotMatchesLineSeparators)
    private static let htmlCommentRegex = try! NSRegularExpression(pattern: "<!--.*?-->", options: .dotMatchesLineSeparators)

    // MARK: - YAML Patterns

    private static let yamlCommentRegex = try! NSRegularExpression(pattern: "#.*$", options: .anchorsMatchLines)
    private static let yamlTopKeyRegex = try! NSRegularExpression(pattern: "^[A-Za-z_][A-Za-z0-9_-]*(?=\\s*:)", options: .anchorsMatchLines)
    private static let yamlKeyRegex = try! NSRegularExpression(pattern: "^(\\s+)[A-Za-z_][A-Za-z0-9_-]*(?=\\s*:)", options: .anchorsMatchLines)
    private static let yamlStringRegex = try! NSRegularExpression(pattern: "(?<=[:\\s])(['\"]).*?\\1")
    private static let yamlBoolRegex = try! NSRegularExpression(pattern: "(?<=:\\s)\\b(true|false)\\b")
    private static let yamlNumberRegex = try! NSRegularExpression(pattern: "(?<=:\\s)-?\\d+\\.?\\d*\\b")
    private static let yamlListMarkerRegex = try! NSRegularExpression(pattern: "^(\\s+)-\\s", options: .anchorsMatchLines)

    // MARK: - Public API

    static func highlightMarkdown(_ storage: NSTextStorage?) {
        guard let storage = storage, storage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        let text = storage.string

        storage.beginEditing()

        // Reset to base style
        storage.addAttributes([
            .foregroundColor: Theme.primaryText,
            .font: monoFont,
        ], range: fullRange)

        // Code blocks (before other rules so they take precedence)
        for match in codeBlockRegex.matches(in: text, range: fullRange) {
            storage.addAttribute(.foregroundColor, value: NSColor.systemGray, range: match.range)
        }

        // Frontmatter delimiters
        for match in frontmatterRegex.matches(in: text, range: fullRange) {
            storage.addAttributes([
                .foregroundColor: NSColor.systemGray,
                .font: italicFont,
            ], range: match.range)
        }

        // HTML comments
        for match in htmlCommentRegex.matches(in: text, range: fullRange) {
            storage.addAttribute(.foregroundColor, value: NSColor.systemGray, range: match.range)
        }

        // Headings
        for match in headingRegex.matches(in: text, range: fullRange) {
            storage.addAttributes([
                .foregroundColor: NSColor.systemBlue,
                .font: boldFont,
            ], range: match.range)
        }

        // Bold
        for match in boldRegex.matches(in: text, range: fullRange) {
            storage.addAttribute(.font, value: boldFont, range: match.range)
        }

        // Italic
        for match in italicRegex.matches(in: text, range: fullRange) {
            storage.addAttribute(.font, value: italicFont, range: match.range)
        }

        // Inline code (after bold/italic so it overrides within backticks)
        for match in inlineCodeRegex.matches(in: text, range: fullRange) {
            storage.addAttribute(.foregroundColor, value: NSColor.systemGray, range: match.range)
        }

        // Links — color the URL part
        for match in linkRegex.matches(in: text, range: fullRange) {
            let urlRange = match.range(at: 2)
            if urlRange.location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: urlRange)
            }
        }

        // List markers
        for match in listRegex.matches(in: text, range: fullRange) {
            let markerRange = match.range(at: 2)
            if markerRange.location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: NSColor.systemGray, range: markerRange)
            }
        }

        // {{VAR}} template variables
        for match in variableRegex.matches(in: text, range: fullRange) {
            storage.addAttributes([
                .foregroundColor: NSColor.systemOrange,
                .font: boldFont,
            ], range: match.range)
        }

        storage.endEditing()
    }

    static func highlightYAML(_ storage: NSTextStorage?) {
        guard let storage = storage, storage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        let text = storage.string

        storage.beginEditing()

        // Reset to base style
        storage.addAttributes([
            .foregroundColor: Theme.primaryText,
            .font: monoFont,
        ], range: fullRange)

        // Comments (apply first, then keys/values override non-comment regions)
        for match in yamlCommentRegex.matches(in: text, range: fullRange) {
            storage.addAttributes([
                .foregroundColor: NSColor.systemGray,
                .font: italicFont,
            ], range: match.range)
        }

        // Top-level keys (bold cyan)
        for match in yamlTopKeyRegex.matches(in: text, range: fullRange) {
            storage.addAttributes([
                .foregroundColor: NSColor.systemCyan,
                .font: boldFont,
            ], range: match.range)
        }

        // Indented keys (cyan, regular weight)
        for match in yamlKeyRegex.matches(in: text, range: fullRange) {
            // Only color the key itself, not the leading whitespace
            let matchStr = (text as NSString).substring(with: match.range)
            let trimmed = matchStr.trimmingCharacters(in: .whitespaces)
            let keyStart = match.range.location + match.range.length - trimmed.count
            let keyRange = NSRange(location: keyStart, length: trimmed.count)
            storage.addAttribute(.foregroundColor, value: NSColor.systemCyan, range: keyRange)
        }

        // String values
        for match in yamlStringRegex.matches(in: text, range: fullRange) {
            storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: match.range)
        }

        // Booleans
        for match in yamlBoolRegex.matches(in: text, range: fullRange) {
            storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: match.range)
        }

        // Numbers
        for match in yamlNumberRegex.matches(in: text, range: fullRange) {
            storage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: match.range)
        }

        // List markers
        for match in yamlListMarkerRegex.matches(in: text, range: fullRange) {
            let dashRange = NSRange(location: match.range.location + match.range.length - 2, length: 1)
            storage.addAttribute(.foregroundColor, value: NSColor.systemGray, range: dashRange)
        }

        storage.endEditing()
    }
}
