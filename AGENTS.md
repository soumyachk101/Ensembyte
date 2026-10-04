# AGENTS.md — Ensembyte agent workflow

## Worktrees (mandatory for coding)

Never code directly in the main checkout of either implementation for
experimental tasks. Use a per-task worktree.

**Swift app:**

```sh
cd Ensembyte-swift
git fetch origin --prune
git worktree add -b <branch> ~/.ensembyte-swift/worktrees/agent-<slug> origin/main
# Do all edits, builds, and scripts/quick_run.sh runs inside that worktree
# Cleanup when done:
git worktree remove --force ~/.ensembyte-swift/worktrees/agent-<slug>
git worktree prune
```

**Rust app:**

```sh
cd Ensembyte-rust
git fetch origin --prune
git worktree add -b <branch> ~/.ensembyte-rust/worktrees/agent-<slug> origin/main
# Do all edits, builds, and cargo runs inside that worktree
# Cleanup when done:
git worktree remove --force ~/.ensembyte-rust/worktrees/agent-<slug>
git worktree prune
```

Never delete the main checkout, never touch another agent's worktree.

## Layout (four layers, one way)

Both implementations follow the same one-way layering. New code goes in
the lowest layer whose dependencies it has; a Core file that needs the
provider registry, the settings, or a view is in the wrong layer, and
the part that needs them must be split into an extension in the layer
above.

### Swift app

- `Ensembyte/Core` (models, pure support) reaches into nothing else in
  the app.
- `Ensembyte/Services` (Git, Store, Providers) and `Ensembyte/UI`
  (Chrome, Common, Markdown, Theme, Sound) reach only into Core.
- `Ensembyte/App` (entry, model, runtime, windows, captures, and every
  feature view) reaches into everything.

There is no test target and no test scripts; the build is the check
(`xcodebuild -project Ensembyte.xcodeproj -scheme Ensembyte -configuration Debug build`).

### Rust app

- `crates/core` (models, pure support) reaches into nothing else.
- `crates/services` and `crates/ui` reach only into `core`.
- `crates/app` (entry, runtime, windows, feature views) reaches into
  everything.

## Hydra heads (the chat team)

A head never builds or otherwise verifies: no `xcodebuild`, no
`scripts/quick_run.sh`, no `cargo run`, no check command. It edits the
files the lead briefed it on and reports, nothing more. The lead runs
the one build that proves the change, in the checkout, after the heads
report.

## Relaunching (never unprompted)

NEVER run `scripts/quick_run.sh`, `cargo run`, or otherwise
quit/relaunch either implementation unless Soumya explicitly asks for
it in that moment.

- Building inside the worktree is fine; installing to /Applications and
  relaunching is not.
- "Finish", "merge", "done", or "test it" do not imply relaunch — only
  an explicit request to run/relaunch the app does.

## Building (local, native)

Build each app on its native OS. Do not rely on GitHub Actions to produce
binaries — the CI runners are unreliable; build locally and push the
artifacts to GitHub Releases yourself.

**Ensembyte-swift** — macOS only. Xcode and SwiftUI require macOS. Build on
a Mac:

```sh
cd Ensembyte-swift
xcodebuild -project Ensembyte.xcodeproj \
  -scheme Ensembyte \
  -configuration Release \
  build
./scripts/package_dmg.sh   # produces Ensembyte.dmg
```

**Ensembyte-rust** — Linux and Windows only. Build on each target OS (or
cross-compile from Linux):

```sh
cd Ensembyte-rust

# Linux (x86_64)
cargo build --release --target x86_64-unknown-linux-gnu
./scripts/package-linux.sh   # produces tar.gz

# Linux (aarch64)
cargo build --release --target aarch64-unknown-linux-gnu

# Windows (x86_64) — on Windows or via cross-compile
cargo build --release --target x86_64-pc-windows-msvc
```

## Releases

All DMG releases, app updates, and GitHub release publications must
ONLY be made to the designated release repository. Never publish
releases or upload binaries or assets to the main source repository.

Build locally per the section above, then publish the artifacts:

```sh
# macOS
gh release create v1.0.0 build.noindex/Ensembyte-1.0.0.dmg \
  --repo soumyachk101/Ensembyte \
  --title "v1.0.0"

# Linux / Windows
gh release create v1.0.0 \
  dist/ensembyte-linux-x86_64.tar.gz \
  dist/Ensembyte-Setup.exe \
  --repo soumyachk101/Ensembyte \
  --title "v1.0.0"
```

**Every release must update the website.** After publishing a new
version:

1. Update the version string in the website download section.
2. Add the new release entry to the website changelog.
3. Commit and push so the deployment pipeline auto-deploys the site.
