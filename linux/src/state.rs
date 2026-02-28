use std::sync::{Arc, RwLock};

use crate::api::client::PpgClient;
use crate::api::websocket::{WsEvent, WsManager};
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
///
/// The `ws_tx` sender is created once and shared. Any code path that needs
/// to reconnect the WebSocket can grab a clone of `ws_tx` and pass it to
/// `WsManager::connect()`. The receiver end is drained by a single
/// `glib::spawn_future_local` loop set up in `MainWindow::connect()`.
#[derive(Clone)]
pub struct Services {
    pub state: AppState,
    pub client: Arc<RwLock<PpgClient>>,
    pub ws: Arc<RwLock<WsManager>>,
    pub runtime: tokio::runtime::Handle,
    /// Persistent sender for WS events. Cloned for each connect() call.
    /// The receiver is drained on the GTK main thread.
    pub ws_tx: async_channel::Sender<WsEvent>,
    /// Receiver stored here so the event loop can be started once.
    ws_rx: Arc<RwLock<Option<async_channel::Receiver<WsEvent>>>>,
    /// Toast message sender — UI components send error/info messages here.
    pub toast_tx: async_channel::Sender<ToastMessage>,
    toast_rx: Arc<RwLock<Option<async_channel::Receiver<ToastMessage>>>>,
}

/// Message for the toast overlay.
#[derive(Debug, Clone)]
pub struct ToastMessage {
    pub text: String,
    pub is_error: bool,
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

        let (ws_tx, ws_rx) = async_channel::unbounded::<WsEvent>();
        let (toast_tx, toast_rx) = async_channel::unbounded::<ToastMessage>();

        Self {
            state: AppState::new(settings),
            client: Arc::new(RwLock::new(client)),
            ws: Arc::new(RwLock::new(WsManager::new())),
            runtime: handle,
            ws_tx,
            ws_rx: Arc::new(RwLock::new(Some(ws_rx))),
            toast_tx,
            toast_rx: Arc::new(RwLock::new(Some(toast_rx))),
        }
    }

    /// Take the WS event receiver. Can only be called once (by the window).
    pub fn take_ws_rx(&self) -> Option<async_channel::Receiver<WsEvent>> {
        self.ws_rx.write().unwrap().take()
    }

    /// Take the toast receiver. Can only be called once (by the window).
    pub fn take_toast_rx(&self) -> Option<async_channel::Receiver<ToastMessage>> {
        self.toast_rx.write().unwrap().take()
    }

    /// Reconnect the WebSocket using the current settings.
    /// The events flow into the same `ws_tx` → GTK event loop.
    pub fn reconnect_ws(&self) {
        let settings = self.state.settings();
        let ws = self.ws.read().unwrap();
        ws.disconnect();
        ws.connect(
            &settings.server_url,
            settings.bearer_token.clone(),
            self.ws_tx.clone(),
            &self.runtime,
        );
    }

    /// Send a toast message to the UI.
    pub fn toast(&self, text: impl Into<String>) {
        let _ = self.toast_tx.try_send(ToastMessage {
            text: text.into(),
            is_error: false,
        });
    }

    /// Send an error toast message to the UI.
    pub fn toast_error(&self, text: impl Into<String>) {
        let _ = self.toast_tx.try_send(ToastMessage {
            text: text.into(),
            is_error: true,
        });
    }
}
