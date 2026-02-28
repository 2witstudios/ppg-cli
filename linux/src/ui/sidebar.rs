use gtk4::prelude::*;
use gtk4::{self as gtk, gio};

use crate::api::client::RestartRequest;
use crate::models::manifest::{AgentEntry, AgentStatus, Manifest, WorktreeEntry};
use crate::state::Services;
use crate::ui::window::SidebarSelection;

use std::cell::RefCell;
use std::rc::Rc;

/// Sidebar with project > worktree > agent hierarchy.
#[derive(Clone)]
pub struct SidebarView {
    container: gtk::Box,
    list_box: gtk::ListBox,
    services: Services,
    on_selection: Rc<RefCell<Option<Box<dyn Fn(SidebarSelection)>>>>,
}

impl SidebarView {
    pub fn new(services: Services) -> Self {
        let container = gtk::Box::new(gtk::Orientation::Vertical, 0);
        container.add_css_class("sidebar");

        // Sidebar header
        let header_box = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        header_box.set_margin_top(12);
        header_box.set_margin_bottom(8);
        header_box.set_margin_start(12);
        header_box.set_margin_end(12);
        let title = gtk::Label::new(Some("PPG"));
        title.add_css_class("title-3");
        title.set_halign(gtk::Align::Start);
        header_box.append(&title);
        container.append(&header_box);

        let scrolled = gtk::ScrolledWindow::new();
        scrolled.set_vexpand(true);
        scrolled.set_policy(gtk::PolicyType::Never, gtk::PolicyType::Automatic);

        let list_box = gtk::ListBox::new();
        list_box.set_selection_mode(gtk::SelectionMode::Single);
        list_box.add_css_class("navigation-sidebar");
        scrolled.set_child(Some(&list_box));
        container.append(&scrolled);

        // Add "Dashboard" row at the top
        let dashboard_row = create_section_row("Dashboard", "go-home-symbolic");
        list_box.append(&dashboard_row);

        let on_selection: Rc<RefCell<Option<Box<dyn Fn(SidebarSelection)>>>> =
            Rc::new(RefCell::new(None));

        let on_sel_ref = on_selection.clone();
        list_box.connect_row_activated(move |_, row| {
            if let Some(ref cb) = *on_sel_ref.borrow() {
                let selection = row_to_selection(row);
                cb(selection);
            }
        });

        Self {
            container,
            list_box,
            services,
            on_selection,
        }
    }

    pub fn widget(&self) -> &gtk::Box {
        &self.container
    }

    pub fn connect_selection_changed<F: Fn(SidebarSelection) + 'static>(&self, f: F) {
        *self.on_selection.borrow_mut() = Some(Box::new(f));
    }

    /// Rebuild the sidebar from a new manifest.
    pub fn update_manifest(&self, manifest: &Manifest) {
        // Remove all rows except the Dashboard row (index 0)
        while let Some(row) = self.list_box.row_at_index(1) {
            self.list_box.remove(&row);
        }

        // Section: Worktrees
        if !manifest.worktrees.is_empty() {
            let section = create_section_header("Worktrees");
            self.list_box.append(&section);

            let mut worktrees: Vec<_> = manifest.worktrees.values().collect();
            worktrees.sort_by(|a, b| a.created_at.cmp(&b.created_at));

            for wt in worktrees {
                let wt_row = create_worktree_row(wt, &self.services);
                self.list_box.append(&wt_row);

                // Agent children
                let mut agents: Vec<_> = wt.agents.values().collect();
                agents.sort_by(|a, b| a.started_at.cmp(&b.started_at));

                for agent in agents {
                    let agent_row = create_agent_row(&wt.id, agent, &self.services);
                    self.list_box.append(&agent_row);
                }
            }
        }
    }

    /// Update a single agent's status badge without full rebuild.
    pub fn update_agent_status(
        &self,
        _worktree_id: &str,
        _agent_id: &str,
        _status: AgentStatus,
    ) {
        // For simplicity, trigger a full manifest refresh from state.
        // A production app would do targeted updates.
        if let Some(manifest) = self.services.state.manifest() {
            self.update_manifest(&manifest);
        }
    }
}

