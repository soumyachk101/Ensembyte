# Contributing to Quorumly

Thanks for helping build Quorumly. This guide covers how to set up, what a
good pull request looks like, and the handful of rules that keep a
local-first, multi-device, multi-platform app working across versions.

## Before you start

- For anything larger than a focused fix, open an issue or draft PR first
  so the approach can be agreed before you invest in it.
- Keep a pull request to one concern. A bug fix, a refactor, and a new
  feature are three PRs.
- Read the architecture and domain documentation for the implementation
  you are working on. The Swift app keeps context in `AGENTS.md`; the
  Rust app keeps it in `CONTEXT.md` and `docs/`.

## Developer Certificate of Origin

By contributing, you certify that:

> You have the right to submit your work under the MIT License.
> You are granting Soumya Chakraborty and Quorumly Contributors a license
> to use your contributions under the same terms.
> You agree that your contributions may be relicensed under future
> compatible open source licenses if the project changes license.

This is a standard DCO (Developer Certificate of Origin) — it protects
both you and the project. You do not need to sign anything; submitting a
PR constitutes your agreement.

## Setup

Quorumly ships as two implementations under one umbrella. Set up only
the one you intend to change.

### Swift app (macOS only)

The Swift app targets macOS only (Apple silicon / macOS 26+) and requires Xcode with the Swift
toolchain.

- Open `Quorumly-swift/Quorumly.xcodeproj` in Xcode.
- Select the `Quorumly` scheme and build (Cmd-B).
- Use `scripts/quick_run.sh` to build and launch the app from the
  terminal.

All edits, builds, and test runs should be performed inside a git
worktree (see [AGENTS.md](AGENTS.md)), never in the main checkout.

### Rust app (Windows & Linux)

The toolchain is pinned by
[`rust-toolchain.toml`](Quorumly-rust/rust-toolchain.toml) (stable, with
`rustfmt` and `clippy`).

**Linux** needs the GPUI system libraries CI installs:

```sh
sudo apt-get install -y libxkbcommon-dev libxkbcommon-x11-dev libwayland-dev \
  libx11-dev libxcb1-dev libx11-xcb-dev libfontconfig1-dev libfreetype-dev \
  libasound2-dev libvulkan-dev pkg-config cmake libwebkit2gtk-4.1-dev libjson-glib-dev
```

**Windows** is covered in
[docs/reference/windows-development.md](Quorumly-rust/docs/reference/windows-development.md).

Build and run the app with:

```sh
cargo run -p quorumly
```

#### Running a dev build next to an installed app

An installed daemon holds the default data directory and IPC port. Give
your dev build its own so the two never share state:

```sh
QUORUMLY_DATA_DIR=~/.quorumly-dev QUORUMLY_IPC_PORT=27700 cargo run -p quorumly
```

Useful knobs for exercising the UI without a real agent or account:

| Variable | Effect |
| --- | --- |
| `ORBIT_HARNESS=mock` | Offers the mock harness, which streams canned turns |
| `ORBIT_MOCK_SUBAGENT=1` | Mock turns spawn subagents |
| `ORBIT_MOCK_THINKING=1` | Mock turns include markdown-heavy thinking |
| `ORBIT_MOCK_TODO=1` | Mock turns work through an 8-item checklist (pair with `ORBIT_MOCK_DELAY_MS=900` to watch the todo panel) |

## Tests

### Swift app

There is no formal test suite. The build itself is the check:

```sh
xcodebuild -project Quorumly-swift/Quorumly.xcodeproj -scheme Quorumly -configuration Debug build
```

### Rust app

Run the suites for the crates you touched before opening a PR. These
mirror CI:

```sh
cargo test --locked -p orbit-ui --lib -- --test-threads=1
cargo test --locked -p orbit-engine --lib
cargo test --locked -p orbit-harness            # includes tests/ fixtures, not just --lib
cargo test --locked -p orbit-sync --lib
cargo test --locked -p orbit-preview
```

- CI does not cover every crate on every platform. For engine, harness,
  and sync changes, the local suite is the gate, so say in the PR what
  you ran.
