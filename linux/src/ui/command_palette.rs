use gtk4::prelude::*;
use gtk4::{self as gtk};
use libadwaita as adw;
use libadwaita::prelude::*;

use crate::api::client::SpawnRequest;
use crate::models::agent_variant::{self, AgentVariant, VariantKind};
use crate::state::Services;

/// Command palette overlay (Ctrl+Shift+P) for spawning agents.
///
/// Phase 1: Pick an agent variant
/// Phase 2: Enter a prompt
#[derive(Clone)]
pub struct CommandPalette {
    dialog: adw::Dialog,
    #[allow(dead_code)]
    services: Services,
}

impl CommandPalette {
    pub fn new(services: Services) -> Self {
        let dialog = adw::Dialog::new();
        dialog.set_title("Command Palette");
        dialog.set_content_width(500);
        dialog.set_content_height(400);

        let content = gtk::Box::new(gtk::Orientation::Vertical, 0);

        // Phase 1: Variant selection
        let search_entry = gtk::SearchEntry::new();
        search_entry.set_placeholder_text(Some("Search agent types..."));
        search_entry.set_margin_top(12);
        search_entry.set_margin_start(12);
        search_entry.set_margin_end(12);
        content.append(&search_entry);

        let variant_list = gtk::ListBox::new();
        variant_list.set_selection_mode(gtk::SelectionMode::Single);
        variant_list.add_css_class("boxed-list");
        variant_list.set_margin_top(8);
        variant_list.set_margin_start(12);
        variant_list.set_margin_end(12);

        for variant in agent_variant::all_variants() {
            let row = create_variant_row(variant);
            variant_list.append(&row);
        }

        let variant_scroll = gtk::ScrolledWindow::new();
        variant_scroll.set_vexpand(true);
        variant_scroll.set_child(Some(&variant_list));
        content.append(&variant_scroll);

        // Phase 2: Prompt input (hidden initially)
        let prompt_box = gtk::Box::new(gtk::Orientation::Vertical, 8);
        prompt_box.set_margin_top(12);
        prompt_box.set_margin_start(12);
        prompt_box.set_margin_end(12);
        prompt_box.set_margin_bottom(12);
        prompt_box.set_visible(false);

        let selected_label = gtk::Label::new(None);
        selected_label.add_css_class("title-4");
        selected_label.set_halign(gtk::Align::Start);
        prompt_box.append(&selected_label);

        let text_scroll = gtk::ScrolledWindow::new();
        text_scroll.set_vexpand(true);
        text_scroll.set_min_content_height(120);

        let text_view = gtk::TextView::new();
        text_view.set_wrap_mode(gtk::WrapMode::WordChar);
        text_view.set_top_margin(8);
        text_view.set_bottom_margin(8);
        text_view.set_left_margin(8);
        text_view.set_right_margin(8);
        text_view.add_css_class("monospace");

        // Key controller for Enter to submit (Shift+Enter for newline)
        let spawn_trigger = std::rc::Rc::new(std::cell::Cell::new(false));
        let spawn_trigger_key = spawn_trigger.clone();
        let key_controller = gtk::EventControllerKey::new();
        key_controller.connect_key_pressed(move |_, keyval, _keycode, modifiers| {
            if keyval == gtk4::gdk::Key::Return
                && !modifiers.contains(gtk4::gdk::ModifierType::SHIFT_MASK)
            {
                spawn_trigger_key.set(true);
                return gtk4::glib::Propagation::Stop;
            }
            gtk4::glib::Propagation::Proceed
        });
        text_view.add_controller(key_controller);

        text_scroll.set_child(Some(&text_view));
        prompt_box.append(&text_scroll);

        let button_row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        button_row.set_halign(gtk::Align::End);

        let back_button = gtk::Button::with_label("Back");
        let spawn_button = gtk::Button::with_label("Spawn");
        spawn_button.add_css_class("suggested-action");

        button_row.append(&back_button);
        button_row.append(&spawn_button);
        prompt_box.append(&button_row);

        content.append(&prompt_box);
        dialog.set_child(Some(&content));

        // -- Filtering --
        let variant_list_filter = variant_list.clone();
        search_entry.connect_search_changed(move |entry| {
            let query = entry.text().to_lowercase();
            let mut idx = 0;
            while let Some(row) = variant_list_filter.row_at_index(idx) {
                let name = row.widget_name();
                let visible = query.is_empty() || name.as_str().contains(&query);
                row.set_visible(visible);
                idx += 1;
            }
        });

        // -- Phase transitions --
        let prompt_box_ref = prompt_box.clone();
        let variant_scroll_ref = variant_scroll.clone();
        let search_ref = search_entry.clone();
        let selected_label_ref = selected_label.clone();
        let text_view_ref = text_view.clone();

        let selected_variant_id = std::rc::Rc::new(std::cell::RefCell::new(String::new()));
        let selected_id_activate = selected_variant_id.clone();

        variant_list.connect_row_activated(move |_, row| {
            let variant_id = row.widget_name().to_string();
            *selected_id_activate.borrow_mut() = variant_id.clone();

            let display = agent_variant::all_variants()
                .iter()
                .find(|v| v.id == variant_id)
                .map(|v| v.display_name)
                .unwrap_or("Agent");

            selected_label_ref.set_text(&format!("Spawn {} Agent", display));

            variant_scroll_ref.set_visible(false);
            search_ref.set_visible(false);
            prompt_box_ref.set_visible(true);
            text_view_ref.grab_focus();
        });

        // Back button
        let prompt_box_back = prompt_box.clone();
        let variant_scroll_back = variant_scroll.clone();
        let search_back = search_entry.clone();
        back_button.connect_clicked(move |_| {
            prompt_box_back.set_visible(false);
            variant_scroll_back.set_visible(true);
            search_back.set_visible(true);
            search_back.grab_focus();
        });

        // Spawn button
        let services_spawn = services.clone();
        let dialog_ref = dialog.clone();
        let selected_id_spawn = selected_variant_id.clone();
        let text_view_spawn = text_view.clone();
        let do_spawn = std::rc::Rc::new(move || {
            let variant_id = selected_id_spawn.borrow().clone();
            let buffer = text_view_spawn.buffer();
            let prompt = buffer
                .text(&buffer.start_iter(), &buffer.end_iter(), false)
                .to_string();

            if prompt.trim().is_empty() && variant_id != "terminal" {
                return;
            }

            let client = services_spawn.client.clone();
            let variant = variant_id.clone();
            let prompt_text = prompt.clone();
            services_spawn.runtime.spawn(async move {
                let req = SpawnRequest {
                    name: variant.clone(),
                    agent: Some(variant),
                    prompt: if prompt_text.is_empty() {
                        None
                    } else {
                        Some(prompt_text)
                    },
                    count: None,
                };
                match client.read().unwrap().spawn(&req).await {
                    Ok(resp) => {
                        log::info!("Spawned: {} in {}", resp.name, resp.worktree_id);
                    }
                    Err(e) => {
                        log::error!("Spawn failed: {}", e);
                    }
                }
            });

            dialog_ref.close();
        });

        let do_spawn_btn = do_spawn.clone();
        spawn_button.connect_clicked(move |_| {
            do_spawn_btn();
        });

        // Check the Enter key trigger on idle
        let do_spawn_key = do_spawn.clone();
        let spawn_trigger_check = spawn_trigger.clone();
        glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
            if spawn_trigger_check.get() {
                spawn_trigger_check.set(false);
                do_spawn_key();
                return glib::ControlFlow::Break;
            }
            glib::ControlFlow::Continue
        });

        Self { dialog, services }
    }

    pub fn present(&self, parent: &adw::ApplicationWindow) {
        self.dialog.present(Some(parent));
    }
}

