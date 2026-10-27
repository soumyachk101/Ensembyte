//! ensembyte-mcp — a Model Context Protocol server over the running engine.
//!
//! `ensembyte mcp` speaks MCP (JSON-RPC 2.0, newline-delimited) on stdin/stdout
//! and proxies every tool into the engine's localhost IPC — the same
//! `ensembyte_rpc` WebSocket the headed app and `ensembyte sync` dial. Nothing here
//! talks to the edge or touches the filesystem: the engine stays the single
//! authority for chats, devices, projects, and the command plane.
//!
//! The server is hand-rolled rather than an SDK: the MCP surface a stdio
//! tool server needs is five methods (`initialize`, `ping`, `tools/list`,
//! `tools/call`, and the `initialized` notification), and the repo already
//! owns JSON-RPC framing for the Codex and ACP drivers. Zero new crates.
//!
//! When the engine launches a harness it can inject this server into the
//! agent's MCP config with `ENSEMBYTE_CHAT_ID` / `ENSEMBYTE_DEVICE_ID` in the
//! environment. Every send from such an agent is then attributed to its
//! originating chat, and a chat can never message itself.

mod jsonrpc;
mod tools;
mod transcript;
mod ensembyte;

pub use jsonrpc::serve_stdio;
pub use tools::{ToolDef, Tools};
pub use transcript::{RenderOptions, RenderedMessage, render_entries};
pub use ensembyte::{Origin, Ensembyte};

/// How `ensembyte mcp` finds the engine and who it speaks for.
#[derive(Debug, Clone)]
pub struct McpConfig {
    /// Loopback IPC port of the engine to proxy (`ENSEMBYTE_IPC_PORT`, default 27654).
    pub ipc_port: u16,
    /// The engine's data dir, whose `ipc-token` authenticates the IPC dial
    /// (`ENSEMBYTE_DATA_DIR`; the `ensembyte` binary fills in its default). The token
    /// itself is resolved at every dial — `ENSEMBYTE_IPC_TOKEN`, then the
    /// `ENSEMBYTE_IPC_TOKEN_FILE` the engine injects, then `{data_dir}/ipc-token`
    /// — so a long-lived server follows the engine across restarts.
    pub data_dir: Option<std::path::PathBuf>,
    /// The chat whose agent spawned this server, when injected by the engine.
    pub origin: Origin,
}

impl McpConfig {
    /// Resolve from the process environment: `ENSEMBYTE_IPC_PORT` /
    /// `ENSEMBYTE_DATA_DIR` for the engine, `ENSEMBYTE_CHAT_ID` / `ENSEMBYTE_DEVICE_ID`
    /// for the originating chat.
    pub fn from_env() -> Self {
        let ipc_port = std::env::var("ENSEMBYTE_IPC_PORT")
            .ok()
            .and_then(|p| p.parse().ok())
            .unwrap_or(27654);
        Self {
            ipc_port,
            data_dir: std::env::var_os("ENSEMBYTE_DATA_DIR")
                .filter(|dir| !dir.is_empty())
                .map(std::path::PathBuf::from),
            origin: Origin::from_env(),
        }
    }
}

/// Run the MCP server on this process's stdin/stdout until stdin closes.
pub async fn run(config: McpConfig) -> anyhow::Result<()> {
    let ensembyte = Ensembyte::new(config.ipc_port, config.data_dir, config.origin);
    let tools = Tools::new(std::sync::Arc::new(ensembyte));
    serve_stdio(std::sync::Arc::new(tools)).await
}
