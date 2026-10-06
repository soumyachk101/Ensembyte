#!/usr/bin/env bash
# The Linux Rust tests that used to run as separate `cargo test` invocations in
# session-sync-regressions, cursor-compatibility and preview-tests, as ONE
# build and ONE nextest run (separate invocations recompiled the same
# dependency graph with different feature sets).
#
# Same coverage as the old invocations:
#   ensembyte-harness  every test binary (cursor-compatibility ran `-p ensembyte-harness`
#                  plus `--test pi_rpc` with native-fixture; native-fixture only
#                  adds the pi_rpc fixture binaries, so it is on for the whole build)
#   ensembyte-preview  every test binary (preview-tests)
#   ensembyte-doc      lib + attachments_roundtrip (cursor-compatibility)
#   ensembyte-sync, ensembyte-update   lib only (session-sync-regressions)
#   ensembyte-engine   lib + the integration tests named below. Engine has many other
#                  integration binaries (live agents etc.) that no workflow ran, so
#                  they are listed instead of globbed to avoid compiling them.
# nextest does not run doctests; these crates have none (their doc comments
# contain no Rust code blocks).
# Extra arguments are passed to nextest (the nightly job adds `--release`).
set -euo pipefail
cd "$(dirname "$0")/../.."

tests=()
for f in crates/harness/tests/*.rs crates/preview/tests/*.rs; do
  tests+=(--test "$(basename "$f" .rs)")
done
for t in session_publication restart_resume codex_subagents local_profiles message_queue pi_resume attachments_roundtrip; do
  tests+=(--test "$t")
done

exec cargo nextest run --config-file scripts/ci/nextest.toml --locked --no-fail-fast \
  -p ensembyte-harness -p ensembyte-engine -p ensembyte-sync -p ensembyte-update -p ensembyte-doc -p ensembyte-preview \
  --features ensembyte-harness/native-fixture \
  --lib --bins "${tests[@]}" "$@"
