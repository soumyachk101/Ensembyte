//! `ensembyte-engine` — the desktop app's background engine, as a process of its
//! own ("Ensembyte Engine" in Activity Monitor): the app starts it and attaches;
//! sessions keep running with the app closed. Without the UI linked in.
//!
//! It also answers what the engine runs its own executable for: `mcp` (the
//! Ensembyte MCP server injected into agents) and `--noop-browser` (browser
//! suppression for agents' sign-in flows).

#![cfg_attr(windows, windows_subsystem = "windows")]

fn main() -> anyhow::Result<()> {
    match std::env::args().nth(1).as_deref() {
        Some("--noop-browser") => Ok(()),
        Some("mcp") => {
            ensembyte_app::init_logging(false, "mcp", true);
            ensembyte_app::run_mcp()
        }
        Some("--version" | "-V") => {
            println!("ensembyte-engine {}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        _ => ensembyte_app::background::run(),
    }
}
