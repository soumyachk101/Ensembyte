# Changelog

All notable changes to Ensembyte are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.0.0]: https://github.com/soumyachk101/Ensembyte/releases/tag/v1.0.0
