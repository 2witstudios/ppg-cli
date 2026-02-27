use std::sync::{Arc, RwLock};

use crate::api::client::PpgClient;
use crate::api::websocket::WsManager;
use crate::models::manifest::Manifest;
use crate::models::settings::AppSettings;

/// Connection lifecycle states.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting,
    Error(String),
}

impl ConnectionState {
    pub fn label(&self) -> &str {
        match self {
            Self::Disconnected => "Disconnected",
            Self::Connecting => "Connecting...",
            Self::Connected => "Connected",
            Self::Reconnecting => "Reconnecting...",
            Self::Error(msg) => msg.as_str(),
        }
    }

    pub fn css_class(&self) -> &str {
        match self {
            Self::Connected => "status-running",
            Self::Connecting | Self::Reconnecting => "status-idle",
            Self::Disconnected => "status-gone",
            Self::Error(_) => "status-failed",
        }
    }
}

/// Shared application state — thread-safe via Arc<RwLock>.
#[derive(Clone)]
pub struct AppState {
    inner: Arc<RwLock<AppStateInner>>,
}

struct AppStateInner {
    pub manifest: Option<Manifest>,
    pub connection: ConnectionState,
    pub settings: AppSettings,
}

impl AppState {
    pub fn new(settings: AppSettings) -> Self {
        Self {
            inner: Arc::new(RwLock::new(AppStateInner {
                manifest: None,
                connection: ConnectionState::Disconnected,
                settings,
            })),
        }
    }

    pub fn manifest(&self) -> Option<Manifest> {
        self.inner.read().unwrap().manifest.clone()
    }

    pub fn set_manifest(&self, manifest: Manifest) {
        self.inner.write().unwrap().manifest = Some(manifest);
    }

    pub fn connection_state(&self) -> ConnectionState {
        self.inner.read().unwrap().connection.clone()
    }

    pub fn set_connection_state(&self, state: ConnectionState) {
        self.inner.write().unwrap().connection = state;
    }

    pub fn settings(&self) -> AppSettings {
        self.inner.read().unwrap().settings.clone()
    }

    pub fn update_settings<F: FnOnce(&mut AppSettings)>(&self, f: F) {
        let mut inner = self.inner.write().unwrap();
        f(&mut inner.settings);
        let _ = inner.settings.save();
    }
}

/// Bundles all shared services for easy passing to UI components.
#[derive(Clone)]
pub struct Services {
    pub state: AppState,
    pub client: Arc<RwLock<PpgClient>>,
    pub ws: Arc<RwLock<WsManager>>,
    pub runtime: tokio::runtime::Handle,
}

impl Services {
    pub fn new(settings: AppSettings) -> Self {
        let client = PpgClient::new(&settings.server_url, settings.bearer_token.clone());
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("Failed to create tokio runtime");
        let handle = runtime.handle().clone();

        // Keep runtime alive by leaking it — it lives for the app's lifetime.
        std::mem::forget(runtime);

        Self {
            state: AppState::new(settings),
            client: Arc::new(RwLock::new(client)),
            ws: Arc::new(RwLock::new(WsManager::new())),
            runtime: handle,
        }
    }
}
