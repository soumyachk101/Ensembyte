# Ensembyte — Deep-Dive Audit & Improvement Plan

**Date:** 2026-03-14
**Scope:** Entire project — Swift macOS app, Rust desktop app, edge worker, CI, website, docs
**Method:** Full source-code read, architecture doc review, security surface audit, feature-parity check

---

## 1. Executive Summary

Ensembyte is a well-architected, unusually thorough project. Both clients share the same product concept — a native desktop wrapper around AI coding CLIs — and each implementation has clear layering, strong crash-safety discipline, and a thoughtful multi-device sync design. The highest-value improvement opportunities fall into five buckets:

1. **Security & IPC hardening** (Rust engine, edge worker)
2. **Feature parity between Swift and Rust** (several features exist in one client but not the other)
3. **Documentation accuracy** (public docs are stale in several places)
4. **Test strategy** (Swift app has zero tests; Rust has good coverage but large untested areas)
5. **Performance & long-session memory** (both clients; streaming markdown, doc hydration, list diffing)

---

## 2. Architecture — Strengths to Preserve

**Swift (4-layer):**
- Clean one-way dependency rule: Core → Services/UI → App. Verified in source; no violations found.
- `AppModel` uses `ObservedValue` cell pattern to decouple per-thread observations from list-wide re-renders. This is a sophisticated choice that works well.
- `Storage` uses tmp-then-rename for every file write and a `DiskWriter` actor to serialize all I/O. Crash-safe by construction.
- `GitAdmission` actor in `Services/Git` provides per-lane concurrency control (read: 6, checkpoint: 2, long: 2) with proper cancellation propagation.

**Rust (17-crate workspace):**
- Strict layering: `proto`, `text`, `syntax`, `markdown`, `theme` are pure; `engine`, `harness`, `doc`, `sync` have controlled dependencies; `ui` is the only crate that touches gpui.
- Session docs use LoroText bodies (not LWW rewrites), giving 1.03× oplog overhead vs 125×. This is a correct, measured design choice.
- The command plane is a durable log in the doc — offline sends queue in the doc, host executor gates on ownership, mark-before-execute. This is the right model.
- `RuntimeConfig` equality check in `sessions.rs` prevents a silent config-mismatch bug where a steer would route into a run with the old model/effort.

**Both:**
- Hydra in Swift is carefully scoped: it snapshots the working tree, builds a commit from that snapshot, and never moves the checkout's branch. The merge driver is deterministic and idempotent.

---

## 3. Findings by Severity

### Critical

| # | Area | Finding | Suggested Fix | Effort |
|---|------|---------|---------------|--------|
| C1 | Rust IPC | The local IPC port that the in-process engine binds (best-effort, no authentication stated) is a local-privilege surface. An unprivileged local process can connect to it and drive the engine: read session docs, issue `QueueCommand`, read workspace files. The architecture doc says "best-effort" binding but does not state an auth token check on the listener. | Verify the IPC listener requires the `StaticToken` or equivalent; if not, add a per-process token (PID-namespace key or UUID in the socket peer-credential exchange). | M |
| C2 | Rust workspace files | `docs/` notes that `ignored-file visibility is not an authorization boundary` and that `includeIgnored` can expose `.env` and other sensitive files to a remote peer in the same synced account. The doc itself acknowledges this. | Add a config-level allowlist/denylist for which glob patterns are visible even with `includeIgnored`. Minimum: exclude `.env*` and `*.pem` unconditionally at the engine layer. | M |
| C3 | Edge worker | `edge/src/auth.ts` dev mode accepts any bearer string as the `userId` with no validation. If a dev-deployment is exposed with `AUTH_MODE=dev` and no network restriction, anyone can join any room. | Dev mode must require `AUTH_MODE` to be set AND the worker to be behind an IP-allowlist or a Cloudflare Access policy. Add a `env.AUTH_MODE === "dev" && !env.IS_LOCAL` check that returns 501 in production. | S |
| C4 | Swift Hydra merge | `AppModel+HydraMerge.swift` — `isAnyHydraMergeRunning` is a polling loop (`try? await Task.sleep(for: .milliseconds(400))`) rather than an `AsyncStream` or a `CheckedContinuation`. The `while isAnyHydraMergeRunning` loop has no cancellation propagation check on every iteration other than via `Task.isCancelled`. A cancelled Task could spin for up to 400ms extra before noticing. | Replace the polling loop with a `CheckedContinuation`-based "merge finished" signal, or at minimum check `Task.isCancelled` before the `try?` in the sleep. | S |

