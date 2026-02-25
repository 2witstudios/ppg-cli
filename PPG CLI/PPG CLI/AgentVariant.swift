import Foundation

struct AgentVariant {
    let id: String
    let displayName: String
    let icon: String               // SF Symbol name
    let subtitle: String
    let defaultCommand: String
    let needsSessionId: Bool
    let needsUnsetClaudeCode: Bool
    let needsConductorContext: Bool
    let promptDelivery: PromptDelivery
    let promptPlaceholder: String
    let kind: Kind

    enum Kind {
        case agent
        case terminal
        case worktree
    }

    enum PromptDelivery {
        case positionalArg   // Append as: command "prompt text" (Claude, Codex)
        case sendKeys        // Send as tmux keystrokes after launch (OpenCode, Terminal)
        case none            // Not applicable (Worktree — name handled separately)
    }

    // MARK: - Built-in Variants

    static let claude = AgentVariant(
        id: "claude",
        displayName: "Claude",
        icon: "circle.fill",
        subtitle: "AI coding agent",
        defaultCommand: "claude --dangerously-skip-permissions",
        needsSessionId: true,
        needsUnsetClaudeCode: true,
        needsConductorContext: true,
        promptDelivery: .positionalArg,
        promptPlaceholder: "Enter prompt...",
        kind: .agent
    )

    static let codex = AgentVariant(
        id: "codex",
        displayName: "Codex",
        icon: "diamond",
        subtitle: "OpenAI coding CLI",
        defaultCommand: "codex --full-auto",
        needsSessionId: false,
        needsUnsetClaudeCode: false,
        needsConductorContext: false,
        promptDelivery: .positionalArg,
        promptPlaceholder: "Enter prompt...",
        kind: .agent
    )

    static let opencode = AgentVariant(
        id: "opencode",
        displayName: "OpenCode",
        icon: "diamond",
        subtitle: "Open-source agent",
        defaultCommand: "opencode",
        needsSessionId: false,
        needsUnsetClaudeCode: false,
        needsConductorContext: false,
        promptDelivery: .sendKeys,
        promptPlaceholder: "Enter prompt...",
        kind: .agent
    )

    static let terminal = AgentVariant(
        id: "terminal",
        displayName: "Terminal",
        icon: "terminal",
        subtitle: "Shell session",
        defaultCommand: "",
        needsSessionId: false,
        needsUnsetClaudeCode: false,
        needsConductorContext: false,
        promptDelivery: .sendKeys,
        promptPlaceholder: "Enter initial command (optional)...",
        kind: .terminal
    )

    static let worktree = AgentVariant(
        id: "worktree",
        displayName: "Worktree",
        icon: "arrow.triangle.branch",
        subtitle: "Git worktree",
        defaultCommand: "",
        needsSessionId: false,
        needsUnsetClaudeCode: false,
        needsConductorContext: false,
        promptDelivery: .none,
        promptPlaceholder: "Enter worktree name...",
        kind: .worktree
    )

    static let allVariants: [AgentVariant] = [claude, codex, opencode, terminal, worktree]
}
