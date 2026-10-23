# Changelog

All notable changes to Ensembyte are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The umbrella version tracks cross-project work. Each subproject (Ensembyte-swift,
Ensembyte-rust) keeps its own changelog for platform-specific changes.

## [1.1.10] - 2026-10-23

Ensembyte 1.1.10 brings resilient Hydra head spawning across all LLM providers, explicit user spawn intent detection, and a built-in `/hydra` slash command with direct task dispatch.

### macOS Updates (`Ensembyte-swift/`)
- **Resilient Hydra Head Spawning**: Resolved an issue where Claude Code and CLI sessions bypassed the delegation block with inline tool commands; injected clear delegation schemas and anti-inline tool instructions directly at the user-turn boundary.
- **Permissive Block Parser**: Enhanced `HydraDelegationStream` to dynamically resolve keys (`instructions`, `brief`, `description`, `title`, etc.) and tolerate language tag variations in fenced blocks (`hydra json`, `hydra:json`).
- **Slash Command & Direct Dispatch**: Added `/hydra` command autocompletion to the composer, allowing users to toggle Hydra or immediately dispatch background heads with `/hydra <task>`.
- **Explicit Spawn Recognition**: Automatically identifies delegation keywords (e.g. "spawn hydra", "spawn heads") and guides the model to delegate immediately without inline tool loops.

## [1.1.9] - 2026-10-17

Ensembyte 1.1.9 delivers native WorkOS AuthKit cloud sync integration across desktop clients, custom loopback OAuth callback routing, refreshed high-resolution brand assets, and interactive test reporting with AI assistance.

### Cross-Platform & Rust Updates (`Ensembyte-rust/`)
- **WorkOS AuthKit & User Sync Integration**: Native WorkOS AuthKit integration replacing legacy third-party endpoints with loopback OAuth callbacks (`http://127.0.0.1:27641/callback`) and dynamic authentication endpoints (`https://ensembyte.vercel.app`).
- **High-Resolution Vector Branding**: Upgraded `dist/ensembyte.svg` with embedded 1024×1024 high-resolution brand mark.
- **Thinking Shader Orb & Test Results**: Added animated thinking shader orb with multi-gradient rotating states, dynamic reasoning tier indicators, and interactive test results runner.

## [1.1.8] - 2026-10-17

Ensembyte 1.1.8 introduces an interactive Pro Diff Review system with unified/split views, word-level diff highlights, and inline feedback directly in chat, alongside intelligent auto-scrolling for active chat threads.

### macOS Updates (`Ensembyte-swift/`)
- **Interactive Pro Diff Review**: Complete native implementation of side-by-side split diff review with synced scrolling, intra-line word/token-level diff highlighting, inline commenting on diff lines, and file action cards (`Accept` / `Revert`).
- **Chat Thread Auto-Scroll**: Added smart bottom-following auto-scroll for streaming tokens, reasoning blocks, and tool executions with intelligent user scroll detection.
- **Diff Cache Management**: Real-time diff cache invalidation on file revert and expanded popover viewport (`780×580`).

## [1.1.7] - 2026-10-17

Ensembyte 1.1.7 brings integrated GitHub repository cloning directly from the welcome screen, sidebar, and menu bar, window zoom keyboard shortcuts for full-app scaling, and upgraded multi-architecture release pipelines for macOS (Apple Silicon and Intel).

### macOS Updates (`Ensembyte-swift/`)
- **GitHub Repository Cloning Integration**: Added direct "Clone from GitHub" button on the Welcome screen, quick contextual popover on the sidebar "Add project" button, and `File › Clone from GitHub…` menu command.
- **Command Palette Action**: Searchable "Clone from GitHub" command added to the Command Palette (`⌘K`).
- **AppZoom Window Menu Shortcuts**: Native `⌘+` (Zoom In), `⌘-` (Zoom Out), and `⌘0` (Actual Size) keyboard shortcuts in the Window menu.
- **Multi-Architecture Release Support**: Automated release packaging for single-architecture Apple Silicon (`arm64`) and Intel (`x86_64`) disk images.

## [1.1.6] - 2026-10-16

Ensembyte 1.1.6 introduces a full redesign of the Prompt Input controls and AI Reasoning interface, delivering an elevated effort slider with live tier gradients, pearl-white slider puck, and animated thinking shader orbs with live duration tracking.

### macOS Updates (`Ensembyte-swift/`)
- **Precision Effort Slider**: 28pt rectangular rounded track (`h-7`) with pearl-white elevated puck, drop shadow, center grip notch, and dynamic electric aura glow at Max effort.
- **Dynamic Tier Gradients**: Distinct refined palettes for Low (zinc/gray), Medium (sky blue), High (indigo), Extra High (violet), and Max (electric cyan/violet/fuchsia).
- **Extended Thinking Integration**: Added extended thinking toggle directly within the composer effort slider card.
- **Thinking Shader Orb & Live Timer**: Integrated rotating multi-gradient shader orb during reasoning, live counting timer pill ("Thinking…"), and auto-collapsing summary badge ("Thought for 12s") with expandable trail.
- **UI Alignment Refinements**: Clean vertical spacing between track and "Recommended" indicator marker, smooth light sheen wave, and edge-to-edge gradient coverage.

## [1.1.5] - 2026-10-12

