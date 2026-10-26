# Ensembyte-rust MCP feature plan

Port the Swift app's user-facing MCP server features into the Rust app:
catalog, connection manager, keychain, OAuth, proxy, probe, and per-provider
injection. The Rust app already has a working Orbit MCP server
(`crates/mcp`) and per-harness injection points. This plan adds the missing
user-server layer.

## What the Swift app has (reference features)

```
Ensembyte-swift/Ensembyte/Services/MCP/
├── MCPCatalogEntry + Resolve   # 35 preconfigured servers, {field} placeholder
├── MCPStore                    # @MainActor @Observable connection manager
├── MCPKeychain                 # per-server, per-field Secret storage
├── MCPOAuth                    # Full OAuth 2.1 + PKCE, dynamic client registration
├── MCPProxy                    # Localhost HTTP reverse proxy (NIO-free)
├── MCPProbe                    # One-shot: connect, call tools/list, return summary
├── MCPExternalSync             # One-time migration: clean managed ids from external configs
├── MCPSessionOverrides         # Per-session runtime overrides (Copilot flags, OpenCode env)
├── MCPBridgeSource             # JS bridge for Pi/Command-Code to consume MCP tools
└── MCPProviderConfig           # Emits user config files for all 4+ providers
```

**Core models** (in Swift `Core/`):
- `MCPTransport`: `.stdio(command, args)`, `.http(url, headers)`, `.oauth(url)`
- `MCPField`: user input a server needs (secret/text/path)
- `MCPCatalogEntry`: 35 built-in servers with metadata
- `MCPResolvedServer`: filled-in, launchable form
- `MCPConnection`: Codable, persisted per-server state
- `MCPConnectionState`: notConnected / connecting / connected(toolCount) / failed(msg) / needsSetup(guide)
- `MCPProbeResult`: serverName?, serverVersion?, tools[]

**Provider dialects** (Swift `MCPProviderConfig`):
- `claude()` → writes `~/.ensembyte/mcp/claude.json`, passed via `--mcp-config <path>`
- `codex()` → writes `codex.json`, passed via `config` JSON-RPC param
- `acpServers()` → flat array, passed to ACP `session/new` `mcpServers`
- `gemini()` → writes `gemini-settings.json`, passed via env var
- `copilot()` → writes `copilot.json`, passed via `--additional-mcp-config`

---

## What the Rust app has today

| Area | Status |
|---|---|
| Orbit MCP server (`crates/mcp`) | ✅ Working — 17 tools, JSON-RPC stdio |
| `RunRequest.mcp: Option<McpServer>` | ✅ Single-server injection |
| Per-harness injection dialects | ✅ All 6 drivers (claude, codex, acp, opencode, cursor, pi) |
| User MCP catalog | ❌ Greenfield |
| User MCP connection manager | ❌ Greenfield |
| MCP keychain / secret storage | ❌ Greenfield |
| MCP OAuth flow | ❌ Greenfield |
| MCP proxy | ❌ Greenfield |
| MCP probe (list tools of external server) | ❌ Greenfield |
| Settings pane for MCP | ❌ Greenfield |

### Key architectural facts for the Rust port

**Where user servers live.** The engine's per-user settings precedent is
`harness-prefs.json` at `{data_dir}/harness-prefs.json`
(`crates/engine/src/registry.rs:319-340`), shape `HarnessPrefsFile`. The user
MCP server list goes in a new `mcp-servers.json` in the same data dir,
engine-owned, device-scoped. RPC methods mirror `SetHarnessEnabled`
(`registry.rs:390-422`): `SetMcpServer`, `DeleteMcpServer`, `ListMcpServers`.

**`RunRequest.mcp` is single-server only.** The new field is
`RunRequest.mcp_servers: Vec<McpServer>` (serde `default`, wire-compatible).
The engine stamps it at `sessions.rs:1808` from the new `mcp-servers.json`
store. The existing `mcp: Option<McpServer>` (Orbit) stays as-is.

**Per-harness dialect sites to extend** (six functions, each currently takes
`Option<&McpServer>` and must accept `&[McpServer]`):

