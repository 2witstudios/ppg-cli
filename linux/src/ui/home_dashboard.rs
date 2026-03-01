use cairo;
use gtk4::prelude::*;
use gtk4::{self as gtk};

use crate::models::manifest::{AgentStatus, Manifest};
use crate::state::Services;

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

/// Home dashboard view with stats, commit heatmap, and recent commits.
#[derive(Clone)]
pub struct HomeDashboard {
    container: gtk::Box,
    stats_running: gtk::Label,
    stats_completed: gtk::Label,
    stats_failed: gtk::Label,
    stats_total: gtk::Label,
    worktree_count: gtk::Label,
    project_label: gtk::Label,
    heatmap_area: gtk::DrawingArea,
    commits_list: gtk::ListBox,
    heatmap_data: Rc<RefCell<Vec<u32>>>,
    services: Services,
}

impl HomeDashboard {
    pub fn new(services: Services) -> Self {
        let container = gtk::Box::new(gtk::Orientation::Vertical, 16);
        container.set_margin_top(24);
        container.set_margin_bottom(24);
        container.set_margin_start(24);
        container.set_margin_end(24);

        // -- Header --
        let header_label = gtk::Label::new(Some("Dashboard"));
        header_label.add_css_class("title-1");
        header_label.set_halign(gtk::Align::Start);
        container.append(&header_label);

        let project_label = gtk::Label::new(Some("No project connected"));
        project_label.add_css_class("dim-label");
        project_label.set_halign(gtk::Align::Start);
        container.append(&project_label);

        // -- Stats cards row --
        let stats_row = gtk::Box::new(gtk::Orientation::Horizontal, 12);
        stats_row.set_homogeneous(true);

        let (running_card, stats_running) = create_stat_card("Running", "0", "status-running");
        let (completed_card, stats_completed) = create_stat_card("Completed", "0", "status-exited");
        let (failed_card, stats_failed) = create_stat_card("Failed", "0", "status-failed");
        let (killed_card, stats_total) = create_stat_card("Killed", "0", "status-gone");

        stats_row.append(&running_card);
        stats_row.append(&completed_card);
        stats_row.append(&failed_card);
        stats_row.append(&killed_card);
        container.append(&stats_row);

        // Worktree count
        let worktree_count = gtk::Label::new(Some("0 worktrees"));
        worktree_count.add_css_class("caption");
        worktree_count.add_css_class("dim-label");
        worktree_count.set_halign(gtk::Align::Start);
        container.append(&worktree_count);

        // -- Commit heatmap --
        let heatmap_label = gtk::Label::new(Some("Commit Activity (90 days)"));
        heatmap_label.add_css_class("title-4");
        heatmap_label.set_halign(gtk::Align::Start);
        heatmap_label.set_margin_top(16);
        container.append(&heatmap_label);

        let heatmap_data: Rc<RefCell<Vec<u32>>> = Rc::new(RefCell::new(vec![0; 91]));

        let heatmap_area = gtk::DrawingArea::new();
        heatmap_area.set_content_width(13 * 16 + 12 * 2); // 13 cols, 16px each, 2px gap
        heatmap_area.set_content_height(7 * 16 + 6 * 2); // 7 rows, 16px each, 2px gap

        let data_ref = heatmap_data.clone();
        heatmap_area.set_draw_func(move |_area, cr, width, height| {
            draw_heatmap(cr, width, height, &data_ref.borrow());
        });
        container.append(&heatmap_area);

        // -- Recent commits --
        let commits_label = gtk::Label::new(Some("Recent Commits"));
        commits_label.add_css_class("title-4");
        commits_label.set_halign(gtk::Align::Start);
        commits_label.set_margin_top(16);
        container.append(&commits_label);

        let scrolled = gtk::ScrolledWindow::new();
        scrolled.set_max_content_height(200);
        scrolled.set_propagate_natural_height(true);

        let commits_list = gtk::ListBox::new();
        commits_list.set_selection_mode(gtk::SelectionMode::None);
        commits_list.add_css_class("boxed-list");

        commits_list.append(&create_commit_row("—", "Waiting for connection...", ""));

        scrolled.set_child(Some(&commits_list));
        container.append(&scrolled);

        Self {
            container,
            stats_running,
            stats_completed,
            stats_failed,
            stats_total,
            worktree_count,
            project_label,
            heatmap_area,
            commits_list,
            heatmap_data,
            services,
        }
    }

