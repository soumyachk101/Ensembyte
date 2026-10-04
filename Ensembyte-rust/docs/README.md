# Ensembyte Design & Research Docs

This directory contains design notes, research, plans, and reference
documentation for the Ensembyte project. It does not contain the primary
getting-started guide (see [../README.md](../README.md)) or contribution
instructions (see [../CONTRIBUTING.md](../CONTRIBUTING.md)).

## Directory map

| Path | Contents |
| --- | --- |
| `adr/` | Architecture Decision Records — one per significant design choice |
| `plans/` | Implementation plans for specific features or releases |
| `regressions/` | Regressions that have been found and fixed |
| `reference/` | Platform-specific and operational reference (Linux browser, Windows dev, etc.) |
| `research/` | Background research — technology choices, stability audits, catalogs |
| `screenshots/` | Screenshot fixtures and guides for visual regression checks |
| `sound-design/` | Audio design notes and audition assets |
| `toolcraft/` | Agent workflow notes and worklogs |

## Key documents

| Document | Description |
| --- | --- |
| `ARCHITECTURE.md` (repo root) | Full system design, crate map, topology |
| `CONTEXT.md` (repo root) | Domain vocabulary (themes, sessions, workspaces) |
| `performance-*.md` | Performance investigations and runway plans |
| `mcp.md` | Model Context Protocol integration design |
| `sync-*.md` | Sync and CRDT calibration notes |
| `mobile-*.md` | Mobile/iOS core integration notes |
| `pi.md` | Pi (Inflection) harness integration |

## Conventions

- Design docs use Markdown and live in `docs/`. The root `docs/` level is for
  subsystem-wide notes; deeper directories group by type (plans, research, …).
- ADR titles are `NNN-slug.md` and dated in the heading.
- Screenshot README files explain the capture and comparison setup.
- Internal research and plans may reference code paths under `crates/` and
  `apps/` directly — they are not user-facing and may include implementation
  details.
