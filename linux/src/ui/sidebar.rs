use gtk4::prelude::*;
use gtk4::{self as gtk};

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
                let wt_row = create_worktree_row(wt);
                self.list_box.append(&wt_row);

                // Agent children
                let mut agents: Vec<_> = wt.agents.values().collect();
                agents.sort_by(|a, b| a.started_at.cmp(&b.started_at));

                for agent in agents {
                    let agent_row = create_agent_row(&wt.id, agent);
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

fn create_worktree_row(wt: &WorktreeEntry) -> gtk::ListBoxRow {
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

    row
}

fn create_agent_row(worktree_id: &str, agent: &AgentEntry) -> gtk::ListBoxRow {
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
    row.set_widget_name(&format!("ag:{}:{}", worktree_id, agent.id));

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
