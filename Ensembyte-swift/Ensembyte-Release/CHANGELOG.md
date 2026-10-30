# Changelog

All notable changes to Ensembyte for macOS are documented here, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are the release tags without the `v`.

## [1.1.14] - 2026-10-30

### New features
- Thread Working Modes (Single Agent, Heads in Panel, Heads in Thread): Support three working modes per thread: single agent (solo work without secondary heads), heads in floating panel, or heads nested as child threads in the sidebar.
- Single-Agent Solo Mode: Enforces direct in-thread work with strict solo prompts instructing the model not to open hydra delegation blocks.
- Thread Tasks & Artifacts Section (`ThreadTaskSection`): Bottom collapsible sheet with dedicated Todos (interactive checklist) and Artifacts (syntax-highlighted code diff hunks, markdown, and image previews) tabs.
- Chat Header Panels Menu: Added a Panels capsule menu in the conversation header to quickly toggle between Todos and Artifacts.

### Bug fixes
- Header Title Overflow: Added an elastic spacer between thread titles and right-hand action capsules, ensuring long branch and thread titles truncate cleanly with an ellipsis without pushing buttons off-screen.

### Refinements
- Provider Solo Flag Propagation: Passes the solo thread mode flag directly into ACP, Codex, Command Code, and OpenAI-compatible provider sessions.
- Settings Working Mode Card: Visual picker in Hydra Settings to easily view and configure the active thread's working mode.

## [1.1.13] - 2026-10-30

### New features
- Native In-App Web Browser: Integrated a full-bleed web browser column beside the conversation thread powered by Apple's `WebKit` (`WKWebView`), featuring multi-tab management, tab switching, and custom glass theme styling.
- Live Artifact Cards Across Providers: Dynamically streams newly written or modified files as interactive preview cards directly in the timeline across ACP, Codex, Command Code, and OpenAI-compatible provider sessions.
- In-Turn Artifact Upsert: Rewrites the turn's active artifact card in place as files are edited or created, providing instant visual feedback without stacking duplicate rows.
- Address Bar & Normalization: Built-in address field with automatic scheme normalization (`http://` for local loopback development servers such as `localhost:3000`, `https://` for external web domains) and inline address validation.
- Chat Link Routing: Markdown web links clicked within conversation turns now seamlessly open directly inside the in-app browser without losing development context.
- Browser Keyboard Shortcuts: Added a dedicated Browser shortcuts section (`⇧⌘B` to toggle browser, `⌘L` to focus address bar, `⌘T` for new tab, `⇧⌘W` to close tab, `⌘[` / `⌘]` for history, and `⇧⌘R` to reload).

### Bug fixes
- Strict URL Scheme Policy: Added `BrowserURLPolicy` blocking embedded credentials (`user:pass@host`), invalid escape sequences, and unsupported protocol schemes to protect against link exploits.
- Loopback Dev Server Detection: Fixed port parsing on bare authority inputs so local development URLs resolve correctly to HTTP loopback rather than failing hostname lookup.

### Refinements
- Flexible Hydra Head Workspaces: Configure where parallel Hydra heads execute—either directly nested in-chat or organized in a dedicated floating panel.
- Browser Keyboard Shortcut Customization: Integrated the Browser shortcut command group into Settings with customizable hotkeys and quick reference labels.
- External Browser Handoff: Added a one-click button in the browser toolbar to instantly open the active page in the macOS system default browser.

## [1.1.12] - 2026-10-27

### New features
- Non-Interrupting Prompt Submission: Pressing Return in the composer while the lead agent is actively working now queues the draft as a follow-up prompt rather than interrupting the turn. Stopping the agent remains dedicated to the Stop button and `Esc` key.
- Hydra Head Dispatch on Return: When the opt-in "always dispatch to heads" setting is active, pressing Return while the lead is busy immediately routes the draft to a new parallel Hydra worker head.

### Bug fixes
- App Launch Queue Resumption: Queued follow-up prompts restored from persistent thread state at app launch now automatically flush and begin execution on an idle lead agent, even if the prior session was interrupted or aborted upon quitting.
- Queue Drain Resilience: Follow-up queues now reliably continue execution following completed or errored turns, preventing queued prompts from remaining stuck when a turn encounters an upstream model error.

### Refinements
- Refined Queue Defaults: Disabled automatic head queueing by default (`hydraQueueHeads = false`) for direct, predictable thread execution.
- Documentation & License Attribution: Updated upstream project credits and license notices across 3D Orb, Voice Controller, Stream Veil, and Working Indicators.

## [1.1.11] - 2026-10-26

### New features
- Native Unit Test Suite (`EnsembyteCoreTests`): Added complete native unit testing bundle for macOS covering foundational models and utilities (`StdioFramer`, `ThreadContinuation`, `JSONValue`, `ISO8601`, `HydraCookbook`).

### Bug fixes
- StdioFramer Memory Leak Prevention: Fixed buffer retention on oversized frames (>16MB) by resetting internal framing state on failure (`failTooLarge`), preventing memory bloat and stale buffer poisoning.
- Hydra Regex Performance & Hang Fix: Statically cached compiled regexes in `HydraPrompts` with fast string checks, eliminating dynamic regex re-parsing and resolving UI/thread hangs during context continuation processing.
- Continuation Ordering & Budget Preservation: Ensured forwarded threads retain the initial user request at the context boundary, cleanly positioning omission markers when context budget constraints require intermediate turn trimming.

## [1.1.10] - 2026-10-23

### New features
- Slash Command Autocompletion: Integrated `/hydra` into the composer slash command palette with quick toggling and instant status indications.
- Direct Task Dispatch: Fast-path delegation via `/hydra <task>` or `/spawn <task>` to immediately assign tasks directly to background worker heads without roundtrips.

