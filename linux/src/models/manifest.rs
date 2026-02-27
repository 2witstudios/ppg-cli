use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AgentStatus {
    Running,
    Idle,
    Exited,
    Gone,
}

impl AgentStatus {
    pub fn css_class(&self) -> &'static str {
        match self {
            Self::Running => "status-running",
            Self::Idle => "status-idle",
            Self::Exited => "status-exited",
            Self::Gone => "status-gone",
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            Self::Running => "Running",
            Self::Idle => "Idle",
            Self::Exited => "Exited",
            Self::Gone => "Gone",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum WorktreeStatus {
    Active,
    Merging,
    Merged,
    Failed,
    Cleaned,
}

impl WorktreeStatus {
    pub fn css_class(&self) -> &'static str {
        match self {
            Self::Active => "status-running",
            Self::Merging => "status-idle",
            Self::Merged => "status-exited",
            Self::Failed => "status-failed",
            Self::Cleaned => "status-gone",
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            Self::Active => "Active",
            Self::Merging => "Merging",
            Self::Merged => "Merged",
            Self::Failed => "Failed",
            Self::Cleaned => "Cleaned",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentEntry {
    pub id: String,
    pub name: String,
    pub agent_type: String,
    pub status: AgentStatus,
    pub tmux_target: String,
    pub prompt: String,
    pub started_at: String,
    pub exit_code: Option<i32>,
    pub session_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorktreeEntry {
    pub id: String,
    pub name: String,
    pub path: String,
    pub branch: String,
    pub base_branch: String,
    pub status: WorktreeStatus,
    pub tmux_window: String,
    pub pr_url: Option<String>,
    pub agents: HashMap<String, AgentEntry>,
    pub created_at: String,
    pub merged_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Manifest {
    pub version: u32,
    pub project_root: String,
    pub session_name: String,
    pub worktrees: HashMap<String, WorktreeEntry>,
    pub created_at: String,
    pub updated_at: String,
}

impl Manifest {
    /// Count agents across all worktrees matching a given status.
    pub fn count_agents_by_status(&self, status: AgentStatus) -> usize {
        self.worktrees
            .values()
            .flat_map(|wt| wt.agents.values())
            .filter(|a| a.status == status)
            .count()
    }

    /// Get all agents as (worktree_id, agent) pairs.
    pub fn all_agents(&self) -> Vec<(&str, &AgentEntry)> {
        self.worktrees
            .iter()
            .flat_map(|(wt_id, wt)| wt.agents.values().map(move |a| (wt_id.as_str(), a)))
            .collect()
    }
}
