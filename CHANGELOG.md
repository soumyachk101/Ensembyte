# Changelog

All notable changes to Ensembyte are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The umbrella version tracks cross-project work. Each subproject (Ensembyte-swift,
Ensembyte-rust) keeps its own changelog for platform-specific changes.

## [1.0.0] - 2026-10-03

### Added
- Initial unified release of Ensembyte.
- **Ensembyte for macOS** (`Ensembyte-swift/`) — native Swift 6 / SwiftUI app for
  Apple silicon on macOS 26+: multi-agent orchestration (Codex, Claude, Cursor,
  OpenCode, Grok, DeepSeek, Meta, Antigravity, and more), thread isolation in
  git worktrees, integrated terminal, turn-by-turn diff viewer, command palette,
  26 tinted-glass themes, and full MCP support.
- **Ensembyte Desktop** (`Ensembyte-rust/`) — native Rust + GPUI app for Linux
  and Windows: local-first session store, optional multi-device sync, real-time
  Markdown editor with live preview and syntax highlighting, built-in terminal,
  multi-agent harness, and Model Context Protocol (MCP) server integration.
- Unified documentation: umbrella `README.md`, `LICENSE`, `THIRD_PARTY_NOTICES.md`,
  `TRADEMARK.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `SECURITY.md`, and
  `CHANGELOG.md` in this directory.

---

Ensembyte uses [semantic versioning](https://semver.org/).
