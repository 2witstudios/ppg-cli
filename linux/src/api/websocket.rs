use anyhow::Result;
use async_channel::Sender;
use futures_util::{SinkExt, StreamExt};
use log::{error, info, warn};
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio_tungstenite::{connect_async, tungstenite::Message};

use crate::models::manifest::{AgentStatus, Manifest, WorktreeStatus};

/// Events dispatched from the WebSocket to the GTK main thread.
#[derive(Debug, Clone)]
pub enum WsEvent {
    Connected,
    Disconnected,
    ManifestUpdated(Manifest),
    AgentStatusChanged {
        worktree_id: String,
        agent_id: String,
        status: AgentStatus,
        worktree_status: WorktreeStatus,
    },
    TerminalOutput {
        agent_id: String,
        data: String,
    },
    Error(String),
}

/// Inbound server events (JSON).
#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
enum ServerEvent {
    #[serde(rename = "pong")]
    Pong,
    #[serde(rename = "manifest:updated", rename_all = "camelCase")]
    ManifestUpdated { manifest: Manifest },
    #[serde(rename = "agent:status", rename_all = "camelCase")]
    AgentStatus {
        worktree_id: String,
        agent_id: String,
        status: AgentStatus,
        worktree_status: WorktreeStatus,
    },
    #[serde(rename = "terminal:output", rename_all = "camelCase")]
    TerminalOutput { agent_id: String, data: String },
    #[serde(rename = "error")]
    Error { code: String, message: String },
}

/// Outbound client commands (JSON).
#[derive(Debug, Serialize)]
#[serde(tag = "type")]
#[allow(dead_code)]
enum ClientCommand {
    #[serde(rename = "ping")]
    Ping,
    #[serde(rename = "terminal:subscribe", rename_all = "camelCase")]
    TerminalSubscribe { agent_id: String },
    #[serde(rename = "terminal:unsubscribe", rename_all = "camelCase")]
    TerminalUnsubscribe { agent_id: String },
    #[serde(rename = "terminal:input", rename_all = "camelCase")]
    TerminalInput { agent_id: String, data: String },
}

/// Manages WebSocket connection lifecycle with auto-reconnect.
pub struct WsManager {
    running: Arc<AtomicBool>,
}

impl WsManager {
    pub fn new() -> Self {
        Self {
            running: Arc::new(AtomicBool::new(false)),
        }
    }

    /// Start the WebSocket connection loop on the tokio runtime.
    /// Events are dispatched to the GTK main thread via an async_channel Sender.
    pub fn connect(
        &self,
        base_url: &str,
        token: Option<String>,
        tx: Sender<WsEvent>,
        runtime: &tokio::runtime::Handle,
    ) {
        self.running.store(true, Ordering::SeqCst);

        let ws_url = base_url
            .replace("http://", "ws://")
            .replace("https://", "wss://");
        let ws_url = format!("{}/api/events", ws_url.trim_end_matches('/'));
        let running = self.running.clone();

        runtime.spawn(async move {
            let mut backoff_ms: u64 = 1000;
            let max_backoff_ms: u64 = 30_000;

            while running.load(Ordering::SeqCst) {
                info!("WebSocket connecting to {}", ws_url);

                let url = if let Some(ref t) = token {
                    format!("{}?token={}", ws_url, t)
                } else {
                    ws_url.clone()
                };

                match connect_async(&url).await {
                    Ok((ws_stream, _)) => {
                        backoff_ms = 1000; // Reset on success
                        let _ = tx.send(WsEvent::Connected).await;
                        info!("WebSocket connected");

                        let (mut write, mut read) = ws_stream.split();

                        // Ping keepalive every 30s
                        let running_ping = running.clone();
                        let ping_handle = tokio::spawn(async move {
                            let mut interval =
                                tokio::time::interval(std::time::Duration::from_secs(30));
                            loop {
                                interval.tick().await;
                                if !running_ping.load(Ordering::SeqCst) {
                                    break;
                                }
                            }
                        });

                        while let Some(msg) = read.next().await {
                            if !running.load(Ordering::SeqCst) {
                                break;
                            }
                            match msg {
                                Ok(Message::Text(text)) => {
                                    if let Err(e) = handle_message(&text, &tx).await {
                                        warn!("Failed to handle WS message: {}", e);
                                    }
                                }
                                Ok(Message::Ping(data)) => {
                                    let _ = write.send(Message::Pong(data)).await;
                                }
                                Ok(Message::Close(_)) => {
                                    info!("WebSocket closed by server");
                                    break;
                                }
                                Err(e) => {
                                    error!("WebSocket error: {}", e);
                                    break;
                                }
                                _ => {}
                            }
                        }

                        ping_handle.abort();
                        let _ = tx.send(WsEvent::Disconnected).await;
                    }
                    Err(e) => {
                        error!("WebSocket connection failed: {}", e);
                        let _ = tx.send(WsEvent::Error(format!("Connection failed: {}", e))).await;
                    }
                }

                if !running.load(Ordering::SeqCst) {
                    break;
                }

                // Exponential backoff
                info!("Reconnecting in {}ms...", backoff_ms);
                tokio::time::sleep(std::time::Duration::from_millis(backoff_ms)).await;
                backoff_ms = (backoff_ms * 2).min(max_backoff_ms);
            }

            info!("WebSocket connection loop ended");
        });
    }

    pub fn disconnect(&self) {
        self.running.store(false, Ordering::SeqCst);
    }

    #[allow(dead_code)]
    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::SeqCst)
    }
}

async fn handle_message(text: &str, tx: &Sender<WsEvent>) -> Result<()> {
    let event: ServerEvent = serde_json::from_str(text)?;
    match event {
        ServerEvent::Pong => { /* Keepalive ACK */ }
        ServerEvent::ManifestUpdated { manifest } => {
            let _ = tx.send(WsEvent::ManifestUpdated(manifest)).await;
        }
        ServerEvent::AgentStatus {
            worktree_id,
            agent_id,
            status,
            worktree_status,
        } => {
            let _ = tx.send(WsEvent::AgentStatusChanged {
                worktree_id,
                agent_id,
                status,
                worktree_status,
            }).await;
        }
        ServerEvent::TerminalOutput { agent_id, data } => {
            let _ = tx.send(WsEvent::TerminalOutput { agent_id, data }).await;
        }
        ServerEvent::Error { code, message } => {
            let _ = tx.send(WsEvent::Error(format!("{}: {}", code, message))).await;
        }
    }
    Ok(())
}
