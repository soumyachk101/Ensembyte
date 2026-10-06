# Contributing to Ensembyte

Thank you for your interest in contributing to Ensembyte. This guide covers
project setup, what makes a good pull request, and the conventions that keep
two native implementations — Swift (macOS) and Rust (Windows/Linux) — working
well together.

## Before You Start

- For anything larger than a focused bug fix, open an issue or draft PR first
  so the maintainers can align on the approach before you invest significant effort.
- Keep a pull request to **one concern**. A bug fix, a refactor, and a new
  feature are three separate PRs.
- Read the architecture and domain documentation for the implementation you
  are working on. The Swift app keeps context in `AGENTS.md`; the Rust app
  keeps it in `CONTEXT.md` and `docs/`.

## Developer Certificate of Origin

By contributing to Ensembyte, you certify that:

> You have the right to submit your work under the MIT License.
> You are granting Soumya Chakraborty and Ensembyte Contributors a license
> to use your contributions under the same terms.
> You agree that your contributions may be relicensed under future
> compatible open source licenses if the project changes license.

This is a standard DCO (Developer Certificate of Origin). You do not need to
sign anything physically — opening a pull request constitutes your agreement.

## Project Setup

Ensembyte ships as two implementations under one umbrella. Set up only the
one you intend to change.

### Swift app (macOS only)

The Swift app targets macOS (Apple silicon, macOS 26+) and requires Xcode with
the Swift toolchain.

- Open `Ensembyte-swift/Ensembyte.xcodeproj` in Xcode.
- Select the `Ensembyte` scheme and build with Cmd-B.
- Use `scripts/quick_run.sh` to build and launch from the terminal.

All edits, builds, and test runs should be performed inside a git worktree.
See [AGENTS.md](AGENTS.md) for the required workflow.

### Rust app (Windows & Linux)

The toolchain is pinned by [`rust-toolchain.toml`](Ensembyte-rust/rust-toolchain.toml)
(stable, with `rustfmt` and `clippy`).

**Linux** requires the system libraries listed in the CI configuration:

```sh
sudo apt-get install -y libxkbcommon-dev libxkbcommon-x11-dev libwayland-dev \
  libx11-dev libxcb1-dev libx11-xcb-dev libfontconfig1-dev libfreetype-dev \
  libasound2-dev libvulkan-dev pkg-config cmake libwebkit2gtk-4.1-dev libjson-glib-dev
```

**Windows** setup is documented in
[docs/reference/windows-development.md](Ensembyte-rust/docs/reference/windows-development.md).

Build and run with:

```sh
cargo run -p ensembyte
```

#### Running a dev build alongside an installed app

An installed daemon holds the default data directory and IPC port. Give your
dev build its own so they never share state:

```sh
ENSEMBYTE_DATA_DIR=~/.ensembyte-dev ENSEMBYTE_IPC_PORT=27700 cargo run -p ensembyte
```

Useful environment variables for testing without a real agent:

| Variable | Effect |
| --- | --- |
| `ORBIT_HARNESS=mock` | Offers the mock harness with canned turns |
| `ORBIT_MOCK_SUBAGENT=1` | Mock turns spawn subagents |
| `ORBIT_MOCK_THINKING=1` | Mock turns include markdown-heavy thinking |
| `ORBIT_MOCK_TODO=1` | Mock turns walk through an 8-item checklist |
| `ORBIT_MOCK_DELAY_MS=900` | Slow down mock turns for visual inspection |

## Tests

### Swift app

There is no formal test suite. The build itself is the verification:

```sh
xcodebuild -project Ensembyte-swift/Ensembyte.xcodeproj -scheme Ensembyte -configuration Debug build
```

### Rust app

Run the suites for the crates you touched before opening a PR. These mirror CI:

```sh
cargo test --locked -p ensembyte-ui --lib -- --test-threads=1
cargo test --locked -p ensembyte-engine --lib
cargo test --locked -p ensembyte-harness            # includes tests/ fixtures
cargo test --locked -p ensembyte-sync --lib
cargo test --locked -p ensembyte-preview
```

