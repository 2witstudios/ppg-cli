use gtk4::prelude::*;
use gtk4::{self as gtk, gio};
use libadwaita as adw;
use libadwaita::prelude::*;

use crate::api::websocket::WsEvent;
use crate::state::{ConnectionState, Services, ToastMessage};
use crate::ui::command_palette::CommandPalette;
use crate::ui::home_dashboard::HomeDashboard;
use crate::ui::pane_grid::PaneGrid;
use crate::ui::settings_dialog::SettingsDialog;
use crate::ui::setup_view::SetupView;
use crate::ui::sidebar::SidebarView;
use crate::ui::worktree_detail::WorktreeDetail;

/// The main application window using NavigationSplitView.
pub struct MainWindow {
    pub window: adw::ApplicationWindow,
    sidebar: SidebarView,
    stack: gtk::Stack,
    home_dashboard: HomeDashboard,
    pane_grid: PaneGrid,
    worktree_detail: WorktreeDetail,
    setup_view: SetupView,
    status_label: gtk::Label,
    toast_overlay: adw::ToastOverlay,
    services: Services,
}

impl MainWindow {
    pub fn new(app: &adw::Application, services: Services) -> Self {
        let window = adw::ApplicationWindow::builder()
            .application(app)
            .default_width(1280)
            .default_height(800)
            .title("PPG Desktop")
            .build();

        // -- Header bar --
        let header = adw::HeaderBar::new();

        let status_label = gtk::Label::new(Some("Disconnected"));
        status_label.add_css_class("status-gone");
        status_label.add_css_class("caption");
        header.pack_start(&status_label);

        let menu_button = gtk::MenuButton::builder()
            .icon_name("open-menu-symbolic")
            .build();

        let menu = gio::Menu::new();
        menu.append(Some("Settings"), Some("app.settings"));
        menu.append(Some("Reconnect"), Some("app.reconnect"));
        menu.append(Some("About"), Some("app.about"));
        menu_button.set_menu_model(Some(&menu));
        header.pack_end(&menu_button);

        // -- Content stack --
        let stack = gtk::Stack::new();
        stack.set_transition_type(gtk::StackTransitionType::Crossfade);

        let home_dashboard = HomeDashboard::new(services.clone());
        let pane_grid = PaneGrid::new(services.clone());
        let worktree_detail = WorktreeDetail::new(services.clone());
        let setup_view = SetupView::new(services.clone());

        stack.add_named(&home_dashboard.widget(), Some("dashboard"));
        stack.add_named(&pane_grid.widget(), Some("terminal"));
        stack.add_named(&worktree_detail.widget(), Some("worktree"));
        stack.add_named(&setup_view.widget(), Some("setup"));

        // -- Sidebar --
        let sidebar = SidebarView::new(services.clone());

        // When sidebar selection changes, update the content stack
        let stack_ref = stack.clone();
        let pane_grid_ref = pane_grid.clone();
        let worktree_detail_ref = worktree_detail.clone();
        sidebar.connect_selection_changed(move |selection| match selection {
            SidebarSelection::Dashboard => {
                stack_ref.set_visible_child_name("dashboard");
            }
            SidebarSelection::Worktree(wt_id) => {
                worktree_detail_ref.set_worktree(&wt_id);
                stack_ref.set_visible_child_name("worktree");
            }
            SidebarSelection::Agent(wt_id, agent_id) => {
                pane_grid_ref.show_agent(&wt_id, &agent_id);
                stack_ref.set_visible_child_name("terminal");
            }
        });

        // -- Navigation split view --
        let sidebar_page = adw::NavigationPage::builder()
            .title("PPG")
            .child(&sidebar.widget())
            .build();

        // Wrap content in a toast overlay for notifications
        let toast_overlay = adw::ToastOverlay::new();
        let content_box = gtk::Box::new(gtk::Orientation::Vertical, 0);
        content_box.append(&header);
        content_box.append(&stack);
        stack.set_vexpand(true);
        toast_overlay.set_child(Some(&content_box));

        let content_page = adw::NavigationPage::builder()
            .title("Dashboard")
            .child(&toast_overlay)
            .build();

        let split_view = adw::NavigationSplitView::new();
        split_view.set_sidebar(&sidebar_page);
        split_view.set_content(&content_page);

        window.set_content(Some(&split_view));

        // -- Keyboard shortcut: Ctrl+Shift+P -> command palette --
        let palette_action = gio::SimpleAction::new("command-palette", None);
        let services_cp = services.clone();
        let window_ref = window.clone();
        palette_action.connect_activate(move |_, _| {
            let palette = CommandPalette::new(services_cp.clone());
            palette.present(&window_ref);
        });
        window.add_action(&palette_action);

        // Ctrl+Shift+P keybinding
        let shortcut_ctrl = gtk::ShortcutController::new();
        shortcut_ctrl.set_scope(gtk::ShortcutScope::Global);
        let trigger = gtk::ShortcutTrigger::parse_string("<Ctrl><Shift>p").unwrap();
        let action = gtk::ShortcutAction::parse_string("action(app.command-palette)").unwrap();
        let shortcut = gtk::Shortcut::new(Some(trigger), Some(action));
        shortcut_ctrl.add_shortcut(shortcut);
        window.add_controller(shortcut_ctrl);

        // -- Settings action --
        let settings_action = gio::SimpleAction::new("settings", None);
        let services_sa = services.clone();
        let window_ref2 = window.clone();
        settings_action.connect_activate(move |_, _| {
            let dialog = SettingsDialog::new(services_sa.clone());
            dialog.present(&window_ref2);
        });
        app.add_action(&settings_action);

        // -- Reconnect action (uses centralized reconnect_ws) --
        let reconnect_action = gio::SimpleAction::new("reconnect", None);
        let services_ra = services.clone();
        reconnect_action.connect_activate(move |_, _| {
            services_ra.state.set_connection_state(ConnectionState::Connecting);
            services_ra.reconnect_ws();
            services_ra.toast("Reconnecting...");
        });
        app.add_action(&reconnect_action);

        Self {
            window,
            sidebar,
            stack,
            home_dashboard,
            pane_grid,
            worktree_detail,
            setup_view,
            status_label,
            toast_overlay,
            services,
        }
    }