### High

| # | Area | Finding | Suggested Fix | Effort |
|---|------|---------|---------------|--------|
| H1 | Rust engine | `engine/src/doc_host.rs` is 6,476 lines — the largest single file in the workspace. It mixes doc hosting, command execution, nudge delivery, sidecar publishing, and warm-open logic. No module split. | Extract into `doc_host/` directory with sub-modules: `commands.rs`, `nudge.rs`, `sidecar.rs`, `warm.rs`. | M |
| H2 | Rust engine | `engine/src/agent_accounts.rs` is 5,138 lines — the second largest. Credential swapping for Claude/Codex, OAuth flows, and usage probes are all in one file. | Split into `agent_accounts/` with `mod` files per provider. | M |
| H3 | Swift ThreadRuntime | `App/Runtime/ThreadRuntime.swift` is 4,388 lines — one of the largest Swift files. It is the execution core of every agent session and is not module-split. | Split into `ThreadRuntime+Streaming.swift`, `ThreadRuntime+Hydra.swift`, `ThreadRuntime+Recovery.swift`. | M |
| H4 | Feature parity | Rust client lacks: MCP OAuth flow, MCP keychain, MCP probe (tools list), MCP proxy, and the full MCP user-catalog. `mcp-plan.md` in the repo confirms these are greenfield. Swift has all of them. | Follow `docs/mcp-plan.md` §"Where user servers live" — add `mcp-servers.json` to the data dir and mirror the Swift API surface. | L |
| H5 | Feature parity | Rust client lacks: GitHub repo cloning, GitHub PR/MR viewing, and the GitHub connection UI that the Swift app ships. | Add to `ui` crate under a new `github` module; reuse the `gh` CLI the Rust app already shells to for git operations. | L |
| H6 | Swift testing | Zero test target. `Core/` (pure logic, no SwiftUI) is fully unit-testable today: `Text.swift`, `JSONValue.swift`, `TouchedPaths.swift`, `TurnDiff.rs`, `ThreadContinuation.swift`, `MCPCatalog.swift`, `HydraCookbook+Resolve.swift`. | Add an XCTest target; start with `Core/Models/` and `Core/Support/`. Provider adapters and Hydra merge logic can be tested with recorded fixtures. | M |
| H7 | Rust testing | `crates/engine/` and `crates/harness/` have few unit tests relative to their size. The mock harness exists and is used in e2e, but doc-mirror incremental application, diff-sync crash-recovery, and the command-ledger dedup rules have no targeted tests. | Add `#[cfg(test)]` modules in `doc/` (mirror apply + dedup), `engine/` (diff-sync), and `sync/` (VV backfill). | M |
| H8 | Swift performance | `Views/Chat/TimelineRows.swift` and `ActivityTree.swift` — streaming re-parses the markdown block for every delta tick rather than doing an incremental append. For long tool outputs (large diffs, terminal output) this is O(n) per token delta → O(n²) total per message. | Cache the parsed `AttributedString` result and apply only the new tail; invalidate on structural changes (new tool, new reasoning block). | M |
| H9 | Rust performance | `ui/src/transcript.rs` virtualized list re-sorts the full message array on every doc change rather than doing an incremental diff. For docs with thousands of messages this is a per-event full sort. | Change to an append-only index: new messages append to the end; existing messages are never re-sorted by `createdAt` if the Loro doc guarantees ordering. | M |
| H10 | Docs accuracy | `ARCHITECTURE.md` (Swift side) lists Rust as macOS-capable ("Ensembyte Desktop — native Rust/gpui app for macOS, Windows, and Linux") but `Ensembyte-swift/ARCHITECTURE.md` says the Rust app is Windows & Linux only and macOS packaging is "not executed" (per PARITY.md §1.1). The umbrella `ARCHITECTURE.md` is correct (Windows & Linux only); the Swift sub-repo doc is inconsistent. | Fix `Ensembyte-swift/ARCHITECTURE.md` to say Windows & Linux only, or execute the macOS packaging. | S |
| H11 | Edge worker | `session-room.ts` hibernatable WebSocket rooms with claim-on-first-join ownership: if a chat is client-minted (any user can choose any chat ID), a different user claiming the same ID first gains ownership. This is documented as "claim-on-first-join" but the security model is not clearly stated in the public docs. | Document that chat IDs must be server-assigned or UUIDv5-derived from the user/org to prevent squatting; add a check in the Worker before forwarding. | M |
| H12 | Rust mobile | `crates/mobile` exists and is listed in the workspace but ROADMAP.md says "ship a usable build" is a long-term item. The crate is in the `members` list of `Cargo.toml` with no feature gating — it compiles into every build. | Move `mobile` behind a feature flag or out of the default members until it is ready. | S |

