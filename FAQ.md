# Ensembyte FAQ

## General

**Is Ensembyte really open source?**
Yes. Both clients are released under the MIT License. The full source code is
available in this repository.

**Does Ensembyte collect any telemetry?**
No. Everything runs locally. No analytics, no crash reporters, no phone-home.
Your code and your subscriptions stay on your machine.

**Which platforms are supported?**
- **macOS:** Apple Silicon (M1/M2/M3/M4), macOS 26+
- **Windows:** x86_64
- **Linux:** x86_64, ARM64

## Providers

**Which AI coding agents does Ensembyte support?**
Claude, Codex, Cursor, OpenCode, Grok, Pi, Devin, Hermes, DeepSeek, Antigravity,
and any OpenAI-compatible API. See the README for the full list.

**Do I need to subscribe to every provider?**
No. Install and sign into the CLIs you already use. Ensembyte detects what's
available on your machine.

**Can I use Ensembyte without any provider?**
Yes — the UI works standalone. You just won't have an agent to drive until you
connect one.

## Development

**Why two separate implementations (Swift + Rust)?**
Native performance. SwiftUI on Apple Silicon and GPUI on Windows/Linux give
platform-perfect speed and look-and-feel. A single Electron-based codebase
cannot match either.

**How do I contribute?**
See [CONTRIBUTING.md](CONTRIBUTING.md). The short version: open an issue first,
keep PRs focused, and follow the architecture layering rules.

**Why worktrees on macOS?**
The Hydra multi-agent system fires off parallel agents, each in its own git
worktree. This prevents merge conflicts and keeps the main branch clean.
See [AGENTS.md](AGENTS.md).

**Can I build both clients from the same machine?**
The Swift client requires macOS with Xcode 16. The Rust client can be built on
Linux, Windows, or macOS with the Rust 2024 toolchain.

## Sync

**What is the sync feature?**
The Rust client supports multi-device sync via Loro CRDT and Cloudflare Durable
Objects. It's opt-in and local-first — your data is still yours.

**Do I need to set up a Cloudflare account?**
No. Sync is optional. The app works entirely offline by default.

## Troubleshooting

**The app won't launch after installation.**
Make sure you're on a supported OS version. On macOS, check that you're on
Apple Silicon and macOS 26+. On Windows, ensure the VC++ runtime is installed.

**My agent CLI isn't detected.**
Ensure the CLI is in your `PATH`. On macOS, you may need to grant Terminal
permissions in System Settings > Privacy & Security.

**Build fails on Linux.**
Install the system dependencies listed in CONTRIBUTING.md. Missing `libxkbcommon`
or `libvulkan-dev` are the most common causes.
