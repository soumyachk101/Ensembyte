# Ensembyte Roadmap

This document outlines planned work for Ensembyte. Priorities shift with user
feedback, so treat this as a working draft, not a promise. Anything labeled
**In progress** is currently being worked on.

## Short Term

- **Stabilize the Rust desktop client** — In progress
  - Multi-agent harness parity with the macOS client
  - Performance parity with the Swift app on mid-range hardware
  - Synced sessions on par with local sessions

- **Reduce friction for first-time contributors** — In progress
  - Quick Start in README
  - Issue and PR templates
  - CI badges and clear build status

- **Strengthen the supply chain** — In progress
  - `cargo deny` for license compliance and advisory scanning
  - `cargo clippy --all-targets -- -D warnings` enforced in CI
  - GitHub Actions pinned to commit SHAs
  - Dependabot for automated dependency updates

## Medium Term

- **Documentation site**
  - Render `docs/` (Rust) and the Swift architecture guide to a public site
  - User guide, not just contributor guide
  - Search across the docs

- **Provider matrix coverage**
  - Bring all providers to feature parity on the Rust client
  - Add OAuth flows where providers support them

- **Accessibility audit**
  - Keyboard navigation in every pane
  - VoiceOver / screen reader support on macOS
  - High-contrast themes for users who need them

- **i18n / l10n**
  - Extract strings into resources
  - Crowd-sourced translations via the website

## Long Term

- **Mobile clients**
  - The `mobile` crate exists; ship a usable build
  - Sync with desktop via the existing CRDT layer

- **Plugin system**
  - Documented extension API for themes, providers, and tool integrations
  - Sandboxing model for untrusted extensions

- **Hosted sync**
  - The edge sync (Cloudflare Durable Objects) is built; make it easy for users
    to bring their own account, or default to local-only

## Backlog

Items in the backlog are good ideas that no one has committed to yet.
Contributions welcome.

- Theming: import/export theme packs
- Diff navigation: side-by-side file diff view in the streaming pane
- Audio cues: configurable per-event
- Agent memory: searchable history of decisions across all threads
- Provider health: a small panel showing which agent CLIs are signed in and healthy

## How to influence the roadmap

- Open an issue with a clear problem statement
- Tag it `enhancement` (and the labels for the client it applies to)
- If you want to work on it, leave a comment so we can coordinate

## Not on the roadmap

- Web-based version. Ensembyte is a native desktop client; the website exists
  for marketing and documentation, not as a fallback app.
- Hosting providers. The app drives CLIs you install yourself; we do not
  proxy traffic to LLM providers.