fn create_section_row(label: &str, icon_name: &str) -> gtk::ListBoxRow {
    let row = gtk::ListBoxRow::new();
    let hbox = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    hbox.set_margin_top(4);
    hbox.set_margin_bottom(4);
    hbox.set_margin_start(8);
    hbox.set_margin_end(8);

    let icon = gtk::Image::from_icon_name(icon_name);
    let label_widget = gtk::Label::new(Some(label));
    label_widget.set_halign(gtk::Align::Start);
    label_widget.set_hexpand(true);

    hbox.append(&icon);
    hbox.append(&label_widget);
    row.set_child(Some(&hbox));

    // Store selection data
    row.set_widget_name("dashboard");

    row
}

fn create_section_header(title: &str) -> gtk::ListBoxRow {
    let row = gtk::ListBoxRow::new();
    row.set_selectable(false);
    row.set_activatable(false);

    let label = gtk::Label::new(Some(title));
    label.add_css_class("caption");
    label.add_css_class("dim-label");
    label.set_halign(gtk::Align::Start);
    label.set_margin_top(12);
    label.set_margin_bottom(4);
    label.set_margin_start(12);

    row.set_child(Some(&label));
    row
}

fn create_worktree_row(wt: &WorktreeEntry, services: &Services) -> gtk::ListBoxRow {
    let row = gtk::ListBoxRow::new();
    let hbox = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    hbox.set_margin_top(4);
    hbox.set_margin_bottom(4);
    hbox.set_margin_start(12);
    hbox.set_margin_end(8);

    // Status dot
    let dot = gtk::Label::new(Some("\u{25CF}")); // ●
    dot.add_css_class(wt.status.css_class());

    let name_label = gtk::Label::new(Some(&wt.name));
    name_label.set_halign(gtk::Align::Start);
    name_label.set_hexpand(true);

    // Agent count badge
    let count = wt.agents.len();
    let badge = gtk::Label::new(Some(&count.to_string()));
    badge.add_css_class("caption");
    badge.add_css_class("dim-label");

    hbox.append(&dot);
    hbox.append(&name_label);
    hbox.append(&badge);
    row.set_child(Some(&hbox));

    // Store worktree ID for selection
    row.set_widget_name(&format!("wt:{}", wt.id));

    // -- Context menu (right-click) --
    let wt_id = wt.id.clone();
    let services_ctx = services.clone();

    let menu = gio::Menu::new();
    menu.append(Some("Kill Worktree"), Some(&format!("wt.kill.{}", wt_id)));
    menu.append(Some("Merge Worktree"), Some(&format!("wt.merge.{}", wt_id)));

    let popover = gtk::PopoverMenu::from_model(Some(&menu));
    popover.set_parent(&hbox);
    popover.set_has_arrow(false);

    // Register actions on the row
    let action_group = gio::SimpleActionGroup::new();

    let kill_action = gio::SimpleAction::new(&format!("kill.{}", wt_id), None);
    let services_kill = services_ctx.clone();
    let wt_id_kill = wt_id.clone();
    kill_action.connect_activate(move |_, _| {
        let client = services_kill.client.clone();
        let id = wt_id_kill.clone();
        let toast_tx = services_kill.toast_tx.clone();
        services_kill.runtime.spawn(async move {
            match client.read().unwrap().kill_worktree(&id).await {
                Ok(_) => {
                    let _ = toast_tx.send(crate::state::ToastMessage {
                        text: format!("Killed worktree {}", id),
                        is_error: false,
                    }).await;
                }
                Err(e) => {
                    let _ = toast_tx.send(crate::state::ToastMessage {
                        text: format!("Kill failed: {}", e),
                        is_error: true,
                    }).await;
                }
            }
        });
    });
    action_group.add_action(&kill_action);

    let merge_action = gio::SimpleAction::new(&format!("merge.{}", wt_id), None);
    let services_merge = services_ctx.clone();
    let wt_id_merge = wt_id.clone();
    merge_action.connect_activate(move |_, _| {
        let client = services_merge.client.clone();
        let id = wt_id_merge.clone();
        let toast_tx = services_merge.toast_tx.clone();
        services_merge.runtime.spawn(async move {
            let req = crate::api::client::MergeRequest {
                strategy: Some("squash".to_string()),
                cleanup: Some(true),
                force: None,
            };
            match client.read().unwrap().merge_worktree(&id, &req).await {
                Ok(_) => {
                    let _ = toast_tx.send(crate::state::ToastMessage {
                        text: format!("Merged worktree {}", id),
                        is_error: false,
                    }).await;
                }
                Err(e) => {
                    let _ = toast_tx.send(crate::state::ToastMessage {
                        text: format!("Merge failed: {}", e),
                        is_error: true,
                    }).await;
                }
            }
        });
    });
    action_group.add_action(&merge_action);

    row.insert_action_group("wt", Some(&action_group));

    // Right-click gesture
    let gesture = gtk::GestureClick::new();
    gesture.set_button(3); // Right mouse button
    let popover_ref = popover.clone();
    gesture.connect_released(move |gesture, _, x, y| {
        gesture.set_state(gtk::EventSequenceState::Claimed);
        popover_ref.set_pointing_to(Some(&gtk4::gdk::Rectangle::new(x as i32, y as i32, 1, 1)));
        popover_ref.popup();
    });
    hbox.add_controller(gesture);

    row
}

