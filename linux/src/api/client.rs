use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};

use crate::models::manifest::Manifest;

/// REST client for the ppg serve HTTP API.
#[derive(Clone)]
pub struct PpgClient {
    client: Client,
    base_url: String,
    token: Option<String>,
}

// -- Request/Response types --

#[derive(Debug, Serialize)]
pub struct SpawnRequest {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub agent: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub prompt: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub count: Option<u32>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpawnResponse {
    pub worktree_id: String,
    pub name: String,
    pub branch: String,
    pub agents: Vec<SpawnedAgent>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpawnedAgent {
    pub id: String,
    pub tmux_target: String,
    pub session_id: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct SendKeysRequest {
    pub text: String,
    pub mode: SendMode,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum SendMode {
    Raw,
    Literal,
    WithEnter,
}

#[derive(Debug, Serialize)]
pub struct RestartRequest {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub prompt: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub agent: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct MasterRequest {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub agent: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub prompt: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct MergeRequest {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub strategy: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cleanup: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub force: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LogsResponse {
    pub agent_id: String,
    pub lines: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct HealthResponse {
    pub status: String,
}

impl PpgClient {
    pub fn new(base_url: &str, token: Option<String>) -> Self {
        Self {
            client: Client::new(),
            base_url: base_url.trim_end_matches('/').to_string(),
            token,
        }
    }

    pub fn update_connection(&mut self, base_url: &str, token: Option<String>) {
        self.base_url = base_url.trim_end_matches('/').to_string();
        self.token = token;
    }

    fn url(&self, path: &str) -> String {
        format!("{}{}", self.base_url, path)
    }

    fn auth_header(&self) -> Option<String> {
        self.token.as_ref().map(|t| format!("Bearer {}", t))
    }

    async fn get<T: serde::de::DeserializeOwned>(&self, path: &str) -> Result<T> {
        let mut req = self.client.get(self.url(path));
        if let Some(auth) = self.auth_header() {
            req = req.header("Authorization", auth);
        }
        let resp = req.send().await.context("HTTP GET failed")?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("HTTP {} — {}", status, body);
        }
        resp.json().await.context("Failed to parse JSON response")
    }

    async fn post<B: Serialize, T: serde::de::DeserializeOwned>(
        &self,
        path: &str,
        body: &B,
    ) -> Result<T> {
        let mut req = self.client.post(self.url(path)).json(body);
        if let Some(auth) = self.auth_header() {
            req = req.header("Authorization", auth);
        }
        let resp = req.send().await.context("HTTP POST failed")?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("HTTP {} — {}", status, body);
        }
        resp.json().await.context("Failed to parse JSON response")
    }

    async fn post_no_body<T: serde::de::DeserializeOwned>(&self, path: &str) -> Result<T> {
        let mut req = self.client.post(self.url(path));
        if let Some(auth) = self.auth_header() {
            req = req.header("Authorization", auth);
        }
        let resp = req.send().await.context("HTTP POST failed")?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("HTTP {} — {}", status, body);
        }
        resp.json().await.context("Failed to parse JSON response")
    }

    // -- Health --

    pub async fn health(&self) -> Result<HealthResponse> {
        self.get("/health").await
    }

    pub async fn test_connection(&self) -> Result<bool> {
        match self.health().await {
            Ok(h) => Ok(h.status == "ok"),
            Err(_) => Ok(false),
        }
    }

    // -- Status --

    pub async fn status(&self) -> Result<Manifest> {
        self.get("/api/status").await
    }

    pub async fn worktrees(&self) -> Result<serde_json::Value> {
        self.get("/api/worktrees").await
    }

    // -- Spawn --

    pub async fn spawn(&self, req: &SpawnRequest) -> Result<SpawnResponse> {
        self.post("/api/spawn", req).await
    }

    pub async fn spawn_master(&self, req: &MasterRequest) -> Result<SpawnResponse> {
        self.post("/api/agents/master", req).await
    }

    // -- Agent operations --

    pub async fn agent_logs(&self, agent_id: &str, lines: Option<u32>) -> Result<LogsResponse> {
        let path = match lines {
            Some(n) => format!("/api/agents/{}/logs?lines={}", agent_id, n),
            None => format!("/api/agents/{}/logs", agent_id),
        };
        self.get(&path).await
    }

    pub async fn send_keys(&self, agent_id: &str, req: &SendKeysRequest) -> Result<serde_json::Value> {
        self.post(&format!("/api/agents/{}/send", agent_id), req).await
    }

    pub async fn kill_agent(&self, agent_id: &str) -> Result<serde_json::Value> {
        self.post_no_body(&format!("/api/agents/{}/kill", agent_id)).await
    }

    pub async fn restart_agent(&self, agent_id: &str, req: &RestartRequest) -> Result<serde_json::Value> {
        self.post(&format!("/api/agents/{}/restart", agent_id), req).await
    }

    // -- Worktree operations --

    pub async fn merge_worktree(&self, worktree_id: &str, req: &MergeRequest) -> Result<serde_json::Value> {
        self.post(&format!("/api/worktrees/{}/merge", worktree_id), req).await
    }

    pub async fn kill_worktree(&self, worktree_id: &str) -> Result<serde_json::Value> {
        self.post_no_body(&format!("/api/worktrees/{}/kill", worktree_id)).await
    }

    // -- Config --

    pub async fn config(&self) -> Result<serde_json::Value> {
        self.get("/api/config").await
    }

    pub async fn templates(&self) -> Result<serde_json::Value> {
        self.get("/api/templates").await
    }
}