Ensembyte 1.1.5 delivers critical Voice Mode ChatGPT account token refresh stability on macOS, alongside comprehensive Linux and Windows engine upgrades including native WebView2 embedded browser support, path traversal security, and 5-button mouse route navigation.

### macOS Updates (`Ensembyte-swift/`)
- **Voice Token Refresh**: Fixed voice eligibility probing by refreshing tokens on `account/read` (`refreshToken: true`). Prevents premature session timeouts and spurious `chatgptRequired` rejections when starting Voice Mode sessions.
- **Codex Voice Host Stability**: Hardened realtime connection establishment and voice catalog listing across long-running background sessions.

### Windows & Linux Updates (`Ensembyte-rust/`)
- **Native Embedded WebView2 Browser**: Added full Windows WebView2 in-app browser implementation with sanitized IPC and navigation surfaces.
- **Windows Drive & Network Path Support**: Added support for Windows drive letters (`D:\`), extended paths (`\\?\D:\`), and UNC network shares with case-insensitive root handling.
- **UNC / SMB Security**: Protected against Windows NTLM credential leaks and path traversal attacks via lexical path component jailing prior to filesystem calls.
- **5-Button Mouse Navigation**: Added Mouse 4 and Mouse 5 back/forward route history walking across desktop shell and embedded browser canvases.
- **Engine Performance**: Bounded MCP bridge runtime to 2 worker threads, offloaded chunk disk reads to `spawn_blocking`, and implemented periodic glibc malloc trimming on Linux.

## [1.1.4] - 2026-10-11

Ensembyte 1.1.4 is a major feature update delivering interactive Voice Mode with 3D fluid Orb visualization, a redesigned dynamic model picker with provider rails and mid-session switching, GitHub integration, multi-account management, automated CLI updates, system-wide zoom, and custom terminal typography.

### New Features & Capabilities
- **Interactive Voice Mode & 3D Fluid Orb** (`Ensembyte-swift/`):
  - Converse naturally using full two-way voice mode backed by `LocalDictationEngine` and real-time audio playback.
  - Interactive shader-driven 3D fluid Orb visualizer reacting dynamically to speaking, listening, and agent thinking states.
  - Hands-free composer voice dictation directly from the prompt input.
- **Redesigned Dynamic Model Picker** (`Ensembyte-swift/`):
  - Split-view layout featuring a vertical provider rail with tile highlight and active provider model counts in the header.
  - Real-time search across all installed providers and models.
  - Unlocked mid-session model and provider switching with seamless turn re-routing without session restart.
- **Multi-Account & Provider Management** (`Ensembyte-swift/`):
  - Multi-account switching per provider directly in Settings and the Usage pane.
  - Integrated CLI update checker and manager ensuring background agent binaries stay synchronized.
  - Native support for OMP provider sessions, plan limits, and usage tracking.
- **GitHub Integration & Repository Cloning** (`Ensembyte-swift/`):
  - Secure GitHub device authorization with macOS Keychain token storage.
  - In-app repository clone panel and workspace initialization.
- **Timeline, Stream & UI Enhancements** (`Ensembyte-swift/`):
  - Activity tree view providing hierarchical inspection of tool calls, command executions, and nested agent actions.
  - AppZoom scaling across all application windows.
  - Customizable terminal font selection and line heights.
  - 120 FPS timeline scrolling, stream mending, and hover preview cards.

## [1.1.3] - 2026-10-11

Ensembyte 1.1.3 brings updated welcome tour artwork and liquid glass UI rendering refinements.

### Refinements
- **Refreshed welcome tour artwork** (`Ensembyte-swift/`): Updated in-app tour walkthrough visuals across all 8 onboarding scenes with crisp, high-resolution native macOS retina assets.
- **Liquid glass & theme refinements** (`Ensembyte-swift/`, `website/`): Cleaned frosted glass rendering across theme previews and app chrome surfaces.

## [1.1.2] - 2026-10-08

Ensembyte 1.1.2 delivers major stability and performance enhancements across file tree watching, child process management, background task synchronization with Claude, and multi-chat git isolation.

### Bug fixes & Performance
- **WorkingTreeWatch freeze fix** (`Ensembyte-swift/`): Resolved a critical deadlock in file-tree watching where concurrent callers looped without suspending, eliminating intermittent app beachballs and UI freezes during agent file edits.
- **Process tree & memory management** (`Ensembyte-swift/`): Implemented recursive process-tree tracking via kernel APIs (`proc_pidinfo`, `proc_listchildpids`) ensuring child and grandchild agent processes cleanly terminate on cancellation without leaking memory or leaving orphan zombies. Added 32MB input queue and 256MB backlog safety limits.
- **Claude background task sync** (`Ensembyte-swift/`): Fixed unprompted turn synchronization when Claude Code completes background commands, and added real-time "Waiting on a background task" mini spinner indicators to the sidebar.
- **Hydra multi-chat isolation** (`Ensembyte-swift/`): Added spent-branch tracking and dedicated ref namespaces (`refs/ensembyte/sent/`, `refs/ensembyte/merged/`) to prevent cross-chat write claiming and race conditions when multiple chat threads operate concurrently.
- **Offline Antigravity guard** (`Ensembyte-swift/`): Added network reachability checks to guard headless usage queries when offline, preventing unexpected browser sign-in popups.

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