    pub fn widget(&self) -> &gtk::Box {
        &self.container
    }

    /// Update dashboard stats from a new manifest.
    pub fn update_manifest(&self, manifest: &Manifest) {
        let all_agents: Vec<_> = manifest
            .worktrees
            .values()
            .flat_map(|wt| wt.agents.values())
            .collect();

        let running = all_agents.iter().filter(|a| a.status == AgentStatus::Running).count();
        let completed = all_agents
            .iter()
            .filter(|a| a.status == AgentStatus::Exited && a.exit_code == Some(0))
            .count();
        let failed = all_agents
            .iter()
            .filter(|a| a.status == AgentStatus::Exited && a.exit_code != Some(0))
            .count();
        let killed = all_agents.iter().filter(|a| a.status == AgentStatus::Gone).count();

        self.stats_running.set_text(&running.to_string());
        self.stats_completed.set_text(&completed.to_string());
        self.stats_failed.set_text(&failed.to_string());
        self.stats_total.set_text(&killed.to_string());

        self.worktree_count
            .set_text(&format!("{} worktrees", manifest.worktrees.len()));

        self.project_label
            .set_text(&format!("Project: {}", manifest.project_root));

        // Fetch git log data for heatmap and recent commits (async)
        self.fetch_heatmap_data(&manifest.project_root);
        self.fetch_recent_commits(&manifest.project_root);
    }

    fn fetch_recent_commits(&self, project_root: &str) {
        let root = project_root.to_string();
        let commits_list = self.commits_list.clone();

        std::thread::spawn(move || {
            let output = std::process::Command::new("git")
                .args([
                    "log",
                    "--format=%h|%s|%ar",
                    "-n",
                    "10",
                ])
                .current_dir(&root)
                .output();

            if let Ok(output) = output {
                let stdout = String::from_utf8_lossy(&output.stdout);
                let commits: Vec<(String, String, String)> = stdout
                    .lines()
                    .filter_map(|line| {
                        let parts: Vec<&str> = line.splitn(3, '|').collect();
                        if parts.len() == 3 {
                            Some((
                                parts[0].to_string(),
                                parts[1].to_string(),
                                parts[2].to_string(),
                            ))
                        } else {
                            None
                        }
                    })
                    .collect();

                glib::idle_add_once(move || {
                    // Clear existing rows
                    while let Some(row) = commits_list.row_at_index(0) {
                        commits_list.remove(&row);
                    }

                    if commits.is_empty() {
                        commits_list.append(&create_commit_row("—", "No commits found", ""));
                    } else {
                        for (hash, message, time) in &commits {
                            commits_list.append(&create_commit_row(hash, message, time));
                        }
                    }
                });
            }
        });
    }

    fn fetch_heatmap_data(&self, project_root: &str) {
        let root = project_root.to_string();
        let data_ref = self.heatmap_data.clone();
        let area_ref = self.heatmap_area.clone();

        // Run git log in background
        std::thread::spawn(move || {
            let output = std::process::Command::new("git")
                .args(["log", "--format=%aI", "--since=90 days ago"])
                .current_dir(&root)
                .output();

            if let Ok(output) = output {
                let stdout = String::from_utf8_lossy(&output.stdout);
                let mut day_counts: HashMap<String, u32> = HashMap::new();

                for line in stdout.lines() {
                    if let Some(date) = line.split('T').next() {
                        *day_counts.entry(date.to_string()).or_insert(0) += 1;
                    }
                }

                // Convert to 91-day array (today at the end)
                let today = chrono::Local::now().date_naive();
                let mut counts = vec![0u32; 91];
                for i in 0..91 {
                    let date = today - chrono::Duration::days(90 - i as i64);
                    let key = date.format("%Y-%m-%d").to_string();
                    counts[i] = day_counts.get(&key).copied().unwrap_or(0);
                }

                glib::idle_add_once(move || {
                    *data_ref.borrow_mut() = counts;
                    area_ref.queue_draw();
                });
            }
        });
    }
}

