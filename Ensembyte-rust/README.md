# Ensembyte Desktop (Windows & Linux)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Rust](https://img.shields.io/badge/Rust-1.85%2B-orange.svg?logo=rust)](Cargo.toml)
[![Platforms: Windows & Linux](https://img.shields.io/badge/Platforms-Windows%20%7C%20Linux-brightgreen.svg)]()
[![Releases](https://img.shields.io/badge/Releases-Ensembyte-blue)](https://github.com/soumyachk101/Ensembyte/releases)

**Ensembyte Desktop** is the official high-performance native desktop client for **Windows** and **Linux**, built in **Rust** with **GPUI** (GPU-accelerated immediate mode GUI).

It connects directly to the AI coding agent CLI tools you already have installed and signed in (Claude Code, Codex, Cursor, Grok, Pi, Devin, Hermes, DeepSeek, Antigravity, and more) — keeping your existing subscriptions, running entirely local, with zero middleman or telemetry.

> **Platform Note:** Ensembyte Desktop is exclusively engineered and packaged for **Windows** and **Linux**. If you are on **macOS**, use the dedicated native Swift 6 / Liquid Glass client: [Ensembyte-swift](../Ensembyte-swift).

---

## Key Highlights

- **GPU-Accelerated Rendering:** Powered by Zed's GPUI framework delivering instantaneous startup, smooth scrolling, and responsive animations (Direct3D 11 on Windows, Vulkan/Wayland/X11 on Linux).
- **Direct CLI Agent Orchestration:** Shells out to CLI agents running locally on your own machine. Conversations stream with full reasoning blocks, tool execution calls, plans, and terminal outputs.
- **Local-First & CRDT-Powered:** Session state, conversations, and workspace context are stored locally. Includes optional real-time multi-device synchronization powered by **Loro CRDTs**.
- **Model Context Protocol (MCP):** Embedded Model Context Protocol server that bridges local system tools, file discovery, and browser automations directly into your agent workflows.
- **Diff & Checkpoint System:** Built-in git checkpoints and diff viewers track changes across every assistant turn.

---

## Supported Operating Systems

| OS | Architectures | Formats / Packages |
|---|---|---|
| **Windows** | x86_64, ARM64 | Per-user installer (`.exe`), Portable (`.zip`) |
| **Linux** | x86_64, aarch64 | Standalone tarball (`.tar.gz`), AppImage, Debian package (`.deb`) |

*macOS builds and `.dmg` installers are exclusively provided by [Ensembyte-swift](../Ensembyte-swift).*

---

## Installation & Download

Pre-built binaries and official releases are available at:
👉 **[Ensembyte Releases Page](https://github.com/soumyachk101/Ensembyte/releases)**

### Windows Installation
1. Download `ensembyte-<version>-windows-x86_64-setup.exe` or portable `ensembyte-<version>-windows-x86_64.zip`.
2. Run the installer (installs into `%LOCALAPPDATA%\Programs\Ensembyte` without requiring administrator privileges).
3. Launch **Ensembyte** from the Start menu or desktop shortcut.

### Linux Installation
Download the packaged tarball or AppImage for your architecture:
```bash
# Extract and install using the included installer
tar -xzf ensembyte-<version>-linux-x86_64.tar.gz
cd ensembyte-<version>-linux-x86_64
./install.sh
```
This installs Ensembyte into `~/.ensembyte/app/` and creates desktop entries under `~/.local/share/applications/` and symlinks in `~/.local/bin/`.

---

## Building from Source

### Prerequisites

1. **Rust Toolchain:** Stable Rust (configured automatically via [`rust-toolchain.toml`](rust-toolchain.toml)).
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

2. **Linux System Dependencies:**
   On Debian / Ubuntu:
   ```bash
   sudo apt-get update
   sudo apt-get install -y \
     libxkbcommon-dev libxkbcommon-x11-dev libwayland-dev \
     libx11-dev libxcb1-dev libx11-xcb-dev \
     libfontconfig1-dev libfreetype-dev libasound2-dev \
     libvulkan-dev pkg-config cmake libwebkit2gtk-4.1-dev libjson-glib-dev
   ```
   On Fedora:
   ```bash
   sudo dnf install -y \
     libxkbcommon-devel wayland-devel libX11-devel \
     fontconfig-devel freetype-devel alsa-lib-devel \
     vulkan-loader-devel cmake webkit2gtk4.1-devel json-glib-devel
   ```

3. **Windows System Dependencies:**
   - Visual Studio 2022 with C++ Build Tools and Windows 10/11 SDK.
   - For building the installer: [Inno Setup 6](https://jrsoftware.org/isinfo.php) (`winget install JRSoftware.InnoSetup`).

### Compilation

Clone the repository and build the desktop client:
```bash
# Check the build
cargo check -p ensembyte

# Run in debug mode
cargo run -p ensembyte

# Build release binary
cargo build --release -p ensembyte
```

The compiled binary will be placed at `target/release/ensembyte` (or `target/release/ensembyte.exe` on Windows).

---

## Packaging

Automated packaging scripts produce production artifacts matching release specifications:

### Linux Package
```bash
scripts/package-linux.sh
# Generates target/package/ensembyte-<version>-linux-<arch>.tar.gz
```

### Windows Package (PowerShell)
```powershell
./scripts/package-windows.ps1 -ReleasesUrl "https://github.com/soumyachk101/Ensembyte/releases/latest/download"
# Generates target/package/ensembyte-<version>-windows-x86_64.zip and setup.exe
```

---

## Workspace Structure

```
Ensembyte-rust/
├── apps/
│   ├── ensembyte/          Main desktop executable entrypoint
│   └── landing/           Landing and marketing static site
├── crates/
│   ├── ui/                GPUI views, layouts, themes, chrome, and typography
│   ├── engine/            Runtime coordinator for agents, chats, and workspaces
│   ├── rpc/               WebSocket RPC and IPC protocol definitions
│   ├── sync/              Loro CRDT multi-device synchronization engine
│   ├── proto/             Data models and wire schemas
│   ├── mcp/               Model Context Protocol (MCP) server implementation
│   ├── doc/               Document and transcript CRDT management
│   ├── update/            In-place application auto-updater
│   └── voice/             Audio feedback and sound synthesizer
├── dist/                  Desktop launchers, icons, and Windows installer scripts
└── scripts/               Packaging, cross-compilation, and verification scripts
```

---

## Architecture & Design Documents

For deep dives into design rationale, state models, and benchmarks:
- [`docs/README.md`](docs/README.md) — Index of Architecture Decision Records (ADRs) and design plans
- [`docs/mcp.md`](docs/mcp.md) — Model Context Protocol hub design
- [`docs/theme-system.md`](docs/theme-system.md) — Color token system and theme engines
- [Root `ARCHITECTURE.md`](../ARCHITECTURE.md) — Overall Ensembyte ecosystem architecture

---

## Contributing

Contributions, bug reports, and suggestions are warmly welcomed!

1. Fork the repository and create a feature branch.
2. Verify code formatting and linting:
   ```bash
   cargo fmt --check
   cargo clippy --workspace --all-targets
   ```
3. Run tests across workspace crates:
   ```bash
   cargo test -p ensembyte
   ```
4. Submit a Pull Request describing your changes.

Please adhere to the project's [Code of Conduct](../CODE_OF_CONDUCT.md) and [Contributing Guide](../CONTRIBUTING.md).

---

## License

This project is licensed under the **MIT License**. See the [LICENSE](LICENSE) file for details.

Developed with ❤️ by [Soumya Chakraborty](https://github.com/soumyachk101).
