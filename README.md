# Quorumly

**The open-source multi-agent coding client by Soumya Chakraborty.**

Quorumly is the unified open-source project that brings together two native desktop clients for driving your AI coding agents locally from your own computer. Both apps directly connect to the CLI tools you already have installed and signed in (Claude Code, Codex, Cursor, OpenCode, Grok, Pi, Devin, Hermes, DeepSeek, Antigravity, and more), so your subscriptions stay entirely yours and your code never leaves your machine.

---

## Dedicated Platform Implementations

To deliver uncompromising native speed, memory efficiency, and platform-perfect UI, Quorumly is architected into two dedicated clients:

- **[Quorumly for macOS](Quorumly-swift/)** (`Quorumly-swift`): Built in **Swift 6 and SwiftUI** with Apple's **Liquid Glass** design system, embedded terminal, and Hydra multi-agent orchestration. Exclusively crafted for **macOS** (Apple silicon / macOS 26+). Releases produce native `.dmg` installers.
- **[Quorumly Desktop](Quorumly-rust/)** (`Quorumly-rust`): Built in **Rust and GPUI** with immediate-mode GPU acceleration and optional Loro CRDT multi-device sync. Exclusively engineered for **Windows and Linux**. Releases produce Windows installers (`.exe` / `.zip`) and Linux packages (`.tar.gz` / `.AppImage` / `.deb`).

Website: [quorumly.org](https://quorumly.org) | Releases: [Quorumly Releases](https://github.com/soumyachk101/Quorumly/releases)

---

## Which App Should I Use?

| Dimension | **Quorumly for macOS** | **Quorumly Desktop** |
| --- | --- | --- |
| **Supported OS** | **macOS** (Apple silicon, macOS 26+) | **Windows & Linux** (x86_64, ARM64) |
| **Technology Stack** | Swift 6 / SwiftUI (Liquid Glass) | Rust 2024 / GPUI (GPU accelerated) |
| **Source Directory** | [`Quorumly-swift/`](Quorumly-swift/) | [`Quorumly-rust/`](Quorumly-rust/) |
| **Distribution Format** | Signed & Notarized `.dmg` | Windows `.exe` / `.zip`, Linux `.tar.gz` / `.AppImage` / `.deb` |
| **Multi-Agent Engine** | Hydra: Lead orchestrator + parallel worktree heads | Dedicated local and synced sessions |
| **Design Language** | 26 Tinted-glass themes, Apple AppKit chrome | Minimalist dark/light themes, GPUI immediate mode |
| **State & Sync** | Local-first, hidden git checkpoints | Local-first, optional Loro CRDT sync |

If you are on a Mac, use **Quorumly for macOS** for the most seamless Apple silicon experience. If you are on Windows or Linux, use **Quorumly Desktop** for instant, lightweight native execution.

---

## Key Capabilities

Both apps deliver a focused, keyboard-first environment for your agents:

- **One Workspace, Any Agent:** Project and thread sidebars, search, pinning, and per-thread runtimes. Real-time streaming of thoughts, reasoning, tool execution, terminal outputs, and file diffs.
- **Inline Permission Prompts:** Answer approval requests, tool execution dialogs, and decision questions right in the stream without switching to another terminal.
- **Diff for Every Turn:** Automated git checkpoints let you inspect precise line-by-line file modifications across each model turn.
- **Model Context Protocol (MCP):** Preloaded with MCP servers for system tools, web search, browser automation, and knowledge bases.
- **Spend & Quota Transparency:** Live token expenditure and rolling rate-limit counters keep provider costs transparent.

---

## Supported Providers & Agents

Quorumly connects to the tools on your machine. You sign in once with each CLI using your existing provider plan:

| Provider | Command Line Tool | Protocol / Transport | macOS (Swift) | Windows & Linux (Rust) |
| --- | --- | --- | :---: | :---: |
| **Claude** | `claude` | stream-json + permission prompts | ✅ | ✅ |
| **Codex** | `codex` | app-server JSON-RPC | ✅ | ✅ |
| **Cursor** | `cursor-agent` | Agent Client Protocol (ACP) | ✅ | ✅ |
| **Grok** | `grok` | Agent Client Protocol (ACP) | ✅ | ✅ |
| **Antigravity** | `agy` | stream-json headless | ✅ | ✅ |
| **Pi** | `pi` | JSONL over stdio | ✅ | ✅ |
| **OpenCode** | `opencode` | Agent Client Protocol (ACP) | ✅ | — |
| **Devin** | `devin` | local agent | — | ✅ |
| **Hermes** | `hermes` | local agent | — | ✅ |
| **DeepSeek** | `DEEPSEEK_API_KEY` | Native API (OpenAI-compatible) | ✅ | — |
| **Meta** | `MODEL_API_KEY` | Native API (Muse Spark) | ✅ | — |

---

## Repository Structure

```
Quorumly/
├── Quorumly-swift/    # Dedicated macOS Swift 6 / SwiftUI application
├── Quorumly-rust/     # Dedicated Windows & Linux Rust / GPUI application
├── website/           # Official marketing and documentation website
├── ARCHITECTURE.md    # In-depth architectural design specification
├── CONTRIBUTING.md    # Contributor guidelines and workflow
└── LICENSE            # MIT open-source license
```

---

## Open Source Contributing

Quorumly is open source under the MIT License and actively welcomes contributions.

1. **Read the Docs:** Read [`ARCHITECTURE.md`](ARCHITECTURE.md) and the README of the specific subproject you wish to develop ([`Quorumly-swift/README.md`](Quorumly-swift/README.md) or [`Quorumly-rust/README.md`](Quorumly-rust/README.md)).
2. **Open an Issue:** For new features or significant changes, open a GitHub Issue first to align on technical design.
3. **Keep PRs Focused:** Keep each pull request dedicated to a single concern (bugfix, enhancement, or refactoring).
4. **Follow Guidelines:** Adhere to our [Code of Conduct](CODE_OF_CONDUCT.md) and [Contributing Guide](CONTRIBUTING.md).

---

## Acknowledgements

Quorumly is built upon amazing open-source projects:
- **Terminal Emulation:** [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) by Miguel de Icaza (MIT License).
- **GPUI Toolkit:** [GPUI / Zed](https://github.com/zed-industries/zed) by Zed Industries (GPL / Apache 2.0).
- **CRDT Synchronization:** [Loro](https://github.com/loro-dev/loro) (MIT / Apache 2.0).
- **Working Indicators & Pulses:** Ported from [Zeron](https://github.com/zeronsh/zeron) by Wing (MIT License).

See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for complete attributions.

---

## License

This project is licensed under the **MIT License**. See [LICENSE](LICENSE) for details.

Copyright © Soumya Chakraborty ([@soumyachk101](https://github.com/soumyachk101)).
