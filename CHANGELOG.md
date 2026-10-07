# Changelog

All notable changes to Ensembyte are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The umbrella version tracks cross-project work. Each subproject (Ensembyte-swift,
Ensembyte-rust) keeps its own changelog for platform-specific changes.

## [1.1.1] - 2026-10-07

Ensembyte 1.1.1 updates the default working line style to a clean line, improves Hydra thread-mode status indicators and animations, and introduces dynamic platform adaptation on the website.

### New features
- **Working line default** (`Ensembyte-swift/`): Changed the default working line style in Conversation settings to a clean line ("Line") instead of "Card".
- **Hydra thread-mode indicators** (`Ensembyte-swift/`): Live rotating working vocabulary ticker, animated mini thinking spinners, persona glyphs, and smooth spring physics transitions for child heads in the sidebar.
- **Dynamic platform landing page** (`website/`): Website now automatically detects the user's operating system (macOS, Windows, Linux) and dynamically updates platform highlights, hero text, and call-to-actions.

### Bug fixes
- Stabilized Swift CodeQL build workflow and updated codeql-action to v4.
- Resolved Rust clippy warnings and restored backward-compatible environment variable fallbacks.

## [1.1.0] - 2026-10-06

Ensembyte 1.1.0 introduces Hydra Thread View to the sidebar and live status glyphs for child heads.

### New features
- **Hydra Thread View** (`Ensembyte-swift/`): Hydra heads can now run in a new dedicated thread on the sidebar instead of a floating panel. Right-click any lead thread with Hydra enabled and choose "Switch to Thread View" to migrate heads into individual sidebar rows with full status glyphs. Switch back to floating panel mode anytime from the same menu.
- **Head row status** (`Ensembyte-swift/`): Each Hydra head now shows its live status glyph (thinking, done, error) directly in its sidebar row, matching the floating panel indicator.

### Bug fixes
- Fixed sidebar layout for threads with many Hydra heads in thread mode.

## [1.0.1] - 2026-10-04

### Fixed
- **Ensembyte for macOS** (`Ensembyte-swift/`): Fixed installer DMG background styling and wordmark.

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
