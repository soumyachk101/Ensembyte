//! Load the existing Ensembyte delegation tools into this Pi process only.
use crate::{HarnessError, process::Command, scratch::ScratchDir};

pub(super) fn configure(
    cmd: &mut Command,
    config: &orbit_proto::McpServer,
) -> Result<ScratchDir, HarnessError> {
    let scratch = ScratchDir::new("pi-mcp")?;
    let extension = scratch.path().join("ensembyte-mcp.mjs");
    std::fs::write(&extension, include_str!("mcp.mjs"))?;
    let serialized = serde_json::to_string(config).expect("serializable MCP config");
    cmd.arg("--extension")
        .arg(extension)
        .env("ENSEMBYTE_PI_MCP", &serialized)
        .env("ORBIT_PI_MCP", serialized);
    Ok(scratch)
}
