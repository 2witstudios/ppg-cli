use gtk4::prelude::*;
use gtk4::{self as gtk};

use crate::state::Services;
use crate::util::shell::tmux_attach_shell_command;

/// A terminal pane that embeds a VTE terminal widget.
///
/// Since vte4-rs may not be available as a crate, we use a fallback
/// placeholder. When VTE is available, the `create_vte_terminal` function
/// would return a real terminal widget.
#[derive(Clone)]
pub struct TerminalPane {
    widget: gtk::Widget,
    #[allow(dead_code)]
    services: Services,
}

impl TerminalPane {
    pub fn new(services: Services) -> Self {
        let widget = create_fallback_widget().upcast();

        Self { widget, services }
    }

    pub fn widget(&self) -> &gtk::Widget {
        &self.widget
    }

    /// Attach this terminal to a tmux session/window.
    pub fn attach_to_tmux(&self, session_name: &str, window_target: &str) {
        let _cmd = tmux_attach_shell_command(session_name, window_target);
        // When VTE is available:
        // spawn_in_terminal(&self.widget, &cmd);
    }
}

/// Fallback widget when VTE is not available.
fn create_fallback_widget() -> gtk::Box {
    let container = gtk::Box::new(gtk::Orientation::Vertical, 8);
    container.set_halign(gtk::Align::Center);
    container.set_valign(gtk::Align::Center);

    let icon = gtk::Image::from_icon_name("utilities-terminal-symbolic");
    icon.set_pixel_size(48);
    icon.add_css_class("dim-label");

    let label = gtk::Label::new(Some("Terminal Pane"));
    label.add_css_class("title-3");

    let hint = gtk::Label::new(Some(
        "VTE terminal widget will be embedded here.\n\
         Install libvte-2.91-gtk4-dev and rebuild with VTE support.",
    ));
    hint.add_css_class("dim-label");
    hint.set_justify(gtk::Justification::Center);

    let tmux_hint = gtk::Label::new(Some(
        "The terminal connects to tmux sessions to show live agent output.\n\
         Use 'ppg attach <agent>' in a regular terminal for now.",
    ));
    tmux_hint.add_css_class("caption");
    tmux_hint.add_css_class("dim-label");
    tmux_hint.set_margin_top(8);
    tmux_hint.set_justify(gtk::Justification::Center);

    container.append(&icon);
    container.append(&label);
    container.append(&hint);
    container.append(&tmux_hint);

    container
}