    pub fn present(&self) {
        self.window.present();
    }

    /// Check prerequisites and show setup view or connect immediately.
    /// This should be called once after the window is created.
    pub fn start(&self) {
        use crate::util::shell::command_exists;

        // Wire the setup view's continue button to switch to dashboard and connect
        let stack = self.stack.clone();
        let services_continue = self.services.clone();
        self.setup_view.connect_continue(move || {
            stack.set_visible_child_name("dashboard");
            // Trigger connection when prerequisites are satisfied
            services_continue.reconnect_ws();
        });

        // Check if prerequisites are met
        let ppg_ok = command_exists("ppg");
        let tmux_ok = command_exists("tmux");

        if ppg_ok && tmux_ok {
            // Prerequisites met — go straight to dashboard and connect
            self.stack.set_visible_child_name("dashboard");
            self.connect();
        } else {
            // Show setup view first
            self.stack.set_visible_child_name("setup");
            // Still set up the event loops so they're ready when the user continues
            self.setup_event_loops();
        }
    }

    /// Set up event loops for WS and toast receivers.
    /// Called once — either from connect() or from start() for deferred connect.
    fn setup_event_loops(&self) {
        let services = self.services.clone();
        let status_label = self.status_label.clone();
        let sidebar = self.sidebar.clone();
        let home = self.home_dashboard.clone();

        // Take the persistent WS event receiver from Services.
        if let Some(rx) = services.take_ws_rx() {
            let services_rx = services.clone();
            let sidebar_rx = sidebar.clone();
            let home_rx = home.clone();
            let status_rx = status_label.clone();
            glib::spawn_future_local(async move {
                while let Ok(event) = rx.recv().await {
                    match event {
                        WsEvent::Connected => {
                            services_rx
                                .state
                                .set_connection_state(ConnectionState::Connected);
                            update_status_ui(
                                &status_rx,
                                &services_rx.state.connection_state(),
                            );
                        }
                        WsEvent::Disconnected => {
                            services_rx
                                .state
                                .set_connection_state(ConnectionState::Reconnecting);
                            update_status_ui(
                                &status_rx,
                                &services_rx.state.connection_state(),
                            );
                        }
                        WsEvent::ManifestUpdated(manifest) => {
                            services_rx.state.set_manifest(manifest.clone());
                            sidebar_rx.update_manifest(&manifest);
                            home_rx.update_manifest(&manifest);
                        }
                        WsEvent::AgentStatusChanged {
                            worktree_id,
                            agent_id,
                            status,
                            ..
                        } => {
                            sidebar_rx.update_agent_status(
                                &worktree_id,
                                &agent_id,
                                status,
                            );
                        }
                        WsEvent::TerminalOutput { .. } => {
                            // Terminal output handled by subscribed panes
                        }
                        WsEvent::Error(msg) => {
                            services_rx
                                .state
                                .set_connection_state(ConnectionState::Error(msg));
                            update_status_ui(
                                &status_rx,
                                &services_rx.state.connection_state(),
                            );
                        }
                    }
                }
            });
        }

        // Drain toast messages and show them via the toast overlay.
        if let Some(toast_rx) = services.take_toast_rx() {
            let overlay = self.toast_overlay.clone();
            glib::spawn_future_local(async move {
                while let Ok(msg) = toast_rx.recv().await {
                    let toast = adw::Toast::new(&msg.text);
                    if msg.is_error {
                        toast.set_timeout(5);
                    } else {
                        toast.set_timeout(3);
                    }
                    overlay.add_toast(toast);
                }
            });
        }
    }

