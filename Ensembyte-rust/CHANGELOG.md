# Changelog

All notable changes to Ensembyte (Rust Core & Desktop) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.12] - 2026-10-27

### Added
- **Interactive Pull Request Workspace (`crates/ui`)**: Built-in GitHub Pull Request inspection surface with side-by-side diffs, code review commenting, PR destination switching, draft status detection, and shell handoff flows.
- **Native Two-Way Voice Mode & Stage (`crates/voice`, `crates/voice-media`, `crates/voice-session`)**: Low-latency voice interaction pipeline with WebRTC SDP audio streaming, live transcript captioning, and voice stage visualizer.
- **3D Fluid Thinking Shader Orb (`crates/orb`, `crates/ui/src/orb`)**: GPUI-accelerated animated thinking shader orb with dynamic multi-gradient state transitions across listening, speaking, and reasoning modes.
- **LaTeX Math Rendering Engine (`crates/zatex`, `ui/src/markdown/math.rs`)**: High-performance mathematical equation parsing and KaTeX-compatible rendering in markdown chat turns.
- **Mermaid Diagram Acceleration & Caching (`ui/src/markdown/mermaid_cache.rs`)**: Persistent caching layer for fast rendering of Mermaid flowcharts, sequence diagrams, and state diagrams.
- **Worktree Management & Cloud/Billing Settings**: Native Git worktree isolation controls, session branching, and WorkOS cloud sync account management views.
- **Notification Subsystem (`crates/notify`) & System Sound Cues**: Cross-platform desktop notifications and bundled audio cues (`voice-start.wav`, `voice-end.wav`).

## [1.1.11] - 2026-10-26

### Security & Engine
- **Workspace Secret Denylist & Path Protection**: Unconditional path filtering for `.env`, `.env.*`, `*.pem`, `id_*`, `credentials`, `*.key`, `*.p12`, and keystores across reads, writes, mutations, directory listings, and searches.
- **Diff Sync Secret Leak Prevention**: Untracked patch captures in the engine now strictly filter denylisted secret files, ensuring sensitive keys and credentials are never captured or broadcast across synced peers.
- **Diff Sync Repair Throttling**: Throttled full-tree git diff re-captures with a 60-second minimum interval (`REPAIR_MIN_INTERVAL`) and genuine filesystem watch event triggers, slashing background CPU usage.
- **PTY Session Reaper TTL**: Exited terminal processes and inactive replay buffers are reliably swept following TTL expiration.
- **CI Cargo Deny Audit**: Automated license compliance and security vulnerability advisory checks across the Rust workspace in CI.

## [1.1.10] - 2026-10-23

### Security & IPC
- **Engine IPC Token Verification**: Cryptographic IPC authentication token checking on all local loopback RPC channels, preventing unauthorized local process communication.

## [1.1.9] - 2026-10-17

### Added
- **WorkOS AuthKit & Cloud Sync**: Complete custom WorkOS AuthKit integration for cloud synchronization with loopback callback server (`http://127.0.0.1:27641/callback`) and edge authentication routing.
- **High-Resolution Vector Branding**: Updated `dist/ensembyte.svg` with embedded 1024×1024 high-resolution brand icon for crisp rendering on high-DPI displays.
- **Thinking Shader Orb & Interactive Test Results**: Added interactive test results runner, motion loaders with multi-gradient shader orbs, and reasoning tier indicators in transcript views.

## [1.1.5] - 2026-10-12

### Added
- Native embedded Windows WebView2 in-app browser implementation (`windows_webview.rs`).
- Full Windows drive path navigation (`D:\`, `\\?\D:\`, UNC shares, case-insensitivity) in project and folder pickers.
- 5-button mouse route history navigation (Mouse 4 and Mouse 5) across shell and browser view surfaces.
- Fallback from disabled Git push URLs (`DISABLED--push-...`) to fetch URLs.

### Security & Performance
- UNC / SMB path traversal and NTLM credential leak protection using lexical component jailing prior to filesystem calls.
- Offloaded file chunk reads to Tokio `spawn_blocking` to prevent worker thread starvation.
- Bounded MCP bridge runtime to 2 worker threads.
- Linux glibc malloc arena periodic trimming to reclaim resident heap memory in long-running headless engine processes.
- Hardened headless engine IPC and browser test retry loops.

## [1.0.0] - 2026-10-03

### Added
- Initial public release of Ensembyte (Rust Core & Desktop).
- Control coding agents (Claude Code, Codex, Cursor, Antigravity, etc.) locally.
- High-performance native Rust desktop application powered by GPUI.
- Real-time Markdown editor with live preview and syntax highlighting.
- Built-in terminal emulation and command runner.
- Multi-agent harness support and local-first session store.
- Model Context Protocol (MCP) server integration.

[1.1.12]: https://github.com/soumyachk101/Ensembyte/releases/tag/v1.1.12
[1.1.11]: https://github.com/soumyachk101/Ensembyte/releases/tag/v1.1.11
[1.1.10]: https://github.com/soumyachk101/Ensembyte/releases/tag/v1.1.10
[1.1.9]: https://github.com/soumyachk101/Ensembyte/releases/tag/v1.1.9
[1.1.5]: https://github.com/soumyachk101/Ensembyte/releases/tag/v1.1.5
[1.0.0]: https://github.com/soumyachk101/Ensembyte/releases/tag/v1.0.0