| Harness | File | Function | Current signature | New signature |
|---|---|---|---|---|
| Claude | `claude/mod.rs:79-96` | `mcp_config_arg` | `fn mcp_config_arg(mcp: &McpServer) -> String` | `fn mcp_config_arg(servers: &[McpServer]) -> String` (emit multi-entry JSON) |
| Codex | `codex/mod.rs:91-98` | `codex_mcp_overrides` | `fn codex_mcp_overrides(mcp: &McpServer) -> Value` | `fn codex_mcp_overrides(servers: &[McpServer]) -> Value` (emit multi-key `mcp_servers` table) |
| ACP | `acp/mod.rs:2481-2499` | `acp_mcp_servers` | `fn acp_mcp_servers(mcp: Option<&McpServer>) -> Vec<Value>` | `fn acp_mcp_servers(servers: &[McpServer]) -> Vec<Value>` (push all) |
| OpenCode | `opencode/mod.rs:4282-4322` | `mcp_config` | parses `OPENCODE_CONFIG_CONTENT`, adds one entry | extend to add N entries from user list |
| Cursor | `cursor/mod.rs:360` + `shim.mjs:661-662` | inline `mcpServers` map | single Orbit entry | add user entries to the map alongside Orbit |
| Pi | `pi/mcp.rs` + `pi/mcp.mjs:43` | `--extension` + `ENSEMBYTE_PI_MCP` env | one serialized `McpServer` JSON | change to serialized `[McpServer]` JSON, generalize `mcp.mjs` to spawn/bridge N servers |

**Keychain.** The Rust app has a macOS Keychain module at
`crates/engine/src/agent_accounts.rs:2900` (`mod keychain`, shells out to
`/usr/bin/security`). It reads other CLIs' logins (Claude Code, Gemini) but
is not a general app-owned secret store. The plan adds a new
`crates/engine/src/mcp_keychain.rs` using the same pattern:
`add-generic-password -U` for write, `find-generic-password` for read, 15 s
timeout, scoped to service `com.ensembyte.mcp.<server_id>`.

