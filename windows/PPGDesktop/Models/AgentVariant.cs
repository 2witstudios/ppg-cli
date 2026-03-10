namespace PPGDesktop.Models;

public record AgentVariant(
    string Id,
    string DisplayName,
    string Icon,
    string Subtitle,
    string DefaultCommand
)
{
    public static readonly AgentVariant[] BuiltIn =
    [
        new("claude", "Claude Code", "\uE8A4", "Anthropic AI coding agent", "claude"),
        new("codex", "Codex CLI", "\uE8A4", "OpenAI Codex coding agent", "codex"),
        new("opencode", "OpenCode", "\uE8A4", "Open-source coding agent", "opencode"),
        new("aider", "Aider", "\uE8A4", "AI pair programming", "aider"),
        new("terminal", "Terminal", "\uE756", "Raw terminal session", "bash"),
    ];
}