- Every bug fix comes with a test that fails without the fix. Every
  behavior change updates or adds the tests that pin it.
- Tests must be deterministic and offline: no real network, no real
  agent CLIs, no reliance on your home directory. Use in-memory clients,
  fixtures under `tests/`, and temp dirs.
- A catalog or protocol change often touches both `--lib` tests and
  integration fixtures under `crates/*/tests/`. Run the whole crate.

## Code

- Match the surrounding code: its naming, its idioms, and its comment
  density. Comments explain *why*, not what.
- For the Rust app, `cargo clippy --all-targets` should introduce no new
  warnings in code you touched.
- For the Rust app, format only your own changes. Parts of the tree are
  not rustfmt-clean, and whole-file reformatting buries the real diff.
  Drop formatting-only hunks in code you didn't otherwise change.
- Don't add a dependency without saying why in the PR. Dependencies ship
  to every user's machine.
- Don't bump the version. Releases are cut by maintainers; the version
  lives only in `[workspace.package]` in `Cargo.toml` for the Rust app,
  or in the appropriate project file for the Swift app.

### Compatibility across versions

Quorumly runs on several devices at once, and they update independently.
A UI may talk to an older backend, and a chat may be hosted on a remote
device running an older engine. So:

- New fields on wire and document types must be optional or
  `#[serde(default)]`. Older peers must still parse newer frames, and
  newer code must accept frames without the field.
- New behavior that needs the other side's cooperation is gated on a
  capability or a device version check. Features degrade when a peer
  lacks them; they don't fail.
- Never rename or repurpose persisted keys, RPC method names, or
  document fields. Add new ones instead.

### Agent harnesses

- New harness integrations follow the existing drivers in the app's
  harness module. Installs are explicit user actions and are documented
  in the relevant harness README.
- Only drive agent CLIs in ways their terms of service allow.

## UI changes

- Reuse the app's existing idioms exactly: rows, menus, seams, hover
  treatments, empty states. If something similar already exists, copy
  it. Don't invent new visual elements as polish.
- Do what the change calls for and nothing more. Unrequested restyling
  of nearby UI gets reverted in review.
- Check light and dark mode, frosted and opaque surfaces. Hover and
  selection on glass lift toward white, never a dark wash.
- Animations use the shared motion kit so they match the rest of the
  app.

## Pull requests

**Title:** a short imperative summary, for example
`Explorer: newest subagents first`.

**Description:** two sections.

- **Summary:** what changed and why, in a few bullets. Call out
  anything reviewers should look at closely, such as compatibility,
  migrations, or behavior that changed on purpose.
- **Test plan:** the tests you added and the suites you ran, as a
  checklist. List manual checks you did, and any you didn't do.

**Screenshots are required for every visible change.**

- Show the new state, and a before/after for changes to existing UI.
  Include light and dark mode when colors or surfaces are involved.
  Use a short recording for animation, drag, or scrolling changes.
- Drag the images into the PR description so GitHub hosts them as
  attachments. **Never commit screenshots to the repository** for a PR.
- Redact personal data before uploading: email addresses, account
  names, tokens, private repo names, and home-directory paths. Pixelate
  them; don't just crop around them.

**Keep it reviewable:**

- Keep the branch mergeable with `main`. PRs are squash-merged, so the
  PR title and description become the commit.
- Respond to review by pushing new commits rather than force-pushing
  over history the reviewer already read.
- CI must pass, or the failure must be a known flake that you name in
  the PR.

## Security

- Never commit secrets, tokens, or real account data, including in
  fixtures, screenshots, and logs.
- Code that spawns processes, handles credentials, or opens network
  listeners gets extra scrutiny in review. Explain in the PR why it
  needs to exist.
- To report a vulnerability, see [SECURITY.md](SECURITY.md).

## License

Quorumly is [MIT licensed](LICENSE). By contributing, you agree that
your contributions are licensed under the same terms — see the
Developer Certificate of Origin above.

Copyright (c) 2026 Soumya Chakraborty and Quorumly Contributors