    /// Start WebSocket and initial data fetch.
    /// Event loops must already be set up via setup_event_loops() or start().
    pub fn connect(&self) {
        self.setup_event_loops();

        self.services
            .state
            .set_connection_state(ConnectionState::Connecting);
        self.update_status_label();

        let services = self.services.clone();
        let status_label = self.status_label.clone();
        let sidebar = self.sidebar.clone();
        let home = self.home_dashboard.clone();

        // Start WebSocket connection using centralized reconnect_ws.
        // This sends events through the persistent ws_tx → ws_rx pipeline.
        services.reconnect_ws();

        // Initial status fetch via HTTP
        let client = services.client.clone();
        let state = services.state.clone();
        let sidebar_init = sidebar.clone();
        let home_init = home.clone();
        let status_init = status_label.clone();
        let toast_tx = services.toast_tx.clone();
        services.runtime.spawn(async move {
            match client.read().unwrap().status().await {
                Ok(manifest) => {
                    let m = manifest.clone();
                    glib::idle_add_once(move || {
                        state.set_manifest(m.clone());
                        state.set_connection_state(ConnectionState::Connected);
                        sidebar_init.update_manifest(&m);
                        home_init.update_manifest(&m);
                        update_status_ui(&status_init, &ConnectionState::Connected);
                    });
                }
                Err(e) => {
                    let msg = format!("{}", e);
                    let toast_msg = msg.clone();
                    let _ = toast_tx.try_send(ToastMessage {
                        text: format!("Connection failed: {}", toast_msg),
                        is_error: true,
                    });
                    glib::idle_add_once(move || {
                        update_status_ui(&status_init, &ConnectionState::Error(msg));
                    });
                }
            }
        });
    }

    fn update_status_label(&self) {
        let state = self.services.state.connection_state();
        update_status_ui(&self.status_label, &state);
    }
}

fn update_status_ui(label: &gtk::Label, state: &ConnectionState) {
    label.set_text(state.label());
    for cls in &["status-running", "status-idle", "status-gone", "status-failed"] {
        label.remove_css_class(cls);
    }
    label.add_css_class(state.css_class());
}

/// Sidebar selection types.
#[derive(Debug, Clone)]
pub enum SidebarSelection {
    Dashboard,
    Worktree(String),
    Agent(String, String),
}