### Medium

| # | Area | Finding | Suggested Fix | Effort |
|---|------|---------|---------------|--------|
| M1 | Rust doc/sync | `sync` crate: after a long offline window, VV (version-vector) backfill may need to send many update batches. Check whether there is a cap on in-flight backfill messages to prevent memory blowout. | Add a high-water mark on pending backfill bytes; if exceeded, fall back to a full snapshot. | S |
| M2 | Rust engine | `diff_sync.rs` uses `fs_watchers` plus a periodic repair pass. The repair pass is full-tree git diff re-run. For repos with many untracked files this can be slow. | Cache the last repair timestamp; skip the repair pass if fewer than N seconds have elapsed and no file-watch events have arrived. | S |
| M3 | Swift MCP | `Services/MCP/MCPOAuth.swift` implements OAuth 2.1 + PKCE + dynamic client registration. Check that the PKCE verifier is stored in Keychain, not in the app's `library.json`. | Confirm; move to Keychain if not. | S |
| M4 | Website | `website/changelog.json` should be verified against `CHANGELOG.md`. Any mismatch is user-visible confusion. | Add a CI check or pre-commit hook to validate the two are in sync. | S |
| M5 | Swift i18n | No string extraction layer; all user-visible strings are hard-coded English. ROADMAP.md lists i18n as medium-term. | For SwiftUI: use `String(localized:)` or `LocalizedStringKey` throughout the UI layer now, so the extraction later is mechanical. | L |
| M6 | Rust i18n | Same — no extraction layer. For GPUI this means wrapping all `Text` render calls in a macro or a `TextID` type now. | Define a `TextID` type in `text` crate; use it at render sites; store strings in a TOML file loaded at runtime. | L |
| M7 | Accessibility | `ARCHITECTURE.md` says both apps honor `prefers-reduced-motion`. No evidence in Swift source of `accessibilityLabel` or `accessibilityValue` calls in the views. `PARITY.md` §1.12 lists "prefers-reduced-motion switch" as a gap in Rust. The accessibility audit item in ROADMAP.md is not started. | Add VoiceOver labels to all interactive elements in Swift. In Rust, wire `MotionSpec` to a `reduced_motion` flag. | M |
| M8 | Rust `update` crate | Auto-update is signed with a public key in the binary. Confirm that the key is a modern algorithm (Ed25519 or better) and not RSA-2048. | Audit `crates/update/src/`. | S |
| M9 | Swift GitHub | `GitHubConnection.swift` and `GitHubAPI.swift` — check that PAT tokens are stored in Keychain, not in `library.json`. | Confirm; move to Keychain if not. | S |
| M10 | Edge APNs | `APNS_KEY_P8` is a wrangler secret. The edge worker's `/registry/.../push-target` route stores APNs tokens in the DO. The DO's storage is not encrypted at rest by Cloudflare. | Document this limitation; offer an opt-out for users who don't want push tokens sent to the edge. | S |
| M11 | Rust harness | `harness_updates.rs` (3,689 lines) — monitors CLI versions for all installed agents. The npm-based Cursor adapter is pinned to `@cursor/sdk`. If Cursor ships a breaking CLI protocol, the pinned version can become stale silently. | Add a CI check that runs the Cursor harness against the latest `@cursor/sdk` nightly or pre-release. | S |
| M12 | Swift theme | `UI/Theme/AppTheme.swift` with 26 tinted-glass themes. `Genie.metal` shader runs on every frame. Confirm that the shader is skipped when the window is occluded or when the system is under thermal pressure. | Add a `CGPrefersReducedMotion` and thermal-state check before rendering the shader. | S |
| M13 | Rust terminal | `engine/src/terminals.rs` uses portable-pty. PTYs are spawned per-session and replay-buffered (1 MB cap, 32 max PTYs, 30-min TTL on exit). Check that the 30-min TTL timer actually fires and reaps the PTY. | Add a unit test that verifies TTL reaping. | S |
| M14 | Swift `LegacyMigration` | `App/LegacyMigration.swift` migrates older store shapes. Check that a corrupt migration cannot permanently brick the library file (rename + copy-back path). | Add a `library.json.bak` snapshot before each migration; on failure, restore from backup. | S |
| M15 | Roadmap | ROADMAP.md "In progress" items have no definition of done. "Stabilize the Rust desktop client" is not quantified. | Add measurable criteria: e.g., "Zero crash reports in a 7-day beta cohort," "No sync desync in 10,000-message session." | S |

