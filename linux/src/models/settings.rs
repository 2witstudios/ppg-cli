use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSettings {
    #[serde(default = "default_server_url")]
    pub server_url: String,
    #[serde(default)]
    pub bearer_token: Option<String>,
    #[serde(default = "default_font_family")]
    pub font_family: String,
    #[serde(default = "default_font_size")]
    pub font_size: u32,
    #[serde(default)]
    pub appearance: Appearance,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum Appearance {
    #[default]
    System,
    Dark,
    Light,
}

impl Appearance {
    pub fn label(&self) -> &'static str {
        match self {
            Self::System => "System",
            Self::Dark => "Dark",
            Self::Light => "Light",
        }
    }

    pub fn all() -> &'static [Appearance] {
        &[Self::System, Self::Dark, Self::Light]
    }
}

fn default_server_url() -> String {
    "http://localhost:3000".to_string()
}

fn default_font_family() -> String {
    "Monospace".to_string()
}

fn default_font_size() -> u32 {
    12
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            server_url: default_server_url(),
            bearer_token: None,
            font_family: default_font_family(),
            font_size: default_font_size(),
            appearance: Appearance::default(),
        }
    }
}

impl AppSettings {
    fn config_path() -> PathBuf {
        let config_dir = glib::user_config_dir().join("ppg-desktop");
        config_dir.join("settings.toml")
    }

    pub fn load() -> Self {
        let path = Self::config_path();
        if path.exists() {
            match std::fs::read_to_string(&path) {
                Ok(content) => toml::from_str(&content).unwrap_or_default(),
                Err(_) => Self::default(),
            }
        } else {
            Self::default()
        }
    }

    pub fn save(&self) -> anyhow::Result<()> {
        let path = Self::config_path();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let content = toml::to_string_pretty(self)?;
        std::fs::write(path, content)?;
        Ok(())
    }
}
