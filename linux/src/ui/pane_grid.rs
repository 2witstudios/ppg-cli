use gtk4::prelude::*;
use gtk4::{self as gtk};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use crate::state::Services;
use crate::ui::terminal_pane::TerminalPane;

/// Grid layout for terminal panes (up to 2 columns × 3 rows).
#[derive(Clone)]
pub struct PaneGrid {
    container: gtk::Box,
    grid: gtk::Grid,
    services: Services,
    panes: Rc<RefCell<HashMap<String, TerminalPane>>>,
    empty_state: gtk::Box,
}

impl PaneGrid {
    pub fn new(services: Services) -> Self {
        let container = gtk::Box::new(gtk::Orientation::Vertical, 0);

        // Grid for terminal panes
        let grid = gtk::Grid::new();
        grid.set_row_homogeneous(true);
        grid.set_column_homogeneous(true);
        grid.set_row_spacing(2);
        grid.set_column_spacing(2);
        grid.set_vexpand(true);
        grid.set_hexpand(true);

        // Empty state
        let empty_state = create_empty_state();

        container.append(&empty_state);

        Self {
            container,
            grid,
            services,
            panes: Rc::new(RefCell::new(HashMap::new())),
            empty_state,
        }
    }

    pub fn widget(&self) -> &gtk::Box {
        &self.container
    }

    /// Show a specific agent's terminal.
    pub fn show_agent(&self, worktree_id: &str, agent_id: &str) {
        let key = format!("{}:{}", worktree_id, agent_id);

        // Get manifest to find tmux target
        let manifest = match self.services.state.manifest() {
            Some(m) => m,
            None => return,
        };

        let (session_name, window_target) = {
            let wt = match manifest.worktrees.get(worktree_id) {
                Some(wt) => wt,
                None => return,
            };
            let agent = match wt.agents.get(agent_id) {
                Some(a) => a,
                None => return,
            };
            (manifest.session_name.clone(), wt.tmux_window.clone())
        };

        // Create a pane if it doesn't exist
        let mut panes = self.panes.borrow_mut();
        if !panes.contains_key(&key) {
            let pane = TerminalPane::new(self.services.clone());
            pane.attach_to_tmux(&session_name, &window_target);
            panes.insert(key.clone(), pane);
        }

        // Replace grid contents with the selected pane
        // Remove all children from grid
        while let Some(child) = self.grid.first_child() {
            self.grid.remove(&child);
        }

        if let Some(pane) = panes.get(&key) {
            self.grid.attach(pane.widget(), 0, 0, 1, 1);
        }

        // Switch from empty state to grid
        if self.empty_state.parent().is_some() {
            self.container.remove(&self.empty_state);
        }
        if self.grid.parent().is_none() {
            self.container.append(&self.grid);
        }
    }

    /// Show all agents for a worktree in a grid layout.
    pub fn show_worktree(&self, worktree_id: &str) {
        let manifest = match self.services.state.manifest() {
            Some(m) => m,
            None => return,
        };

        let wt = match manifest.worktrees.get(worktree_id) {
            Some(wt) => wt,
            None => return,
        };

        // Clear grid
        while let Some(child) = self.grid.first_child() {
            self.grid.remove(&child);
        }

        let agents: Vec<_> = wt.agents.values().collect();
        if agents.is_empty() {
            return;
        }

        // Calculate grid dimensions (up to 2 cols × 3 rows)
        let count = agents.len().min(6);
        let cols = if count <= 1 { 1 } else { 2 };

        let mut panes = self.panes.borrow_mut();
        for (i, agent) in agents.iter().take(6).enumerate() {
            let key = format!("{}:{}", worktree_id, agent.id);
            let col = (i % cols) as i32;
            let row = (i / cols) as i32;

            if !panes.contains_key(&key) {
                let pane = TerminalPane::new(self.services.clone());
                pane.attach_to_tmux(&manifest.session_name, &wt.tmux_window);
                panes.insert(key.clone(), pane);
            }

            if let Some(pane) = panes.get(&key) {
                self.grid.attach(pane.widget(), col, row, 1, 1);
            }
        }

        if self.empty_state.parent().is_some() {
            self.container.remove(&self.empty_state);
        }
        if self.grid.parent().is_none() {
            self.container.append(&self.grid);
        }
    }
}

fn create_empty_state() -> gtk::Box {
    let container = gtk::Box::new(gtk::Orientation::Vertical, 12);
    container.set_halign(gtk::Align::Center);
    container.set_valign(gtk::Align::Center);
    container.set_vexpand(true);

    let icon = gtk::Image::from_icon_name("utilities-terminal-symbolic");
    icon.set_pixel_size(64);
    icon.add_css_class("dim-label");

    let label = gtk::Label::new(Some("Select an agent from the sidebar"));
    label.add_css_class("title-3");
    label.add_css_class("dim-label");

    let hint = gtk::Label::new(Some("Terminal panes will appear here"));
    hint.add_css_class("caption");
    hint.add_css_class("dim-label");

    container.append(&icon);
    container.append(&label);
    container.append(&hint);

    container
}
