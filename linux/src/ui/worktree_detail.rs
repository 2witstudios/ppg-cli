use gtk4::prelude::*;
use gtk4::{self as gtk};

use crate::api::client::MergeRequest;
use crate::state::Services;

/// Detail panel for a selected worktree.
#[derive(Clone)]
pub struct WorktreeDetail {
    container: gtk::Box,
    name_label: gtk::Label,
    status_label: gtk::Label,
    branch_label: gtk::Label,
    base_label: gtk::Label,
    path_label: gtk::Label,
    created_label: gtk::Label,
    agents_list: gtk::ListBox,
    merge_button: gtk::Button,
    kill_button: gtk::Button,
    services: Services,
    current_id: std::rc::Rc<std::cell::RefCell<Option<String>>>,
}

impl WorktreeDetail {
    pub fn new(services: Services) -> Self {
        let container = gtk::Box::new(gtk::Orientation::Vertical, 16);
        container.set_margin_top(24);
        container.set_margin_bottom(24);
        container.set_margin_start(24);
        container.set_margin_end(24);

        // Header
        let header_box = gtk::Box::new(gtk::Orientation::Horizontal, 12);

        let name_label = gtk::Label::new(Some("Worktree"));
        name_label.add_css_class("title-1");
        name_label.set_halign(gtk::Align::Start);
        name_label.set_hexpand(true);

        let status_label = gtk::Label::new(Some("Unknown"));
        status_label.add_css_class("caption");

        header_box.append(&name_label);
        header_box.append(&status_label);
        container.append(&header_box);

        // Info grid
        let info_grid = gtk::Grid::new();
        info_grid.set_row_spacing(8);
        info_grid.set_column_spacing(16);

        let branch_label = gtk::Label::new(Some("—"));
        let base_label = gtk::Label::new(Some("—"));
        let path_label = gtk::Label::new(Some("—"));
        let created_label = gtk::Label::new(Some("—"));

        add_info_row(&info_grid, 0, "Branch", &branch_label);
        add_info_row(&info_grid, 1, "Base Branch", &base_label);
        add_info_row(&info_grid, 2, "Path", &path_label);
        add_info_row(&info_grid, 3, "Created", &created_label);

        container.append(&info_grid);

        // Agents section
        let agents_header = gtk::Label::new(Some("Agents"));
        agents_header.add_css_class("title-4");
        agents_header.set_halign(gtk::Align::Start);
        agents_header.set_margin_top(16);
        container.append(&agents_header);

        let agents_scroll = gtk::ScrolledWindow::new();
        agents_scroll.set_vexpand(true);
        agents_scroll.set_propagate_natural_height(true);
        agents_scroll.set_max_content_height(300);

        let agents_list = gtk::ListBox::new();
        agents_list.set_selection_mode(gtk::SelectionMode::None);
        agents_list.add_css_class("boxed-list");
        agents_scroll.set_child(Some(&agents_list));
        container.append(&agents_scroll);

        // Action buttons
        let button_box = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        button_box.set_halign(gtk::Align::End);
        button_box.set_margin_top(16);

        let kill_button = gtk::Button::with_label("Kill All Agents");
        kill_button.add_css_class("destructive-action");

        let merge_button = gtk::Button::with_label("Merge");
        merge_button.add_css_class("suggested-action");

        button_box.append(&kill_button);
        button_box.append(&merge_button);
        container.append(&button_box);

        let current_id: std::rc::Rc<std::cell::RefCell<Option<String>>> =
            std::rc::Rc::new(std::cell::RefCell::new(None));

        // Kill button action
        let services_kill = services.clone();
        let id_kill = current_id.clone();
        kill_button.connect_clicked(move |_| {
            if let Some(ref wt_id) = *id_kill.borrow() {
                let client = services_kill.client.clone();
                let id = wt_id.clone();
                services_kill.runtime.spawn(async move {
                    let _ = client.read().unwrap().kill_worktree(&id).await;
                });
            }
        });

        // Merge button action
        let services_merge = services.clone();
        let id_merge = current_id.clone();
        merge_button.connect_clicked(move |_| {
            if let Some(ref wt_id) = *id_merge.borrow() {
                let client = services_merge.client.clone();
                let id = wt_id.clone();
                services_merge.runtime.spawn(async move {
                    let req = MergeRequest {
                        strategy: Some("squash".to_string()),
                        cleanup: Some(true),
                        force: None,
                    };
                    let _ = client.read().unwrap().merge_worktree(&id, &req).await;
                });
            }
        });

        Self {
            container,
            name_label,
            status_label,
            branch_label,
            base_label,
            path_label,
            created_label,
            agents_list,
            merge_button,
            kill_button,
            services,
            current_id,
        }
    }

