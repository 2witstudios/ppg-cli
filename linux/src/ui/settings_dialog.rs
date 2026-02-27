use gtk4::prelude::*;
use gtk4::{self as gtk};
use libadwaita as adw;
use libadwaita::prelude::*;

use crate::models::settings::Appearance;
use crate::state::Services;

/// Settings dialog using adw::PreferencesWindow.
pub struct SettingsDialog {
    window: adw::PreferencesWindow,
}

impl SettingsDialog {
    pub fn new(services: Services) -> Self {
        let window = adw::PreferencesWindow::new();
        window.set_title("Settings");
        window.set_default_size(600, 500);
        window.set_search_enabled(false);

        let settings = services.state.settings();

        // -- Connection group --
        let connection_group = adw::PreferencesGroup::new();
        connection_group.set_title("Connection");
        connection_group.set_description(Some("PPG server connection settings"));

        let url_row = adw::EntryRow::new();
        url_row.set_title("Server URL");
        url_row.set_text(&settings.server_url);
        connection_group.add(&url_row);

        let token_row = adw::PasswordEntryRow::new();
        token_row.set_title("Bearer Token");
        if let Some(ref token) = settings.bearer_token {
            token_row.set_text(token);
        }
        connection_group.add(&token_row);

        let test_button = gtk::Button::with_label("Test Connection");
        test_button.set_halign(gtk::Align::Start);
        test_button.set_margin_top(8);

        let services_test = services.clone();
        let test_btn_ref = test_button.clone();
        test_button.connect_clicked(move |_| {
            test_btn_ref.set_label("Testing...");
            test_btn_ref.set_sensitive(false);

            let client = services_test.client.clone();
            let btn = test_btn_ref.clone();
            services_test.runtime.spawn(async move {
                let result = client.read().unwrap().test_connection().await;
                let label = match result {
                    Ok(true) => "Connected!",
                    Ok(false) => "Failed",
                    Err(_) => "Error",
                };
                let label_owned = label.to_string();
                glib::idle_add_once(move || {
                    btn.set_label(&label_owned);
                    btn.set_sensitive(true);
                });
            });
        });
        connection_group.add(&test_button);

        let connection_page = adw::PreferencesPage::new();
        connection_page.set_title("Connection");
        connection_page.set_icon_name(Some("network-server-symbolic"));
        connection_page.add(&connection_group);

        // -- Terminal group --
        let terminal_group = adw::PreferencesGroup::new();
        terminal_group.set_title("Terminal");
        terminal_group.set_description(Some("Terminal appearance settings"));

        let font_row = adw::EntryRow::new();
        font_row.set_title("Font Family");
        font_row.set_text(&settings.font_family);
        terminal_group.add(&font_row);

        let size_row = adw::SpinRow::with_range(8.0, 32.0, 1.0);
        size_row.set_title("Font Size");
        size_row.set_value(settings.font_size as f64);
        terminal_group.add(&size_row);

        // -- Appearance group --
        let appearance_group = adw::PreferencesGroup::new();
        appearance_group.set_title("Appearance");

        let appearance_row = adw::ComboRow::new();
        appearance_row.set_title("Color Scheme");
        let model = gtk::StringList::new(&["System", "Dark", "Light"]);
        appearance_row.set_model(Some(&model));
        appearance_row.set_selected(match settings.appearance {
            Appearance::System => 0,
            Appearance::Dark => 1,
            Appearance::Light => 2,
        });
        appearance_group.add(&appearance_row);

        let appearance_page = adw::PreferencesPage::new();
        appearance_page.set_title("Appearance");
        appearance_page.set_icon_name(Some("applications-graphics-symbolic"));
        appearance_page.add(&terminal_group);
        appearance_page.add(&appearance_group);

        window.add(&connection_page);
        window.add(&appearance_page);

        // Save settings on close
        let services_save = services.clone();
        let url_row_ref = url_row.clone();
        let token_row_ref = token_row.clone();
        let font_row_ref = font_row.clone();
        window.connect_close_request(move |_| {
            let url = url_row_ref.text().to_string();
            let token_text = token_row_ref.text().to_string();
            let token = if token_text.is_empty() {
                None
            } else {
                Some(token_text)
            };
            let font = font_row_ref.text().to_string();
            let size = size_row.value() as u32;
            let appearance = match appearance_row.selected() {
                1 => Appearance::Dark,
                2 => Appearance::Light,
                _ => Appearance::System,
            };

            services_save.state.update_settings(|s| {
                s.server_url = url.clone();
                s.bearer_token = token.clone();
                s.font_family = font;
                s.font_size = size;
                s.appearance = appearance;
            });

            // Update client connection
            services_save
                .client
                .write()
                .unwrap()
                .update_connection(&url, token);

            // Apply appearance
            let style_manager = adw::StyleManager::default();
            match appearance {
                Appearance::Dark => {
                    style_manager.set_color_scheme(adw::ColorScheme::ForceDark);
                }
                Appearance::Light => {
                    style_manager.set_color_scheme(adw::ColorScheme::ForceLight);
                }
                Appearance::System => {
                    style_manager.set_color_scheme(adw::ColorScheme::Default);
                }
            }

            glib::Propagation::Proceed
        });

        Self { window }
    }

    pub fn present(&self, parent: &adw::ApplicationWindow) {
        self.window.set_transient_for(Some(parent));
        self.window.present();
    }
}