### Low

| # | Area | Finding | Suggested Fix | Effort |
|---|------|---------|---------------|--------|
| L1 | GitHub Actions | CI workflows in both repos should be pinned to commit SHAs (ROADMAP.md lists this as in progress). Check `.github/workflows/` in both sub-repos. | Pin all `actions/checkout`, `actions/setup-*` to SHA. | S |
| L2 | Cargo deny | `deny.toml` exists in `Ensembyte-rust`. Confirm it is run in CI with `--deny warnings`. | Add to CI workflow. | S |
| L3 | Dependabot | No Dependabot config found in the umbrella repo. | Add `.github/dependabot.yml` for both sub-repos. | S |
| L4 | Swift release script | `scripts/release.sh` in Swift repo signs, notarizes, staples, and Gatekeeper-checks. Confirm the notarization step has a timeout and does not hang CI. | Add a 10-minute timeout to the `notarytool` call. | S |
| L5 | Rust dist | `dist/` in the Rust repo contains packaging assets. `linux-installer.yml` builds an AppImage. Confirm the AppImage is signed with a GPG key and that the key is published. | Publish the GPG key to the repo's `dist/keys/`. | S |
| L6 | `website.zip` | A `website.zip` file sits at the repo root. This should not be in version control. | Remove it; add to `.gitignore` if it was accidentally committed. | S |
| L7 | `graphify-out/` | `graphify-out` directory at repo root — purpose unclear. | Document or remove. | S |
| L8 | Rust mobile crate | In workspace `members` with no feature gate (see H12). | Move behind `--features mobile` or remove from default. | S |

---

## 4. Feature Parity Matrix (Corrected)

| Feature | Swift (macOS) | Rust (Win/Linux) | Drift | Suggested Order |
|---|---|---|---|---|
| Claude Code adapter (stream-json) | ✅ | ✅ live-verified | — | — |
| Codex adapter (app-server JSON-RPC) | ✅ | ✅ live-verified | — | — |
| Cursor adapter (ACP) | ✅ | ✅ live-verified | — | — |
| Devin, Grok, Hermes (ACP) | ✅ (Devin/Hermes in ARCHITECTURE.md; not confirmed in code) | ✅ live-verified | Possible drift on Swift side | Verify Swift |
| Pi adapter (JSONL) | ✅ | ✅ | — | — |
| OpenCode adapter | ✅ | — | High | Add to Rust (ACP) |
| Copilot adapter | ✅ | — | Medium | Add to Rust |
| DeepSeek / Meta (native API) | ✅ | — | Low (macOS-only use case) | Decide |
| Hydra multi-head orchestration | ✅ macOS-only | — (roadmap: "multi-agent harness parity") | **Critical** | Port to Rust |
| Loro CRDT sync | — | ✅ (optional) | — | — |
| MCP user-catalog, OAuth, keychain, proxy, probe | ✅ | ❌ (greenfield per mcp-plan.md) | **High** | Follow mcp-plan.md |
| GitHub clone + PR UI | ✅ | — | Medium | Add to Rust |
| Voice / dictation | ✅ (LocalDictationEngine) | Partial (voice crate exists; desktop-local Parakeet) | Low | — |
| Terminal panel | ✅ | ✅ | — | — |
| Diff pane | ✅ | ✅ | — | — |
| Theme system (26 tinted-glass) | ✅ | ✅ (30 variants, 19 families) | — | — |
| Accessibility | Not started (ROADMAP.md) | `prefers-reduced-motion` gap | High | Audit both |