    pub fn widget(&self) -> &gtk::Box {
        &self.container
    }

    pub fn set_worktree(&self, worktree_id: &str) {
        *self.current_id.borrow_mut() = Some(worktree_id.to_string());

        let manifest = match self.services.state.manifest() {
            Some(m) => m,
            None => return,
        };

        let wt = match manifest.worktrees.get(worktree_id) {
            Some(wt) => wt,
            None => return,
        };

        self.name_label.set_text(&wt.name);

        // Update status with styling
        self.status_label.set_text(wt.status.label());
        for cls in &[
            "status-running",
            "status-idle",
            "status-exited",
            "status-gone",
            "status-failed",
        ] {
            self.status_label.remove_css_class(cls);
        }
        self.status_label.add_css_class(wt.status.css_class());

        self.branch_label.set_text(&wt.branch);
        self.base_label.set_text(&wt.base_branch);
        self.path_label.set_text(&wt.path);
        self.created_label.set_text(&wt.created_at);

        // Rebuild agents list
        while let Some(row) = self.agents_list.row_at_index(0) {
            self.agents_list.remove(&row);
        }

        let mut agents: Vec<_> = wt.agents.values().collect();
        agents.sort_by(|a, b| a.started_at.cmp(&b.started_at));

        for agent in agents {
            let row = create_agent_detail_row(agent);
            self.agents_list.append(&row);
        }
    }
}

fn add_info_row(grid: &gtk::Grid, row: i32, label_text: &str, value: &gtk::Label) {
    let label = gtk::Label::new(Some(label_text));
    label.add_css_class("dim-label");
    label.set_halign(gtk::Align::Start);

    value.set_halign(gtk::Align::Start);
    value.set_selectable(true);
    value.set_hexpand(true);

    grid.attach(&label, 0, row, 1, 1);
    grid.attach(value, 1, row, 1, 1);
}

fn create_agent_detail_row(
    agent: &crate::models::manifest::AgentEntry,
) -> gtk::ListBoxRow {
    let row = gtk::ListBoxRow::new();
    let hbox = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    hbox.set_margin_top(8);
    hbox.set_margin_bottom(8);
    hbox.set_margin_start(12);
    hbox.set_margin_end(12);

    let dot = gtk::Label::new(Some("\u{25CF}"));
    dot.add_css_class(agent.status.css_class());

    let vbox = gtk::Box::new(gtk::Orientation::Vertical, 2);
    vbox.set_hexpand(true);

    let name_label = gtk::Label::new(Some(&agent.name));
    name_label.set_halign(gtk::Align::Start);
    name_label.add_css_class("heading");

    let info_label = gtk::Label::new(Some(&format!(
        "{} — {} — {}",
        agent.agent_type,
        agent.status.label(),
        agent.id
    )));
    info_label.set_halign(gtk::Align::Start);
    info_label.add_css_class("caption");
    info_label.add_css_class("dim-label");

    vbox.append(&name_label);
    vbox.append(&info_label);

    hbox.append(&dot);
    hbox.append(&vbox);
    row.set_child(Some(&hbox));

    row
}
