use gtk4::prelude::*;
use gtk4::{self as gtk, gio};
use libadwaita as adw;
use libadwaita::prelude::*;

use crate::models::settings::{AppSettings, Appearance};
use crate::state::Services;
use crate::ui::window::MainWindow;

/// PPG Desktop Application.
pub struct PpgApplication {
    app: adw::Application,
    services: Services,
}

impl PpgApplication {
    pub fn new(server_url: Option<String>, token: Option<String>) -> Self {
        let app = adw::Application::builder()
            .application_id("dev.ppg.desktop")
            .flags(gio::ApplicationFlags::default())
            .build();

        // Load settings, applying CLI overrides
        let mut settings = AppSettings::load();
        if let Some(url) = server_url {
            settings.server_url = url;
        }
        if let Some(t) = token {
            settings.bearer_token = Some(t);
        }

        let services = Services::new(settings);

        Self { app, services }
    }

    pub fn run(&self) -> i32 {
        let services = self.services.clone();

        self.app.connect_startup(move |app| {
            // Apply saved appearance
            let settings = services.state.settings();
            let style_manager = adw::StyleManager::default();
            match settings.appearance {
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

            // Load CSS
            load_css();

            // Register global actions
            let about_action = gio::SimpleAction::new("about", None);
            let app_about = app.clone();
            about_action.connect_activate(move |_, _| {
                let about = adw::AboutDialog::builder()
                    .application_name("PPG Desktop")
                    .application_icon("utilities-terminal-symbolic")
                    .developer_name("2wit Studios")
                    .version("0.1.0")
                    .comments("Native Linux GUI for PPG agent orchestration")
                    .website("https://github.com/2witstudios/ppg-cli")
                    .license_type(gtk::License::MitX11)
                    .build();
                if let Some(win) = app_about.active_window() {
                    about.present(Some(&win));
                }
            });
            app.add_action(&about_action);
        });

        let services_activate = self.services.clone();
        self.app.connect_activate(move |app| {
            let main_window = MainWindow::new(app, services_activate.clone());
            main_window.present();
            main_window.start();
        });

        self.app.run().into()
    }
}

fn load_css() {
    let provider = gtk::CssProvider::new();
    provider.load_from_string(include_str!("style.css"));

    gtk::style_context_add_provider_for_display(
        &gtk4::gdk::Display::default().expect("Could not get default display"),
        &provider,
        gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
    );
}
