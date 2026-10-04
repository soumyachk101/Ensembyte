# Ensembyte for macOS

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg?logo=swift)](project.yml)
[![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon%20(macOS%2026%2B)-black.svg?logo=apple)]()
[![Releases](https://img.shields.io/badge/DMG-Ensembyte-blue)](https://github.com/soumyachk101/Ensembyte/releases)

**Ensembyte for macOS** is the official native macOS desktop client for AI coding agents, handcrafted in **Swift 6 and SwiftUI** using Apple's **Liquid Glass** design language.

It connects directly to local coding agent CLIs (Claude Code, Codex, Cursor, Grok, Pi, Devin, Hermes, DeepSeek, Antigravity, and more) — running purely on your own hardware and existing subscriptions with zero middleware and zero telemetry.

> **Platform Scope:** Ensembyte-swift is **exclusively engineered for macOS** (Apple silicon / macOS 26+).
> For Windows and Linux, please use the companion Rust/GPUI client: **[Ensembyte-rust](../Ensembyte-rust)**.

---

## Highlights

- **Pure SwiftUI & Liquid Glass:** Crafted with genuine Apple AppKit and SwiftUI components, delivering responsive glass surfaces, smooth translucent vibrancy, and 26 bespoke color themes.
- **Hydra Multi-Agent Orchestration:** One lead agent plans and delegates work to up to 8 parallel heads, each operating in an isolated git worktree, automatically merged upon completion.
- **Built-In Terminal & Diff Inspector:** Embedded `SwiftTerm` terminal sessions and instant per-turn diff review with hidden git checkpoints.
- **Local Credential Security:** Seamless integration with the macOS Keychain for API keys and tokens.
- **MCP Integration:** Model Context Protocol client with preconfigured developer, filesystem, and browser tools.

---

## Installation

Official signed and notarized `.dmg` packages are hosted at:
👉 **[Ensembyte Releases](https://github.com/soumyachk101/Ensembyte/releases)**

1. Download **`Ensembyte.dmg`**.
2. Mount the disk image and drag **Ensembyte.app** into `/Applications`.
3. Launch Ensembyte from your Applications folder or Spotlight.

---

## Architecture

The macOS client strictly enforces a **four-layer, one-way dependency model**:

```
Ensembyte/
├── Core/          Models, state primitives, pure support (no dependencies on upper layers)
├── Services/      Git, persistence stores, provider adapters (depends only on Core)
├── UI/            Chrome, themes, Markdown renderer, audio, common views (depends only on Core)
└── App/           Application lifecycle, windowing, feature views, coordinators (depends on all)
```

**Rule:** A file in `Core` never reaches into `Services`, `UI`, or `App`. New capabilities are added to the lowest layer whose dependencies satisfy the requirements.

---

## Building from Source

### Requirements
- Mac with Apple Silicon (M1 / M2 / M3 / M4 or later)
- macOS Sequoia (macOS 15) or later
- Xcode 16+ with Swift 6 toolchain
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Building in Xcode
```bash
# Generate the Xcode project from project.yml
xcodegen generate

# Open the project
open Ensembyte.xcodeproj
```
Select the **Ensembyte** scheme and press **⌘B** to build or **⌘R** to run.

### Command-Line Build
```bash
xcodebuild -project Ensembyte.xcodeproj -scheme Ensembyte -configuration Debug build
```

---

## Packaging the macOS DMG

The release packaging pipeline builds a production archive, verifies code signatures, notarizes with Apple notarytool, and packages a styled DMG installer:

```bash
# Build and package the styled disk image
scripts/release.sh

# The script outputs:
# build.noindex/Ensembyte-1.0.0.dmg
```

To publish the release to the official [Ensembyte](https://github.com/soumyachk101/Ensembyte) repository:
```bash
scripts/publish_release.sh
```

---

## Contributing

1. Check open issues or start a discussion for substantial changes.
2. Follow the four-layer architecture strictly.
3. Verify that the app builds cleanly via `xcodebuild`.
4. Open a pull request against `main`.

See the umbrella [Contributing Guidelines](../CONTRIBUTING.md) and [Code of Conduct](../CODE_OF_CONDUCT.md).

---

## License

Licensed under the **MIT License**. See [LICENSE](LICENSE) for terms.

Built with pride by [Soumya Chakraborty](https://github.com/soumyachk101).
