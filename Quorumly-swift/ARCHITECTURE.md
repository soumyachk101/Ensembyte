# Quorumly — Architecture

## Overview

Quorumly is an umbrella project for a native coding-agent client. The two apps that live under it do the same job — give you a window onto the CLI-based coding agents (Claude Code, Codex, Cursor, and others) that you already pay for — but they pick different stacks so you can pick the one that matches your platform.

- **Quorumly for macOS** — a native Swift / SwiftUI app for **macOS 26+** (Apple silicon). Lives in `Quorumly-swift/`.
- **Quorumly Desktop** — a native Rust / gpui app for **macOS, Windows, and Linux**. Lives in `Quorumly-rust/`.

Quorumly is the umbrella that owns the brand, the website, and the cross-project documentation. Author: Soumya Chakraborty.

Both apps share the same product concepts:

- A persistent **project, thread, and worktree** surface.
- A **provider adapter** layer that shells out to the CLI tools you already have installed and signed in, on your own subscriptions. Neither app embeds a model.
- **Hydra** multi-head orchestration in Quorumly for macOS, where a single chat fans out into parallel agent worktrees that are merged back as one result.
- A **Model Context Protocol (MCP)** integration layer with a catalog of preconfigured servers, stdio/HTTP/SSE transports, and an OAuth flow.
- **Local-first state** with crash-safe writes, versioned migrations, and a theme system.
- **Provider-aware credit and plan-limit tracking** so you can see quota state inline.

The two implementations diverge where the platforms demand it: SwiftUI for the polished macOS experience, Rust + gpui for cross-platform reach and an optional multi-device sync layer backed by Cloudflare Durable Objects.

---

## Repository Layout

```
Quorumly/
├── Quorumly-swift/             macOS-native Swift / SwiftUI client
│   ├── Quorumly/           App target (App, Core, Services, UI layers)
│   ├── Resources/          Bundled assets
│   ├── docs/               Architecture, audits, plans
│   ├── scripts/            Release automation
│   └── release/            DMG packaging, signing, notarization
│
├── Quorumly-rust/                  Cross-platform Rust + gpui client
│   ├── Cargo.toml          Workspace definition
│   ├── crates/             Core library crates
│   ├── apps/quorumly/      The binary (headed default, `headless` subcommand)
│   ├── edge/               TypeScript Cloudflare Worker + Durable Objects
│   ├── docs/               Architecture, research, plans
│   ├── dist/               Platform distribution assets
│   └── scripts/            Packaging and CI scripts
│
└── Quorumly/               Umbrella project
    ├── README.md
    └── docs/ARCHITECTURE.md  This document
```

The umbrella repository owns the brand, the website, and the cross-project documentation. Each app is developed in its own folder with its own build, tests, and release pipeline.

---

## Implementation 1: Quorumly for macOS (Swift / SwiftUI)

Quorumly for macOS is a native macOS coding-agent client. The Swift codebase is organized into four layers with a strict one-way dependency rule: each lower layer knows nothing of the layers above it.

### Four-Layer Architecture

```
App  (entry, model, runtime, windows, captures, every feature view)
  |
  +-- Services (Git, Store, Providers)
  |     |
  |     +-- Core (models, pure support)
  |
  +-- UI (Chrome, Common, Markdown, Theme, Sound)
        |
        +-- Core (models, pure support)
```

#### Core

Pure domain logic with zero app-level imports. Every other layer depends on it.

- **Projects and threads** — the fundamental workspace units.
- **Timeline** — the turn-by-turn record of a conversation.
- **Provider kinds** — the enum that identifies which CLI is driving a session.
- **Hydra** — the multi-head orchestration model (launch, status, report, merge).
- **Shortcuts** — keyboard shortcut definitions.
- **Process I/O** — stdio wrappers, JSON-RPC framing, login shell helpers.

Core has no external app dependency and is unit-testable in isolation.

#### Services

Stateful subsystems that own persistence and external tool integration. Depends on Core only.