fn create_variant_row(variant: &AgentVariant) -> gtk::ListBoxRow {
    let row = gtk::ListBoxRow::new();
    row.set_widget_name(variant.id);

    let hbox = gtk::Box::new(gtk::Orientation::Horizontal, 12);
    hbox.set_margin_top(8);
    hbox.set_margin_bottom(8);
    hbox.set_margin_start(12);
    hbox.set_margin_end(12);

    let icon = gtk::Image::from_icon_name(variant.icon_name);
    icon.set_pixel_size(24);

    let vbox = gtk::Box::new(gtk::Orientation::Vertical, 2);
    vbox.set_hexpand(true);

    let name_label = gtk::Label::new(Some(variant.display_name));
    name_label.set_halign(gtk::Align::Start);
    name_label.add_css_class("heading");

    let subtitle_label = gtk::Label::new(Some(variant.subtitle));
    subtitle_label.set_halign(gtk::Align::Start);
    subtitle_label.add_css_class("caption");
    subtitle_label.add_css_class("dim-label");

    vbox.append(&name_label);
    vbox.append(&subtitle_label);

    let kind_label = gtk::Label::new(Some(match variant.kind {
        VariantKind::Agent => "Agent",
        VariantKind::Terminal => "Terminal",
        VariantKind::Worktree => "Worktree",
    }));
    kind_label.add_css_class("caption");
    kind_label.add_css_class("dim-label");

    hbox.append(&icon);
    hbox.append(&vbox);
    hbox.append(&kind_label);
    row.set_child(Some(&hbox));

    row
}
