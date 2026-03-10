use gtk4::prelude::*;
use gtk4::{self as gtk};

use crate::state::Services;
use crate::util::shell::command_exists;

/// First-run setup view that checks prerequisites (ppg, tmux).
#[derive(Clone)]
pub struct SetupView {
    container: gtk::Box,
    ppg_status: gtk::Label,
    ppg_icon: gtk::Image,
    tmux_status: gtk::Label,
    tmux_icon: gtk::Image,
    retry_button: gtk::Button,
    continue_button: gtk::Button,
    services: Services,
}

impl SetupView {
    pub fn new(services: Services) -> Self {
        let container = gtk::Box::new(gtk::Orientation::Vertical, 24);
        container.set_halign(gtk::Align::Center);
        container.set_valign(gtk::Align::Center);
        container.set_margin_top(48);
        container.set_margin_bottom(48);
        container.set_margin_start(48);
        container.set_margin_end(48);
        container.set_width_request(400);

        // Header
        let title = gtk::Label::new(Some("PPG Desktop Setup"));
        title.add_css_class("title-1");
        container.append(&title);

        let subtitle = gtk::Label::new(Some("Checking prerequisites..."));
        subtitle.add_css_class("dim-label");
        container.append(&subtitle);

        // Checks list
        let checks_box = gtk::Box::new(gtk::Orientation::Vertical, 12);
        checks_box.set_margin_top(24);

        // ppg check
        let (ppg_row, ppg_icon, ppg_status) = create_check_row("ppg", "PPG CLI tool");
        checks_box.append(&ppg_row);

        // tmux check
        let (tmux_row, tmux_icon, tmux_status) = create_check_row("tmux", "Terminal multiplexer");
        checks_box.append(&tmux_row);

        container.append(&checks_box);

        // Install hints
        let hints_box = gtk::Box::new(gtk::Orientation::Vertical, 4);
        hints_box.set_margin_top(16);

        let ppg_hint = gtk::Label::new(Some("Install ppg: npm install -g ppg-cli"));
        ppg_hint.add_css_class("monospace");
        ppg_hint.add_css_class("caption");
        ppg_hint.set_selectable(true);

        let tmux_hint = gtk::Label::new(Some("Install tmux: sudo apt install tmux"));
        tmux_hint.add_css_class("monospace");
        tmux_hint.add_css_class("caption");
        tmux_hint.set_selectable(true);

        hints_box.append(&ppg_hint);
        hints_box.append(&tmux_hint);
        container.append(&hints_box);

        // Buttons
        let button_box = gtk::Box::new(gtk::Orientation::Horizontal, 12);
        button_box.set_halign(gtk::Align::Center);
        button_box.set_margin_top(24);

        let retry_button = gtk::Button::with_label("Retry");
        let continue_button = gtk::Button::with_label("Continue");
        continue_button.add_css_class("suggested-action");
        continue_button.set_sensitive(false);

        button_box.append(&retry_button);
        button_box.append(&continue_button);
        container.append(&button_box);

        let view = Self {
            container,
            ppg_status,
            ppg_icon,
            tmux_status,
            tmux_icon,
            retry_button: retry_button.clone(),
            continue_button: continue_button.clone(),
            services,
        };

        // Run initial check
        view.check_prerequisites();

        // Retry button
        let view_retry = view.clone();
        retry_button.connect_clicked(move |_| {
            view_retry.check_prerequisites();
        });

        view
    }

    pub fn widget(&self) -> &gtk::Box {
        &self.container
    }

    pub fn check_prerequisites(&self) {
        let ppg_ok = command_exists("ppg");
        let tmux_ok = command_exists("tmux");

        update_check_status(&self.ppg_icon, &self.ppg_status, ppg_ok);
        update_check_status(&self.tmux_icon, &self.tmux_status, tmux_ok);

        self.continue_button.set_sensitive(ppg_ok && tmux_ok);
    }

    pub fn connect_continue<F: Fn() + 'static>(&self, f: F) {
        self.continue_button.connect_clicked(move |_| f());
    }
}

fn create_check_row(name: &str, description: &str) -> (gtk::Box, gtk::Image, gtk::Label) {
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 12);
    row.set_margin_start(8);
    row.set_margin_end(8);

    let icon = gtk::Image::from_icon_name("dialog-question-symbolic");
    icon.set_pixel_size(24);

    let vbox = gtk::Box::new(gtk::Orientation::Vertical, 2);
    vbox.set_hexpand(true);

    let name_label = gtk::Label::new(Some(name));
    name_label.set_halign(gtk::Align::Start);
    name_label.add_css_class("heading");

    let desc_label = gtk::Label::new(Some(description));
    desc_label.set_halign(gtk::Align::Start);
    desc_label.add_css_class("caption");
    desc_label.add_css_class("dim-label");

    vbox.append(&name_label);
    vbox.append(&desc_label);

    let status_label = gtk::Label::new(Some("Checking..."));
    status_label.add_css_class("caption");

    row.append(&icon);
    row.append(&vbox);
    row.append(&status_label);

    (row, icon, status_label)
}

fn update_check_status(icon: &gtk::Image, status: &gtk::Label, found: bool) {
    if found {
        icon.set_icon_name(Some("emblem-ok-symbolic"));
        icon.add_css_class("success");
        status.set_text("Found");
        status.add_css_class("status-running");
        status.remove_css_class("status-failed");
    } else {
        icon.set_icon_name(Some("dialog-error-symbolic"));
        icon.add_css_class("error");
        status.set_text("Not found");
        status.add_css_class("status-failed");
        status.remove_css_class("status-running");
    }
}