- **Git** — diff parsing, blame, log, touched-paths, worktree creation, commit/push.
- **Store** — on-disk JSON persistence with versioned migrations, crash-safe writes (tmp-then-rename).
- **Providers** — adapters for each supported coding-agent CLI. Each adapter translates that tool's protocol into the app's unified event model.
- **MCP** — the Model Context Protocol integration: catalog, store, bridge source, keychain, OAuth, proxy, wire protocol, and external sync.

#### UI

Renderer-agnostic presentation logic. Depends on Core only.

- **Window chrome** — resizable panels, draggable splitters, veil effects.
- **Common controls** — buttons, sliders, palette, toggles, working indicators, attachment previews, render budget.
- **Markdown rendering** — streaming-aware markdown with tool-call plans, to-do lists, error blocks, reasoning disclosure.
- **Theme** — 26 tinted-glass themes, including System, Catppuccin, Dracula, Claude, and Codex.
- **Sound** — chime on completion, per-provider tone mapping.

#### App

The top-level assembly. Knows about everything.

- App entry and lifecycle, settings model and defaults.
- Project library, thread runtime, and capture system.
- The runtime layer: `ThreadRuntime`, `AutoContinue`, and `LimitHandoff` that drive background agent execution and recovery.
- Every feature view: sidebar, chat, composer, changes, terminal, palette, settings, usage, tour.
- Welcome tour on first launch (six pages of real captures).
- Notification and permission handling.
- App updater and update checker.
- Legacy migration for upgrading older store shapes.

The dependency rule is enforced by convention: Core has no imports from outside the standard library; Services and UI depend only on Core; App depends on everything.

---

## Implementation 2: Quorumly Desktop (Rust / gpui)

Quorumly Desktop is a cross-platform client in Rust with a gpui UI. One binary, headed by default or headless via subcommand. macOS, Windows, and Linux from a single codebase.

### Topology

```
gpui UI ─ in-proc/localhost RPC ─ engine A ══ DeviceRoom DO relay ══ engine B ─ RPC ─ gpui UI
                    │       optional edge Worker: auth, rooms, R2        │
                    └── optional chat2 sync ──  ChatRoom DO (per chat) ──┘
                                          └─ Workspace registry room ────┘
```

- **Engine** is the Rust backend: runs agents, owns auth, terminals, repos/worktrees, diff sync, and doc hosting. Pure Rust daemon, fully functional headless.
- **UI** is the gpui frontend: renders engine state. Talks the same typed RPC whether the engine is in-process or a separate daemon. Organized around **spaces** — (device, folder) pairs, local or synced according to the active profile.
- **Edge** (TypeScript, Cloudflare Workers) hosts Durable Objects for session rooms, device rooms, chat rooms, workspace registry, R2 attachments, and WorkOS auth. Postgres, the Hono server, and the WebRTC signaling stack are all gone.

### Headed and Headless Modes

Single binary `quorumly`:

- `quorumly` — headed. If a local engine daemon is already listening on the IPC port, connect to it; otherwise run the engine **in-process** (RPC over an in-memory duplex — same protocol, zero serialization shortcuts) **and serve that same engine on the IPC port**. The embedded engine is not private: any other viewport can attach to the running app without it first being restarted as a daemon. Binding is best-effort — if the port is taken, the window still opens, having lost only the ability to host peers.
- `quorumly headless` — engine only. A clean installation immediately serves its local profile over localhost IPC; when a saved account selects the synced profile at startup and a bearer is available, it also hosts its DeviceRoom for remote control. A VPS can run this while a laptop's UI drives it.

### Local-First Workspace Profiles

Authentication and workspace selection are deliberately separate state machines:

- `AuthState` is live credential state: `SignedOut`, `NeedsOrganization`, or `SignedIn`. It may change after login, refresh, revocation, or logout.
- `WorkspaceScope` is the immutable storage and transport boundary captured once at engine startup: `Local`, `Synced`, or explicit `Development`.

The engine never re-resolves an open store because `AuthState` changed. This prevents a sign-in, token refresh, or revocation from silently swapping databases or attaching online transports to a runtime that started local-only.

