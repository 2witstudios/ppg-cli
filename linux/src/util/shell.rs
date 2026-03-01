/// Shell-escape a string for safe use in tmux send-keys or shell commands.
pub fn shell_escape(s: &str) -> String {
    if s.is_empty() {
        return "''".to_string();
    }
    if s.chars()
        .all(|c| c.is_alphanumeric() || c == '-' || c == '_' || c == '.' || c == '/' || c == ':')
    {
        return s.to_string();
    }
    format!("'{}'", s.replace('\'', "'\\''"))
}

/// Build a tmux attach command that connects to a specific session/window.
pub fn tmux_attach_command(session_name: &str, window_target: &str) -> Vec<String> {
    vec![
        "tmux".to_string(),
        "new-session".to_string(),
        "-t".to_string(),
        session_name.to_string(),
        "-s".to_string(),
        format!("{}-view-{}", session_name, window_target),
        ";".to_string(),
        "set-option".to_string(),
        "destroy-unattached".to_string(),
        "on".to_string(),
        ";".to_string(),
        "set-option".to_string(),
        "status".to_string(),
        "off".to_string(),
        ";".to_string(),
        "set-option".to_string(),
        "mouse".to_string(),
        "on".to_string(),
        ";".to_string(),
        "select-window".to_string(),
        "-t".to_string(),
        format!(":{}", window_target),
    ]
}

/// Build a tmux attach command as a single shell string (for VTE spawn).
pub fn tmux_attach_shell_command(session_name: &str, window_target: &str) -> String {
    format!(
        "tmux new-session -t {} -s {}-view-{} \
         \\; set-option destroy-unattached on \
         \\; set-option status off \
         \\; set-option mouse on \
         \\; select-window -t :{}",
        shell_escape(session_name),
        shell_escape(session_name),
        shell_escape(window_target),
        shell_escape(window_target),
    )
}

/// Check if a command is available in PATH.
pub fn command_exists(cmd: &str) -> bool {
    std::process::Command::new("which")
        .arg(cmd)
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_shell_escape_simple() {
        assert_eq!(shell_escape("hello"), "hello");
        assert_eq!(shell_escape("path/to/file"), "path/to/file");
    }

    #[test]
    fn test_shell_escape_special() {
        assert_eq!(shell_escape("hello world"), "'hello world'");
        assert_eq!(shell_escape("it's"), "'it'\\''s'");
    }

    #[test]
    fn test_shell_escape_empty() {
        assert_eq!(shell_escape(""), "''");
    }

    #[test]
    fn test_command_exists() {
        assert!(command_exists("sh"));
        assert!(!command_exists("nonexistent_binary_xyz"));
    }
}
