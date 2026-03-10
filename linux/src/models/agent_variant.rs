/// Agent variant definitions matching the macOS app's AgentVariant.swift.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PromptDelivery {
    /// Append prompt as a positional argument.
    PositionalArg,
    /// Send prompt as tmux keystrokes after launch.
    SendKeys,
    /// Not applicable (e.g., plain worktree).
    None,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VariantKind {
    Agent,
    Terminal,
    Worktree,
}

#[derive(Debug, Clone)]
pub struct AgentVariant {
    pub id: &'static str,
    pub display_name: &'static str,
    pub icon_name: &'static str,
    pub subtitle: &'static str,
    pub default_command: &'static str,
    pub prompt_delivery: PromptDelivery,
    pub prompt_placeholder: &'static str,
    pub kind: VariantKind,
}

pub const CLAUDE: AgentVariant = AgentVariant {
    id: "claude",
    display_name: "Claude",
    icon_name: "user-available-symbolic",
    subtitle: "AI coding agent",
    default_command: "claude --dangerously-skip-permissions",
    prompt_delivery: PromptDelivery::PositionalArg,
    prompt_placeholder: "Enter prompt...",
    kind: VariantKind::Agent,
};

pub const CODEX: AgentVariant = AgentVariant {
    id: "codex",
    display_name: "Codex",
    icon_name: "applications-engineering-symbolic",
    subtitle: "OpenAI coding CLI",
    default_command: "codex --full-auto",
    prompt_delivery: PromptDelivery::PositionalArg,
    prompt_placeholder: "Enter prompt...",
    kind: VariantKind::Agent,
};

pub const OPENCODE: AgentVariant = AgentVariant {
    id: "opencode",
    display_name: "OpenCode",
    icon_name: "applications-science-symbolic",
    subtitle: "Open-source agent",
    default_command: "opencode",
    prompt_delivery: PromptDelivery::SendKeys,
    prompt_placeholder: "Enter prompt...",
    kind: VariantKind::Agent,
};

pub const TERMINAL: AgentVariant = AgentVariant {
    id: "terminal",
    display_name: "Terminal",
    icon_name: "utilities-terminal-symbolic",
    subtitle: "Shell session",
    default_command: "",
    prompt_delivery: PromptDelivery::SendKeys,
    prompt_placeholder: "Enter initial command (optional)...",
    kind: VariantKind::Terminal,
};

pub const WORKTREE: AgentVariant = AgentVariant {
    id: "worktree",
    display_name: "Worktree",
    icon_name: "folder-symbolic",
    subtitle: "Git worktree",
    default_command: "",
    prompt_delivery: PromptDelivery::None,
    prompt_placeholder: "Enter worktree name...",
    kind: VariantKind::Worktree,
};

pub fn all_variants() -> Vec<&'static AgentVariant> {
    vec![&CLAUDE, &CODEX, &OPENCODE, &TERMINAL, &WORKTREE]
}

pub fn pane_variants() -> Vec<&'static AgentVariant> {
    all_variants()
        .into_iter()
        .filter(|v| v.kind != VariantKind::Worktree)
        .collect()
}