| Startup condition                                     | `WorkspaceScope` | Online transports |
|-------------------------------------------------------|------------------|-------------------|
| WorkOS enabled, no parseable saved `session.json`     | `Local`          | Disabled          |
| Parseable saved WorkOS session                        | `Synced`         | Enabled when a bearer is available; organization onboarding completes before opening the store when needed |
| WorkOS disabled without a dev bearer                  | `Development`    | Disabled          |
| Explicit non-empty dev bearer                         | `Development`    | Enabled           |

`quorumly login` and `quorumly logout` operate on `session.json` while the engine is stopped. Login selects `Synced` for the next start; logout selects `Local` for the next start. The UI may update live authentication status, but the active `WorkspaceScope` still changes only after restart.

The resolved profile selects the session snapshots, registry snapshot, run journals, and attachment cache that may contain workspace data:

| Scope         | Store and journals                              | Uploads                                                   |
|---------------|-------------------------------------------------|-----------------------------------------------------------|
| `Local`       | `{data_dir}/profiles/local/`                    | `{data_dir}/profiles/local/uploads/`                      |
| `Synced`      | `{data_dir}/orgs/{org_id}/{user_id}/`           | `{data_dir}/orgs/{org_id}/{user_id}/uploads/`             |
| `Development` | `{data_dir}/orgs/{org_id}/{user_id}/`           | `{data_dir}/orgs/{org_id}/{user_id}/uploads/`             |

The synced and development store roots preserve the historical cloud layout while their attachment caches are account-scoped. Local identity lives in `{data_dir}/local-profile.json`; its UUID is stable across restarts and is not an account or development identity.

### Cargo Workspace

```
Quorumly-rust/
  Cargo.toml                Workspace definition
  crates/
    proto/      quorumly-proto (proto)     Wire types: AgentEvent, ToolCall, RunRequest, Model,
                                entities, RPC envelopes (serde; ndjson framing);
                                `view` = the pure derivations both frontends share
                                (sort orders, staleness gating, grouping, boot gate)
    doc/        quorumly-doc (doc)       Session-doc + workspace-registry schemas, mirror layer,
                                parts fold, continuations, command ledger, sidecars
    sync/       quorumly-sync (sync)      Loro room client (join/VV backfill/fragments/backoff),
                                ephemeral presence, DocsStore (SQLite snapshots +
                                processed-command ledger)
    harness/    quorumly-harness (harness)   Harness trait + claude-code (stream-json subprocess),
                                codex (app-server JSON-RPC), mock; steering mailbox,
                                requestInput, models/reasoning/options catalogs
    engine/     quorumly-engine (engine)    Sessions engine (pub/sub, run journal, recovery,
                                stall watchdog), doc host + command executor,
                                repos/worktrees, checkout-diff sync, terminals
                                (portable-pty), uploads, agent accounts (cred swap),
                                auth (WorkOS via edge), device-room host/peers,
                                identity
    rpc/        quorumly-rpc (rpc)       UiRpc/ControlRpc: typed req/resp/stream over WS
                                (tokio-tungstenite) + in-memory transport;
                                device-room virtual sockets ({s,k,to,from} frames)
    theme/      quorumly-theme (theme)     Source-neutral theme schema + built-in/custom registry,
                                validation, provenance, and local VS Code compiler
    voice/      quorumly-voice (voice)     Desktop-local optional Parakeet model, capture and
                                inference; no RPC/sync
    ui/         quorumly-ui (ui)        gpui app: shell, sidebar, conversation, composer,
                                terminal view, diff pane, settings, animation kit
    markdown/   quorumly-markdown (markdown)  Streaming markdown renderer
    syntax/     quorumly-syntax (syntax)    Syntax highlighting
    mcp/        quorumly-mcp (mcp)       Model Context Protocol integration
    text/       quorumly-text (text)      Text processing utilities
    mobile/     quorumly-mobile (mobile)    Mobile companion support
    client/     quorumly-client (client)    Client crate
    update/     quorumly-update (update)    Auto-update support
    preview/    quorumly-preview (preview)   Preview components
  apps/
    quorumly/                  The binary (headed default, `headless` subcommand)
  edge/                        TypeScript Worker + Durable Objects (session rooms,
                               device rooms, chat rooms, registry rooms, R2,
                               WorkOS auth)
  docs/                        Architecture, research, plans
  scripts/                     Packaging and CI scripts
  dist/                        Platform distribution assets
```