**OAuth.** No existing MCP OAuth in the Rust app. The new
`crates/engine/src/mcp_oauth.rs` implements:
- Discovery: `/.well-known/oauth-protected-resource` → `/.well-known/oauth-authorization-server` → `openid-configuration` (path-prefixed + origin forms)
- Dynamic client registration (RFC 7591)
- PKCE (S256 via the `ring` or `sha2` crate — check workspace deps)
- Loopback `TcpListener` on ephemeral port for the browser redirect
- Token refresh: in-flight dedup (same pattern as Swift's `OAuthRefreshGate`)
- Token storage: `mcp_keychain` (not plaintext on disk)

**Proxy.** No existing proxy. The new `crates/engine/src/mcp_proxy.rs`
implements a localhost HTTP reverse proxy (hand-rolled with `tokio::net::TcpListener`,
mirroring Swift's `MCPProxy` which uses `NWConnection`):
- Persistent port, written to `mcp-servers.json` `proxyPort`
- Routes `/mcp/<serverID>/<subpath>` to the upstream
- For `isOAuth` servers: injects `Authorization: Bearer <token>` from `mcp_keychain`
- 401 → refresh token → retry once
- 32 MB chunked-body cap
- `mcp_proxy_url(serverID) -> "http://127.0.0.1:<port>/mcp/<serverID>"`

**Settings pane.** New `crates/ui/src/settings/mcp.rs` (`McpPage`), modeled
on `settings/harnesses.rs` (device-scoped, per-page `ListMcpServers` probe,
device switcher, `SetMcpServer`/`DeleteMcpServer` writes). Hook into:
- `SettingsSection` enum (`crates/ui/src/shell.rs:526`) — add `Mcp` variant
- `ALL` array (`shell.rs:547-557`) — add it
- `label()` / icon in `render_settings_nav` (`shell.rs:7035+`)
- `Shell::settings_outlet` lazy field (`shell.rs:4817`)
- `Route::Settings(SettingsSection)` (`shell.rs:679,826`)
- `mod mcp;` line in `crates/ui/src/settings.rs`

---

## Implementation phases

### Phase 1 — Core data model + engine store (2 days)

**New files:**
- `crates/proto/src/mcp.rs` — `McpTransport`, `McpField`, `McpCatalogEntry`,
  `McpResolvedServer`, `McpConnection`, `McpConnectionState`, `McpProbeResult`,
  `McpServer` (extend existing struct with `McpTransport` fields)
- `crates/engine/src/mcp_store.rs` — `McpStore`: loads/saves
  `mcp-servers.json`, shape `{servers: [McpConnection], proxyPort: u16?}`
- `crates/engine/src/mcp_keychain.rs` — macOS Keychain read/write wrapper
  (mirrors `agent_accounts.rs:2900` pattern)

**Changes to existing files:**
- `crates/proto/src/agent.rs` — add `mcp_servers: Vec<McpServer>` to
  `RunRequest` (serde `default`, wire-compatible with old clients)
- `crates/engine/src/lib.rs` — load `mcp_store` at startup, store in `Engine`
- `crates/engine/src/rpc.rs` — add RPC methods:
  - `ListMcpServers {targetDeviceId?} -> [McpConnection]`
  - `SetMcpServer {connection: McpConnection} -> McpConnectionState`
  - `DeleteMcpServer {serverId: String} -> ()`
  - `ProbeMcpServer {serverId: String} -> McpProbeResult`
  - `McpOAuthSignIn {serverId: String, url: String} -> ()` (triggers browser)
  - `McpOAuthSignOut {serverId: String} -> ()`
- `crates/rpc/src/lib.rs` — add method constants: `LIST_MCP_SERVERS`,
  `SET_MCP_SERVER`, `DELETE_MCP_SERVER`, `PROBE_MCP_SERVER`,
  `MCP_OAUTH_SIGN_IN`, `MCP_OAUTH_SIGN_OUT`

**Tests:**
- `cargo test -p ensembyte-engine mcp_store` — JSON round-trip, version
  migration
- `cargo test -p ensembyte-engine mcp_keychain` — skip on non-macOS
  (feature-gated)

---

### Phase 2 — MCP probe + per-harness injection (2 days)

**New files:**
- `crates/engine/src/mcp_probe.rs` — one-shot probe: connect to a user's
  MCP server (stdio or HTTP), call `initialize` + `tools/list`, return
  `McpProbeResult`. No new crates: reuse `tokio::process::Command` for
  stdio, `reqwest` or `hyper` for HTTP (check what's already in the
  workspace — the engine uses `tokio-tungstenite` so `reqwest` or
  `hyper` is likely already a dep).
- `crates/engine/src/mcp_oauth.rs` — full OAuth 2.1 + PKCE flow
- `crates/engine/src/mcp_proxy.rs` — localhost HTTP reverse proxy

**Per-harness dialect changes** (six functions, all in `crates/harness/`):
- `claude/mod.rs:79` — `mcp_config_arg(servers: &[McpServer])`
- `codex/mod.rs:91` — `codex_mcp_overrides(servers: &[McpServer])`
- `acp/mod.rs:2481` — `acp_mcp_servers(servers: &[McpServer])`
- `opencode/mod.rs:4282` — `mcp_config(...)` extend for N entries
- `cursor/mod.rs:360` + `shim.mjs:661` — add user entries to `mcpServers` map
- `pi/mcp.rs` + `pi/mcp.mjs` — change `ENSEMBYTE_PI_MCP` to `Vec<McpServer>`,
  generalize the `.mjs` bridge to spawn/bridge N servers

**Engine stamping** (`sessions.rs:1808`):
```rust
// today:
request.mcp = inner.ensembyte_mcp(&chat_id);  // Orbit only

// new:
request.mcp = inner.ensembyte_mcp(&chat_id);  // Orbit (unchanged)
request.mcp_servers = inner.mcp_store.connected_servers();  // user servers
```

**Tests:**
- `cargo test -p ensembyte-harness` — extend existing `mcp_injection_tests`
  modules in claude/codex/acp/opencode to assert multi-server injection
- `cargo test -p ensembyte-engine mcp_probe` — stdio + HTTP probe with stub
  server

---

### Phase 3 — Settings UI pane (1–2 days)

**New files:**
- `crates/ui/src/settings/mcp.rs` — `McpPage` (gpui `Render` struct), modeled
  on `settings/harnesses.rs`

**UI layout** (matching Swift's `MCPSettingsPage`):
- Top: "Connected" section — one row per connected server, `Toggle` for
  enable/disable, "Refresh / Show tools / Disconnect" menu, tool-count badge
- Middle: "Custom" section — editable list of user-defined stdio/http servers
- Bottom: catalog cards grouped by `McpCategory` with search box
- Per-server: key panel (for `McpField.kind == Secret`), OAuth "Sign in"
  button, setup guide panel (for `McpConnectionState::NeedsSetup`)

**Wiring** (`crates/ui/src/shell.rs`):
- `SettingsSection::Mcp` variant
- `render_settings_nav` icon + label
- `Shell::settings_outlet` lazy `mcp_page` field
- `Route::Settings(SettingsSection::Mcp)` arm

**RPC calls** from the UI:
- `ListMcpServers` on attach + on device switch
- `SetMcpServer` / `DeleteMcpServer` on connect/disconnect
- `ProbeMcpServer` on "Refresh" / "Show tools"
- `McpOAuthSignIn` / `McpOAuthSignOut` on OAuth button

---

### Phase 4 — Polish + end-to-end test (1 day)

- `MCPExternalSync` equivalent: one-time migration to clean up any
  Ensembyte-managed server ids from external CLI config files
  (only needed if we've ever written to those files directly — the Rust
  app currently doesn't, so this may be a no-op)
- `MCPSessionOverrides` equivalent: per-session runtime overrides
  (Copilot `--additional-mcp-config` + `--disable-mcp-server <name>` flags,
  OpenCode `OPENCODE_CONFIG_CONTENT` env) — check if the Rust app drives
  Copilot or OpenCode as harnesses today; if not, skip
- Smoke test: `cargo run -p ensembyte-engine --example mcp_standalone_smoke`
  extended to include a user server in the injection, verify the agent
  sees both the Orbit tool and the user server's tools
- `cargo test -p ensembyte-mcp` — confirm no regressions in the existing
  17-tool Orbit server

---

## New crate / file summary

```
crates/proto/src/mcp.rs          (new)  — data model
crates/engine/src/mcp_store.rs   (new)  — persisted store
crates/engine/src/mcp_keychain.rs (new) — macOS Keychain
crates/engine/src/mcp_probe.rs   (new)  — tools/list probe
crates/engine/src/mcp_oauth.rs   (new)  — OAuth 2.1 + PKCE
crates/engine/src/mcp_proxy.rs   (new)  — localhost HTTP reverse proxy
crates/ui/src/settings/mcp.rs    (new)  — settings page

crates/proto/src/agent.rs        (edit) — RunRequest.mcp_servers: Vec<McpServer>
crates/engine/src/lib.rs         (edit) — load mcp_store
crates/engine/src/rpc.rs         (edit) — 6 new RPC methods
crates/rpc/src/lib.rs           (edit) — 6 new method constants
crates/engine/src/sessions.rs    (edit) — stamp mcp_servers
crates/harness/src/{claude,codex,acp,opencode,cursor,pi}/* (edit) — dialect changes
crates/ui/src/shell.rs           (edit) — SettingsSection::Mcp
crates/ui/src/settings.rs        (edit) — mod mcp;
```

## Open questions

1. **Which MCP HTTP client crate?** The engine uses `tokio-tungstenite`
   (WebSocket). For plain HTTP MCP probes and the proxy, we need an HTTP
   client. Check if `reqwest` or `hyper` is already in the workspace
   `Cargo.toml`; if not, add one (prefer `reqwest` for OAuth + proxy in
   one dep; `hyper` if we want to minimize deps).

2. **Catalog entry shape.** The Swift app has 35 hardcoded
   `MCPCatalogEntry` structs. The Rust equivalent lives in
   `crates/proto/src/mcp.rs` as a static `const CATALOG: &[McpCatalogEntry]`.
   Should it be a single `.rs` file or a `.json` bundled resource?
   Recommendation: single `.rs` file (no extra build machinery), matching
   the Swift app's approach.

3. **OAuth on non-macOS.** The Swift `MCPOAuth` uses `NWListener` for the
   loopback callback. The Rust `mcp_oauth.rs` needs a `TcpListener` on
   loopback that works on Linux + Windows + macOS. `tokio::net::TcpListener`
   handles this — verify it works under the gpui sandbox in `ui_settings`.

4. **Proxy port persistence.** The Swift `MCPProxy` persists its port to
   a file. The Rust equivalent writes `proxyPort` into `mcp-servers.json`.
   Confirm the port is stable across restarts (the Swift app's
   `MCPProxy.loadPort()` reads the persisted value and reuses it).

5. **Pi bridge generalization.** `pi/mcp.mjs` currently spawns exactly one
   stdio server. Changing it to N servers means the `ENSEMBYTE_PI_MCP` env
   var becomes a JSON array instead of a single object. This is a breaking
   change to the Pi extension protocol — coordinate with the Pi team or
   version the extension (e.g. `ENSEMBYTE_PI_MCP_V2`).