### Bug fixes
- Universal Provider Spawning: Fixed Claude Code and other tool-calling providers bypassing delegation blocks by enforcing strict anti-inline tool execution instructions when delegating.
- Resilient Block Parsing: Relaxed parser key requirements in `HydraDelegationStream` to seamlessly handle `instructions`, `instruction`, `brief`, `description`, `title`, and `task_name` variations emitted by different LLMs.
- Flexible Fence Format Matching: Broadened delegation fence regex matching to accept info string variations (`hydra json`, `json:hydra`, `hydra:json`) and carriage-return delimiters.
- Explicit User Intent Detection: Automatically detects user delegation requests (e.g., "spawn hydra", "spawn heads") and injects explicit delegation prompts into the model turn.

## [1.1.9] - 2026-10-17

### New features
- WorkOS AuthKit Cloud Sync: Native authentication integration with loopback OAuth callbacks (`http://127.0.0.1:27641/callback`) and edge authentication routing.
- High-Resolution Branding: Updated application iconography and vector assets for high-DPI Retina displays.

## [1.1.8] - 2026-10-17

### New features
- Interactive Split & Unified Diff Review: Side-by-side diff review with synced scrolling, intra-line word/token-level diff highlighting, inline commenting on diff lines, and file action cards (`Accept` / `Revert`).
- Chat Thread Auto-Scroll: Intelligent bottom-following auto-scroll for streaming tokens, reasoning blocks, and tool executions with smart user scroll detection.

### Bug fixes
- Diff Cache Invalidation: Real-time diff cache invalidation on file revert and expanded popover viewport (`780×580`).

## [1.1.7] - 2026-10-17

### New features
- GitHub Repository Cloning: Added direct "Clone from GitHub" button on the Welcome screen, quick contextual popover on the sidebar "Add project" button, and `File › Clone from GitHub…` menu command.
- Command Palette Action: Searchable "Clone from GitHub" command in the Command Palette (`⌘K`).
- AppZoom Window Menu Shortcuts: Native `⌘+` (Zoom In), `⌘-` (Zoom Out), and `⌘0` (Actual Size) keyboard shortcuts in the Window menu.

## [1.1.6] - 2026-10-16

### New features
- Precision Effort Slider: Redesigned 28pt rectangular rounded track (`h-7`) with pearl-white elevated puck, drop shadow, center grip notch, and dynamic electric aura glow at Max effort.
- Dynamic Tier Gradients: Distinct refined palettes for Low (zinc/gray), Medium (sky blue), High (indigo), Extra High (violet), and Max (electric cyan/violet/fuchsia).
- Extended Thinking Integration: Added extended thinking toggle directly within the composer effort slider card.
- Thinking Shader Orb & Live Timer: Integrated rotating multi-gradient shader orb during reasoning, live counting timer pill ("Thinking…"), and auto-collapsing summary badge ("Thought for 12s").

## [1.1.5] - 2026-10-12

### Bug fixes
- Voice Token Refresh: Fixed voice eligibility probing by refreshing tokens on `account/read` (`refreshToken: true`), preventing premature session timeouts and spurious `chatgptRequired` rejections when starting Voice Mode sessions.
- Codex Voice Host Stability: Hardened realtime connection establishment and voice catalog listing across long-running background sessions.

## [1.1.4] - 2026-10-11

### New features
- Interactive Voice Mode & 3D Fluid Orb: Natural two-way voice conversations backed by `LocalDictationEngine` and real-time audio playback with interactive shader-driven 3D fluid Orb visualizer.
- Dynamic Model Picker: Split-view layout featuring a vertical provider rail with tile highlight and active provider model counts in the header.
- Multi-Account & Provider Management: Multi-account switching per provider directly in Settings and the Usage pane.
- GitHub Integration: Secure GitHub device authorization with macOS Keychain token storage and in-app repository clone panel.

## [1.1.3] - 2026-10-11

### Refinements
- Welcome tour artwork updates and liquid glass UI rendering refinements.

## [1.1.2] - 2026-10-08

### Bug fixes
- Fixed window frame positioning on multi-monitor setups and restored window state persistence across restarts.

## [1.1.1] - 2026-10-07

### Bug fixes
- Fixed model temperature and sampling parameters passing to background Claude CLI sessions.

## [1.1.0] - 2026-10-06

### New features
- Hydra multi-agent orchestration architecture allowing parallel background subagent execution.

## [1.0.1] - 2026-10-04

### Bug fixes
- Fix installer DMG window background displaying legacy project branding.

## [1.0.0] - 2026-10-03

Initial public release of Ensembyte for macOS: a high-performance native desktop app for coding agents. Apple silicon, macOS 26 or later.

### New features
- Multi-Agent Orchestration: Codex, Claude, Cursor, OpenCode, Grok, DeepSeek, Meta, Devin, and Antigravity in unified threads.
- Real-Time Streaming UI: Inline approval tabs, interactive prompts, and permission requests.
- Thread Isolation: Dedicated git worktree per thread so parallel agents never touch the same checkout.
- Integrated Terminal: Fast, low-latency native terminal attached under every thread.
- Turn-by-Turn Diff Viewer: Rich file inspection and side-by-side reviews for every agent turn.
- Command Palette: Instant fuzzy navigation across all projects, threads, and actions in one keystroke.
- Tinted-Glass Themes: 26 light and dark themes including Catppuccin, Dracula, Tokyo Night, Nord, Gruvbox, and Solarized.
- Model Context Protocol (MCP): Complete support for stdio and remote MCP servers, tools, and resources.