The engine async runtime is **tokio** throughout; the UI bridges via `gpui_tokio` (`Tokio::spawn` futures surfaced as gpui `Task`s). In-process mode runs the engine on its own tokio runtime thread; the UI never blocks on it.

### Data Model — Loro CRDTs

Quorumly Desktop uses two persistent document kinds. When sync is enabled, session docs ride the chat2 row protocol (Loro updates as append-only rows plus Range-resumable checkpoints, ChatRoom DO) and the registry rides its own row-frame protocol; local-only profiles persist the same docs without joining rooms.

1. **Session doc** (per chat) — the transcript and durable command queue. Schema is a Rust port of the session-doc package: `meta` map, `messages` list (parts as list-of-maps with **LoroText bodies** — the measured 1.03× oplog shape; never LWW value rewrites), `commands` list with ledger rules (append-only per-device entries; host-only outcomes; dedupe/TTL/supersede evaluation). Continuation splitting at 256KB, render-only tool parts (full inputs stay in the host's local run journal), tail/diff sidecars. Constants carried over: `STREAM_COMMIT_MS=120`, `DO_FLUSH_MS=5s`, compaction at 8MB, retain 30d, tail 64.

2. **Workspace registry doc** (per profile) — the `registry1` snapshot stores spaces (id, deviceId, path, name?, gitDetected, checkoutId), the chats index (id, deviceId, title, archived, cwd, branch, checkoutId, spaceId, lastSeenAt, lastMessagePreview/At, config), devices, session-status rows, and checkout-diff summary pointers. A space is a device+folder pair in the active profile; the owning device stamps git presence so branch pickers and the diff sidebar can gate without another RPC. Local scope keeps the registry entirely in its profile store. Synced and development scopes join `/registry/{orgId}/ws`, backed by the private per-user room `reg1/{orgId}/{userId}`; rows are never visible to every member of an organization.

   Writer discipline: each device writes its own device and session-status rows, rows for chats it hosts, and git stamps for spaces it owns. Creates, renames, archives, and seen marks are LWW sets accepted from any device. `deleteSpace` tombstones the space and every chat/session row in it in one commit. Presence uses ephemeral room frames rather than durable heartbeat writes.

3. **Mirror layer** (`doc`) — Rust equivalent of loro-mirror: typed structs for the schema, **incremental** application of `doc.subscribe` diffs into cached state (no full re-hydration per change), and a diff-reconcile write path. The UI renders mirror state directly with per-entry change notifications.

### Command Plane

Send / steer / interrupt / respondInput = durable command entries in the session doc (`QueueCommand`), executed by the chat's **host** device. Executor is gated on chat ownership; the entry is marked processed before execute; steer with no live run dispatches as the next turn. Offline sends queue in the doc.

---

## Shared Architecture Concepts

### Provider Adapter System

Both implementations shell out to the CLI tools the user already has installed and signed in, on their own subscriptions. Each provider adapter translates that tool's native protocol into the app's unified streaming event model.

#### Provider Lifecycle

The lifecycle is common to both implementations:

1. **Detection** — on startup, the registry scans for installed CLIs on `$PATH` and checks authentication state.
2. **Registration** — each found provider is registered in the application store.
3. **Session creation** — when a thread is assigned a provider, a session object is spawned. The session owns the child process (or HTTP client for native APIs).
4. **Event streaming** — stdout / stderr (or SSE) is parsed into structured events: text chunks, reasoning blocks, tool calls, plans, errors.
5. **Teardown** — on thread close or app exit, the child process is terminated and the PTY/pipe is closed.

#### Adapters

| Provider    | CLI / Auth                          | Protocol                          | macOS app  | Desktop |
|-------------|-------------------------------------|-----------------------------------|:----------:|:-----:|
| Claude      | `claude`                            | stream-json with permission prompts | yes        | yes   |
| Codex       | `codex`                             | app-server JSON-RPC               | yes        | yes   |
| OpenCode    | `opencode`                          | Agent Client Protocol             | yes        | —     |
| Cursor      | `cursor-agent`                      | Agent Client Protocol             | yes        | yes   |
| Grok        | `grok`                              | Agent Client Protocol             | yes        | yes   |
| Antigravity | `agy`                               | stream-json headless              | yes        | yes   |
| Copilot     | `copilot`                           | headless JSON-RPC (Copilot SDK)   | yes        | —     |
| Command Code| `cmd`                               | headless print mode (NDJSON)      | yes        | —     |
| Pi          | `pi`                                | RPC mode (JSONL over stdio)       | yes        | yes   |
| Devin       | `devin`                             | local agent                       | —          | yes   |
| Hermes      | `hermes`                            | local agent                       | —          | yes   |
| DeepSeek    | `DEEPSEEK_API_KEY` / `ZAI_API_KEY`  | OpenAI-compatible HTTP            | yes        | —     |
| Meta        | `MODEL_API_KEY` at `api.meta.ai/v1` | Muse Spark HTTP                   | yes        | —     |

Native-API providers (DeepSeek, Meta) connect via HTTP and bypass a CLI entirely. The remaining adapters wrap a child process and parse its stdout.

#### Credits and Plan Limits

Each provider adapter tracks its own quota state:

- **Codex** — rolling window resets; a banked reset can be spent from the usage popover.
- **Claude, Antigravity, Copilot, Command Code** — per-plan rolling limits and reset timers.
- **DeepSeek** — API key credit balance.
- **Command Code** — usage also tracked via API key credits.

In Quorumly for macOS, the effort slider fuses the lead's model and the heads' model into a single control when Hydra is active.

---

### Hydra: One Chat, Many Heads

Hydra is a Quorumly feature that turns a single conversation into parallel agent work. When enabled, the lead agent writes briefs, dispatches heads in parallel, and lands their results back into the checkout as one merge.

```
Lead agent (your chat)
  ├── brief generator  →  writes per-head task descriptions
  ├── head launcher    →  spawns N isolated worktrees
  │     ├── Head 0  (Provider A, model X)
  │     ├── Head 1  (Provider A, model X)
  │     └── Head N  (Provider B, model Y)   ← cross-provider allowed
  └── merge driver     →  lands all heads, resolves conflicts
```

**Key invariants:**

- Each head runs in its own copy of the project (a git worktree).
- A Hydra pair configures the lead's model and the heads' model independently.
- The pair can cross providers: a strong lead on one, quick heads on another.
- One effort slider controls both the lead and the heads.
- Heads can be queued (run one at a time) or launched in parallel.
- The lead's floating panel shows each head's status, tool calls, and token spend.

In the Swift app, the Hydra model lives in Core (`Hydra.swift`, `HydraCookbook.swift`, `HydraDelegationStream.swift`) and is orchestrated by `AppModel+Hydra.swift`, `AppModel+HydraPairs.swift`, and `AppModel+HydraMerge.swift`. The CookBook recipe resolution and delegation stream are pure support code that any layer can depend on.

---

### MCP Integration

Both implementations include a full Model Context Protocol integration layer.

- **Catalog** — 30+ preconfigured MCP tools across five categories: Developer, Browser, Knowledge, Database, Communication.
- **Connection manager** — add, update, delete, and monitor MCP server connections from Settings.
- **Transport support** — stdio, HTTP, and SSE transports.
- **Local proxy** — the app runs a local proxy so tools can reach MCP servers without exposing them externally.
- **OAuth authentication** — MCP servers that require OAuth are handled through the app's auth flow.

In Quorumly for macOS, the MCP service layer manages the catalog, connections, transports, and credentials. In Quorumly Desktop, the `mcp` crate provides the same surface.

---

### State Management

All persistent state lives in a single application store, serialized to disk.

**Quorumly for macOS (AppStore):**

```
AppStore
  ├── library
  │     ├── projects: Vec<Project>
  │     ├── threads: Vec<ChatThread>
  │     ├── thread_documents: Vec<ThreadDocument>
  │     ├── hydra_pairs: Vec<HydraPair>
  │     └── mcp: MCPStore
  ├── settings: AppSettings
  ├── providers: Vec<Provider>
  ├── library_items: Vec<LibraryItem>
  └── mcp: MCPStore (connections)
```

**Quorumly Desktop:**

Quorumly Desktop uses two persistent document kinds, persisted via Loro CRDTs with SQLite snapshots for local-only profiles. When sync is enabled, the same docs ride Durable Object rooms in the edge.

```
Session doc (per chat) ─── transcript, commands, sidecars
Workspace registry doc (per profile) ─── spaces, chats, devices, status
```

**Persistence guarantees (both implementations):**

- **Crash-safe writes** — every save goes to a temporary file first, then renames. A crash mid-write cannot leave a partial file.
- **Versioned migrations** — the store file carries a version envelope. The migration layer detects old shapes and upgrades them on load.
- **Convenience fields** (Quorumly for macOS) — top-level `projects`, `threads`, and `hydra_pairs` are convenience accessors kept in sync with `library` via `sync_convenience_fields()`.

---

### Data Flow

**Send a message (Quorumly for macOS):**

```
User types in Composer
  │
  ├── Frontend validates input
  │
  ├── Invoke send_message(thread_id, text, attachments)
  │     │
  │     ├── Handler reads AppStore
  │     │     finds thread, finds provider
  │     │
  │     ├── Spawns provider session (child process or HTTP client)
  │     │
  │     ├── Writes message to provider stdin / sends HTTP request
  │     │
  │     ├── Spawns stdout parser
  │     │     │
  │     │     └── On each parsed event:
  │     │           emit message-chunk event
  │     │
  │     └── Returns ThreadUpdate to frontend
  │
  ├── Frontend receives message-chunk events
  │     appends to chat store
  │     re-renders ChatView
  │
  └── On completion:
        emit hydra-progress (if Hydra active)
        save checkpoint (if git repo)
        notify (if notify_when_finished)
```

**Quorumly Desktop data flow:**

```
gpui UI ── in-memory or WebSocket RPC ── Engine
                                          │
                                          ├── Spawns harness
                                          │     (claude-code subprocess or codex JSON-RPC)
                                          ├── Streams AgentEvent / ToolCall / RunRequest over RPC
                                          ├── Writes session doc (Loro CRDT)
                                          ├── Writes workspace registry doc (Loro CRDT)
                                          └── Syncs via edge Durable Objects (when enabled)
```

Quorumly Desktop's command plane uses durable command entries in the session doc. Send / steer / interrupt / respondInput are entries executed by the chat's host device, with offline sends queued in the doc. Executor is gated on chat ownership; entries are marked processed before execute; steer with no live run dispatches as the next turn.

---

### Theme System

Both implementations share the same design philosophy for themes: numbers drive layout, colors are paint.

**Quorumly for macOS:** 26 tinted-glass themes including System, Catppuccin, Dracula, Claude, and Codex. Theme definitions include semantic colors, syntax palettes, terminal colors, and optional interaction-accent overlays.

**Quorumly Desktop:** Independent light/dark resolved variants. Each variant is a completely resolved palette owned by the `theme` crate. Theme families group related variants; a `ThemeSelection` stores independent light and dark variant ids. `AccentSelection::ThemeDefault` preserves the variant's authored accent; `AccentSelection::Preset` derives a contrast-checked interaction overlay. Every variant records a recommended `SurfaceTreatment` (frost or opaque). `SurfacePreference` is a separate device-local choice that does not change appearance, theme, or accent selection.

The Quorumly Desktop built-in registry contains 30 variants across 19 families (Quorumly, VS Code, Catppuccin, Tokyo Night, Dracula, GitHub, Ayu, Gruvbox, Rosé Pine, Nord, One Dark Pro, Atom One Dark, Night Owl, Winter is Coming, Palenight, SynthWave '84, Shades of Purple, Cobalt2, Andromeda). The importer supports VS Code JSONC themes, TextMate plist files, workbench colors, semantic token colors, and terminal ANSI colors. Linked and editable sources reload explicitly; a failed reload stores a quiet warning and continues using the last successfully compiled family. Local VS Code file/package compilation and imported/linked custom families retain last-known-good persistence.

Both implementations honor `prefers-reduced-motion`. Hairline borders and bundled Geist/Geist Mono are shared presentation foundations in Quorumly Desktop.

---

### Security Model

**Checkpoint security (Quorumly for macOS):** Every diff generated by a thread is stored as a hidden git checkpoint. Checkpoints are secured with HMAC-SHA256 so they cannot be tampered with externally.

**Approval timeouts (both implementations):** Agent requests that require user approval have a configurable timeout. After the timeout expires, the request is auto-rejected (configurable behavior).

**Credential isolation (both implementations):** Provider credentials (API keys, OAuth tokens) are stored in the application settings and never logged or transmitted to any backend except the provider's own API endpoint. In Quorumly for macOS the MCP keychain layer (`MCPKeychain.swift`) keeps MCP credentials isolated from the main store.

**Crash reporting (both implementations):** Crash reports are captured locally and can be submitted. Reports include the store state scrubbed of credentials and the crash traceback.

**Auto-update (both implementations):** Updates are signed and verified before installation. The public key for signature verification is shipped with the app.

**Quorumly Desktop privacy boundary:** Local attachments remain jailed under the local upload root and are not readable through the synced attachment cache. Returning to local-only mode reopens the same local identity and data. Remote workspace file requests from trusted peers are resolved by the owning engine, which enforces workspace-relative path, containment, symlink, and write-conflict checks before touching its filesystem. `.git` remains unavailable regardless of ignored-file visibility options. Ignored-file visibility is not an authorization boundary; a remote peer may request ignored entries and then read or write them, including potentially sensitive files such as `.env`, when `includeIgnored` is enabled. Devices authenticated to the same synced account are trusted peers for remote workspace control; if those devices must no longer trust one another with the full workspace, that policy must be enforced by the owning engine for remote requests — hiding entries only in the UI is not a security control.

---

## Build and Release

### Quorumly for macOS

```bash
cd Quorumly-swift
xcodegen generate
open Quorumly.xcodeproj
```

SwiftTerm, the only dependency, is fetched by Swift Package Manager. Xcode asks once to trust its build plugin. Build is the check; there is no test target.

`scripts/package_dmg.sh` stages HiDPI window backdrop, window geometry, and the app icon into every release DMG. Load-bearing invariants: the volume name must be `Quorumly`, the background must be `/.background.tiff`, the app must be `Quorumly.app`, and the symlink must be `Applications`. Any mismatch silently breaks Finder window styling.

`scripts/release.sh` archives an Apple silicon build, signs it with Developer ID, notarizes and staples both the app and a disk image, and checks Gatekeeper. The disk image lands in `build.noindex/` (Spotlight-skipped). `scripts/publish_release.sh` publishes the release.

### Quorumly Desktop

```bash
cd Quorumly-rust
cargo build --workspace
cargo run --bin quorumly          # headed
cargo run --bin quorumly headless # headless
```

Linux packaging: `scripts/package-linux.sh` with release profile. macOS bundling: `dist/macos/` (requires a Mac to execute). Windows packaging is driven from the same `dist/` tree.

---

## Cross-Project Direction

Both implementations are independently shipped. The umbrella project aligns them on:

- The shared provider matrix in this document.
- The shared MCP catalog and transport surface.
- The shared theme philosophy (numbers drive layout, colors are paint).
- The shared security posture: local-first state, isolated credentials, signed updates.

The implementations diverge where the platforms demand it: SwiftUI vs gpui, Apple-only vs cross-platform, single-machine vs optional multi-device sync. Both stay native; neither embeds a model.

---

Copyright (c) Soumya Chakraborty. MIT License.
