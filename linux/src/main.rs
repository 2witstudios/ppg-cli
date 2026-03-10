mod api;
mod app;
mod models;
mod state;
mod ui;
mod util;

use app::PpgApplication;

fn main() {
    // Initialize logging
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .format_timestamp_millis()
        .init();

    // Parse CLI arguments
    let args: Vec<String> = std::env::args().collect();
    let mut server_url: Option<String> = None;
    let mut token: Option<String> = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--url" | "-u" => {
                if i + 1 < args.len() {
                    server_url = Some(args[i + 1].clone());
                    i += 1;
                }
            }
            "--token" | "-t" => {
                if i + 1 < args.len() {
                    token = Some(args[i + 1].clone());
                    i += 1;
                }
            }
            "--help" | "-h" => {
                println!("PPG Desktop — Native Linux GUI for PPG agent orchestration");
                println!();
                println!("USAGE:");
                println!("    ppg-desktop [OPTIONS]");
                println!();
                println!("OPTIONS:");
                println!("    -u, --url <URL>      PPG server URL (default: http://localhost:3000)");
                println!("    -t, --token <TOKEN>  Bearer token for authentication");
                println!("    -h, --help           Print help information");
                println!("    -V, --version        Print version information");
                std::process::exit(0);
            }
            "--version" | "-V" => {
                println!("ppg-desktop {}", env!("CARGO_PKG_VERSION"));
                std::process::exit(0);
            }
            _ => {}
        }
        i += 1;
    }

    log::info!("Starting PPG Desktop");

    let app = PpgApplication::new(server_url, token);
    std::process::exit(app.run());
}
