## Summary

<!-- What changed and why? 1-3 bullet points. -->

- 
- 

<!-- Call out anything reviewers should look at closely: compatibility, migrations, behavior changes. -->

## Test Plan

<!-- Checklist of what you ran and what you didn't. -->

- [ ] `cargo test --locked -p orbit-ui --lib -- --test-threads=1`
- [ ] `cargo test --locked -p orbit-engine --lib`
- [ ] `cargo test --locked -p orbit-harness`
- [ ] `cargo test --locked -p orbit-sync --lib`
- [ ] `cargo test --locked -p orbit-preview`
- [ ] `cargo clippy --all-targets` introduces no new warnings
- [ ] Manual check: light + dark mode (if UI change)
- [ ] Manual check: frosted + opaque surfaces (if UI change)

## Screenshots

<!-- Required for any visible UI change. Drag images here for GitHub to host them. -->

## Checklist

- [ ] Branch is mergeable with `main`
- [ ] CI passes (or failure is a named known flake)
- [ ] No secrets or personal data in commits, screenshots, or logs
- [ ] Public APIs are backward-compatible (new fields are optional / `#[serde(default)]`)
- [ ] Documented the change in the PR description