fn create_stat_card(title: &str, value: &str, value_class: &str) -> (gtk::Frame, gtk::Label) {
    let frame = gtk::Frame::new(None);
    frame.add_css_class("card");

    let vbox = gtk::Box::new(gtk::Orientation::Vertical, 4);
    vbox.set_margin_top(12);
    vbox.set_margin_bottom(12);
    vbox.set_margin_start(16);
    vbox.set_margin_end(16);
    vbox.set_halign(gtk::Align::Center);

    let value_label = gtk::Label::new(Some(value));
    value_label.add_css_class("title-1");
    value_label.add_css_class(value_class);

    let title_label = gtk::Label::new(Some(title));
    title_label.add_css_class("caption");
    title_label.add_css_class("dim-label");

    vbox.append(&value_label);
    vbox.append(&title_label);
    frame.set_child(Some(&vbox));

    (frame, value_label)
}

fn create_commit_row(hash: &str, message: &str, time: &str) -> gtk::ListBoxRow {
    let row = gtk::ListBoxRow::new();
    let hbox = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    hbox.set_margin_top(6);
    hbox.set_margin_bottom(6);
    hbox.set_margin_start(12);
    hbox.set_margin_end(12);

    let hash_label = gtk::Label::new(Some(hash));
    hash_label.add_css_class("monospace");
    hash_label.add_css_class("caption");

    let msg_label = gtk::Label::new(Some(message));
    msg_label.set_halign(gtk::Align::Start);
    msg_label.set_hexpand(true);
    msg_label.set_ellipsize(pango::EllipsizeMode::End);

    let time_label = gtk::Label::new(Some(time));
    time_label.add_css_class("caption");
    time_label.add_css_class("dim-label");

    hbox.append(&hash_label);
    hbox.append(&msg_label);
    hbox.append(&time_label);
    row.set_child(Some(&hbox));

    row
}

/// Draw the commit heatmap grid (13 columns × 7 rows) using cairo.
fn draw_heatmap(cr: &cairo::Context, _width: i32, _height: i32, data: &[u32]) {
    let cell_size: f64 = 14.0;
    let gap: f64 = 2.0;
    let step = cell_size + gap;

    // Find max for color scaling
    let max_val = data.iter().copied().max().unwrap_or(1).max(1);

    // Colors: 5 levels from no activity to high activity
    let colors = [
        (0.15, 0.15, 0.18), // empty / no commits (dark gray)
        (0.12, 0.30, 0.17), // level 1
        (0.15, 0.50, 0.25), // level 2
        (0.18, 0.70, 0.35), // level 3
        (0.20, 0.83, 0.40), // level 4 (brightest green)
    ];

    // Data is 91 days, laid out in 13 columns × 7 rows (column-major, week-aligned)
    for day_idx in 0..data.len().min(91) {
        let col = day_idx / 7;
        let row = day_idx % 7;

        let x = col as f64 * step;
        let y = row as f64 * step;

        let count = data[day_idx];
        let level = if count == 0 {
            0
        } else {
            let ratio = count as f64 / max_val as f64;
            if ratio <= 0.25 {
                1
            } else if ratio <= 0.50 {
                2
            } else if ratio <= 0.75 {
                3
            } else {
                4
            }
        };

        let (r, g, b) = colors[level];
        cr.set_source_rgb(r, g, b);

        // Rounded rectangle
        let radius = 2.0;
        cr.new_sub_path();
        cr.arc(
            x + cell_size - radius,
            y + radius,
            radius,
            -std::f64::consts::FRAC_PI_2,
            0.0,
        );
        cr.arc(
            x + cell_size - radius,
            y + cell_size - radius,
            radius,
            0.0,
            std::f64::consts::FRAC_PI_2,
        );
        cr.arc(
            x + radius,
            y + cell_size - radius,
            radius,
            std::f64::consts::FRAC_PI_2,
            std::f64::consts::PI,
        );
        cr.arc(
            x + radius,
            y + radius,
            radius,
            std::f64::consts::PI,
            3.0 * std::f64::consts::FRAC_PI_2,
        );
        cr.close_path();
        let _ = cr.fill();
    }
}