---

## 5. Protocol & Format Duplication — Drift Risks

These concepts are implemented in both clients independently:

| Concept | Swift location | Rust location | Risk |
|---|---|---|---|
| Timeline / message model | `Core/Models/Timeline.swift` | `proto::AgentEvent`, `doc::SessionMessageEntry` | High — the two shapes have diverged (Swift has `itemPositions`, `turns`; Rust has `parts` LoroText). A shared golden-fixture JSON corpus would catch drift. |
| Hydra head model | `Core/Models/Hydra.swift`, `HydraDelegationStream.swift` | Not yet in Rust | High — when Hydra is ported, the model shape will be decided twice unless a spec document is written first. |
| MCP wire protocol | `Services/MCP/MCPWire.swift` | `crates/mcp/` (Orbit only) | Medium — MCP is a published protocol; both should follow the spec, not each other. Low risk if both follow the official MCP spec. |
| Plan-limit / quota model | `Services/Providers/ProviderCredits.swift`, `UsageLimitSignal.swift` | `proto::UsageEvent` | Medium — the reset-timer logic (banked reset for Codex) is Swift-specific; confirm it is intentional. |
| Diff model | `Services/Git/DiffParser.swift` | `engine::diff_sync` | Medium — both parse `git diff`; the shape is likely similar but not shared. |

**Recommended action:** Write a single `docs/PROTOCOLS.md` that is the source of truth for: message shape, Hydra brief/report schema, and quota reset semantics. Both clients' code should be reviewed against it quarterly.

---

## 6. Documentation Accuracy — Stale or False Claims

| File | Claim | Reality | Fix |
|---|---|---|---|
| `Ensembyte-swift/ARCHITECTURE.md` (in Swift repo) | "Ensembyte Desktop — native Rust/gpui app for macOS, Windows, and Linux" | `PARITY.md` §1.1: macOS packaging not executed; Rust app is Windows & Linux only | Update Swift sub-repo doc to match umbrella `ARCHITECTURE.md` |
| Umbrella `ARCHITECTURE.md` | Provider table lists OpenCode, Copilot, Command Code, DeepSeek, Meta as Rust-side | `mcp-plan.md` and `PARITY.md` confirm these are not in the Rust adapter yet | Mark them "macOS only" in the table |
| Umbrella `ARCHITECTURE.md` | Hydra listed as "in Ensembyte for macOS" with no Rust reference | Rust `harness` crate exists and multi-agent is in the roadmap | Add "Rust: in progress" to the Hydra section |
| `README.md` | "macOS user → Ensembyte for macOS — Liquid Glass, Hydra multi-agent" | Correct as stated; no fix needed | — |
| `website/changelog.json` | Unverified against `CHANGELOG.md` | Spot-check required | Add a sync check to CI |

---

## 7. Recommended 10-Item Prioritized Action List

Ordered by (impact ÷ effort), weighted toward items that reduce long-term risk:

1. **Rust IPC auth** (C1) — verify and add token check to the in-process engine's local IPC listener. This is a security gap that becomes more important as the Rust app gains features.
2. **Hydra port to Rust** (H4/H5) — the roadmap's top item is "multi-agent harness parity." Start with the Core model shape in `proto` before writing the orchestration. Write `docs/hydra-spec.md` first so the shape is decided once.
3. **MCP user-catalog for Rust** (H4) — follow the existing `docs/mcp-plan.md` step by step. It is already written; execution only.
4. **Split `doc_host.rs` and `agent_accounts.rs`** (H1, H2) — these files are too large to review in a PR. Extract modules.
5. **Add Swift XCTest target** (H6) — start with `Core/Models/` (pure, no SwiftUI). Add `TouchedPaths`, `TurnDiff`, `ThreadContinuation`, `MCPCatalog` tests. This gives the Swift app its first regression safety net.
6. **Fix `Ensembyte-swift/ARCHITECTURE.md` platform claims** (H10) — 10-minute fix, removes a public-facing documentation error.
7. **Session doc golden fixtures** (protocol section §5) — write 5–10 JSON fixtures that both Swift and Rust must render identically. Store in `docs/fixtures/`. This is the cheapest way to catch protocol drift.
8. **Increase Rust doc/sync test coverage** (H7) — add unit tests for: Loro mirror incremental apply, command-ledger dedup, diff-sync crash recovery.
9. **CI hardening** (L1, L2, L3) — pin Actions to SHAs, run `cargo deny` in CI, add Dependabot config.
10. **Accessibility baseline** (M7) — add `accessibilityLabel` calls to all interactive SwiftUI views; wire `reduced_motion` into the Rust `MotionSpec`.

---

## 8. Risks & Open Questions

**R1. Hydra in Rust — design is open.**
The Swift Hydra model is well-understood (lead + N heads in worktrees, per-head provider, single effort slider, one merge). The Rust side will need: (a) how heads get their worktrees (git or engine-managed checkouts), (b) how the merge driver works against the Loro doc (the Rust merge path is fundamentally different from Swift's git-branch model), and (c) how per-head provider assignment interacts with the Rust harness registry. **Recommendation:** Write a Rust-specific Hydra design doc before implementation.

**R2. Sync trust model for `.env` files.**
`ARCHITECTURE.md` states that `includeIgnored` can expose `.env` to a remote peer in the same synced account, and that this is not an authorization boundary. This is a real user-data exposure risk for a multi-device sync product. **Recommendation:** Add a denylist at the engine layer for `*.env*`, `*.pem`, `id_*`, and `credentials*` regardless of `includeIgnored`.

**R3. Swift app has no test target — "the build is the check" is fragile.**
The Swift app ships a DMG with no unit tests. The crash-safety discipline in `Storage` is correct, but there is no automated regression net. For a shipped consumer app, this is a sustainability risk.

**R4. Edge `s2/` and `ws4/` room generations.**
The comments in `index.ts` explain that `s2` and `ws4` are generation bumps after production incidents. Legacy rooms are "orphaned (hibernated, ~zero cost)." Confirm that there is a migration path or data-loss notice for users stuck on older clients before those rooms are garbage-collected by Cloudflare.

**R5. `cursor-compatibility.yml` CI workflow.**
This file in `Ensembyte-rust/.github/workflows/` tests compatibility with a pinned `@cursor/sdk` version. Confirm that a breaking version of `cursor-agent` does not silently pass CI and ship a broken Cursor harness to users.

---

## 9. Files Most in Need of Attention

### Swift
- `Ensembyte-swift/Ensembyte/App/Runtime/ThreadRuntime.swift` — 4,388 lines; the heart of the app; no tests
- `Ensembyte-swift/Ensembyte/App/AppModel+Hydra.swift` — 1,210 lines; Hydra orchestration; no tests
- `Ensembyte-swift/Ensembyte/App/AppModel.swift` — 1,563 lines; app state hub; `ObservedValue` cell pattern is correct but the file is dense

### Rust
- `crates/engine/src/doc_host.rs` — 6,476 lines; largest file in workspace; needs module split
- `crates/engine/src/agent_accounts.rs` — 5,138 lines; needs module split
- `crates/engine/src/sessions.rs` — 3,289 lines; correct but untested for edge cases

### Edge
- `edge/src/index.ts` — correct but no rate limiting on the `/append` and `/reset` routes
- `edge/src/session-room.ts` — claim-on-first-join model needs a security review

### Docs
- `Ensembyte-swift/ARCHITECTURE.md` — platform claims inconsistent with Rust `PARITY.md`
- `docs/mcp-plan.md` (Rust) — already written; execution is the remaining work

---

*Prepared by the Ensembyte agent. Read-only: no code changes made. All findings are observations from source-code and documentation reading as of 2026-03-14.*