Key principles:

- CI does not cover every crate on every platform. For engine, harness, and
  sync changes, your local run is the gate — state in the PR what you ran.
- Every bug fix comes with a test that fails without the fix. Every behavior
  change updates or adds the tests that pin it.
- Tests must be deterministic and offline: no real network, no real agent
  CLIs, no reliance on your home directory. Use in-memory clients, fixtures
  under `tests/`, and temp directories.

## Code Standards

- Match the surrounding code: its naming, its idioms, and its comment density.
  Comments explain **why**, not what.
- For the Rust app, `cargo clippy --all-targets` should introduce no new
  warnings in code you touched.
- For the Rust app, format only your own changes. Parts of the tree are not
  rustfmt-clean, and whole-file reformatting buries the real diff. Drop
  formatting-only hunks in code you didn't otherwise touch.
- Do not add a dependency without explaining why in the PR. Dependencies ship
  to every user's machine.
- Do not bump the version. Releases are cut by maintainers; the version lives
  only in `[workspace.package]` in `Cargo.toml` for the Rust app, or in the
  appropriate project file for the Swift app.

### Cross-version compatibility

Ensembyte runs on multiple devices simultaneously, and they update independently.
A UI may talk to an older backend, and a chat may be hosted on a remote device
running an older engine. Therefore:

- New fields on wire and document types must be optional or `#[serde(default)]`.
  Older peers must still parse newer frames, and newer code must accept frames
  without the new field.
- New behavior that needs the other side's cooperation is gated on a capability
  or a device version check. Features degrade when a peer lacks them; they don't fail.
- Never rename or repurpose persisted keys, RPC method names, or document
  fields. Add new ones instead.

### Agent harnesses

- New harness integrations follow the existing drivers in the app's harness
  module. Installs are explicit user actions and are documented in the relevant
  harness README.
- Only drive agent CLIs in ways their terms of service allow.

## UI Changes

- Reuse the app's existing idioms exactly: rows, menus, seams, hover
  treatments, empty states. If something similar already exists, copy it.
  Do not invent new visual elements as polish.
- Do what the change calls for and nothing more. Unrequested restyling of
  nearby UI will be reverted in review.
- Check light and dark mode, frosted and opaque surfaces. Hover and selection
  on glass lift toward white, never a dark wash.
- Animations use the shared motion kit so they match the rest of the app.

## Pull Requests

**Title:** a short imperative summary, for example:
`Explorer: newest subagents first`

**Description:** two required sections.

- **Summary:** what changed and why, in a few bullets. Call out anything
  reviewers should look at closely — compatibility concerns, migrations,
  or intentional behavior changes.
- **Test plan:** the tests you added and the suites you ran, as a checklist.
  List manual checks you did, and any you didn't.

**Screenshots are required for every visible change:**

- Show the new state, and a before/after for changes to existing UI. Include
  light and dark mode when colors or surfaces are involved. Use a short
  recording for animation, drag, or scrolling changes.
- Drag images into the PR description so GitHub hosts them as attachments.
  **Never commit screenshots to the repository** for a PR.
- Redact personal data before uploading: email addresses, account names,
  tokens, private repo names, and home-directory paths. Pixelate them.

**Keep it reviewable:**

- Keep the branch mergeable with `main`. PRs are squash-merged, so the PR
  title and description become the commit.
- Respond to review by pushing new commits rather than force-pushing over
  history the reviewer already read.
- CI must pass, or the failure must be a known flake that you name in the PR.

## Security

- Never commit secrets, tokens, or real account data — including in fixtures,
  screenshots, and logs.
- Code that spawns processes, handles credentials, or opens network listeners
  receives extra scrutiny in review. Explain in the PR why it needs to exist.
- To report a security vulnerability, see [SECURITY.md](SECURITY.md).

## License

Ensembyte is MIT licensed. See [LICENSE](LICENSE) for full terms.

By contributing, you agree that your contributions are licensed under the
same terms — see the Developer Certificate of Origin above.

Copyright (c) 2026 Soumya Chakraborty and Ensembyte Contributors