fn create_agent_row(worktree_id: &str, agent: &AgentEntry, services: &Services) -> gtk::ListBoxRow {
    let row = gtk::ListBoxRow::new();
    let hbox = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    hbox.set_margin_top(2);
    hbox.set_margin_bottom(2);
    hbox.set_margin_start(32); // Indented under worktree
    hbox.set_margin_end(8);

    // Status dot (smaller)
    let dot = gtk::Label::new(Some("\u{2022}")); // •
    dot.add_css_class(agent.status.css_class());

    let type_label = gtk::Label::new(Some(&agent.agent_type));
    type_label.add_css_class("caption");
    type_label.add_css_class("dim-label");

    let name_label = gtk::Label::new(Some(&agent.name));
    name_label.set_halign(gtk::Align::Start);
    name_label.set_hexpand(true);
    name_label.set_ellipsize(pango::EllipsizeMode::End);

    hbox.append(&dot);
    hbox.append(&type_label);
    hbox.append(&name_label);
    row.set_child(Some(&hbox));

    // Store agent ID for selection
    let agent_id = agent.id.clone();
    row.set_widget_name(&format!("ag:{}:{}", worktree_id, agent_id));

    // -- Context menu (right-click) --
    let menu = gio::Menu::new();
    menu.append(Some("Kill Agent"), Some(&format!("ag.kill.{}", agent_id)));
    menu.append(Some("Restart Agent"), Some(&format!("ag.restart.{}", agent_id)));
    menu.append(Some("View Logs"), Some(&format!("ag.logs.{}", agent_id)));

    let popover = gtk::PopoverMenu::from_model(Some(&menu));
    popover.set_parent(&hbox);
    popover.set_has_arrow(false);

    let action_group = gio::SimpleActionGroup::new();

    // Kill agent
    let kill_action = gio::SimpleAction::new(&format!("kill.{}", agent_id), None);
    let services_kill = services.clone();
    let aid_kill = agent_id.clone();
    kill_action.connect_activate(move |_, _| {
        let client = services_kill.client.clone();
        let id = aid_kill.clone();
        let toast_tx = services_kill.toast_tx.clone();
        services_kill.runtime.spawn(async move {
            match client.read().unwrap().kill_agent(&id).await {
                Ok(_) => {
                    let _ = toast_tx.send(crate::state::ToastMessage {
                        text: format!("Killed agent {}", id),
                        is_error: false,
                    }).await;
                }
                Err(e) => {
                    let _ = toast_tx.send(crate::state::ToastMessage {
                        text: format!("Kill failed: {}", e),
                        is_error: true,
                    }).await;
                }
            }
        });
    });
    action_group.add_action(&kill_action);

    // Restart agent
    let restart_action = gio::SimpleAction::new(&format!("restart.{}", agent_id), None);
    let services_restart = services.clone();
    let aid_restart = agent_id.clone();
    restart_action.connect_activate(move |_, _| {
        let client = services_restart.client.clone();
        let id = aid_restart.clone();
        let toast_tx = services_restart.toast_tx.clone();
        services_restart.runtime.spawn(async move {
            let req = RestartRequest {
                prompt: None,
                agent: None,
            };
            match client.read().unwrap().restart_agent(&id, &req).await {
                Ok(_) => {
                    let _ = toast_tx.send(crate::state::ToastMessage {
                        text: format!("Restarted agent {}", id),
                        is_error: false,
                    }).await;
                }
                Err(e) => {
                    let _ = toast_tx.send(crate::state::ToastMessage {
                        text: format!("Restart failed: {}", e),
                        is_error: true,
                    }).await;
                }
            }
        });
    });
    action_group.add_action(&restart_action);

    // View logs (fetch and show in toast for now — full log viewer is future work)
    let logs_action = gio::SimpleAction::new(&format!("logs.{}", agent_id), None);
    let services_logs = services.clone();
    let aid_logs = agent_id.clone();
    logs_action.connect_activate(move |_, _| {
        let client = services_logs.client.clone();
        let id = aid_logs.clone();
        let toast_tx = services_logs.toast_tx.clone();
        services_logs.runtime.spawn(async move {
            match client.read().unwrap().agent_logs(&id, Some(50)).await {
                Ok(resp) => {
                    let line_count = resp.lines.len();
                    let _ = toast_tx.send(crate::state::ToastMessage {
                        text: format!("Fetched {} log lines for {}", line_count, id),
                        is_error: false,
                    }).await;
                    // Log the actual lines for now
                    for line in &resp.lines {
                        log::info!("[{}] {}", id, line);
                    }
                }
                Err(e) => {
                    let _ = toast_tx.send(crate::state::ToastMessage {
                        text: format!("Logs failed: {}", e),
                        is_error: true,
                    }).await;
                }
            }
        });
    });
    action_group.add_action(&logs_action);

    row.insert_action_group("ag", Some(&action_group));

    // Right-click gesture
    let gesture = gtk::GestureClick::new();
    gesture.set_button(3);
    let popover_ref = popover.clone();
    gesture.connect_released(move |gesture, _, x, y| {
        gesture.set_state(gtk::EventSequenceState::Claimed);
        popover_ref.set_pointing_to(Some(&gtk4::gdk::Rectangle::new(x as i32, y as i32, 1, 1)));
        popover_ref.popup();
    });
    hbox.add_controller(gesture);

    row
}

fn row_to_selection(row: &gtk::ListBoxRow) -> SidebarSelection {
    let name = row.widget_name();
    let name_str = name.as_str();

    if name_str == "dashboard" {
        SidebarSelection::Dashboard
    } else if let Some(wt_id) = name_str.strip_prefix("wt:") {
        SidebarSelection::Worktree(wt_id.to_string())
    } else if let Some(rest) = name_str.strip_prefix("ag:") {
        let parts: Vec<&str> = rest.splitn(2, ':').collect();
        if parts.len() == 2 {
            SidebarSelection::Agent(parts[0].to_string(), parts[1].to_string())
        } else {
            SidebarSelection::Dashboard
        }
    } else {
        SidebarSelection::Dashboard
    }
}
