## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues using the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The default five-label triage vocabulary is used. See `docs/agents/triage-labels.md`.

### Domain docs

This repository uses the single-context layout. See `docs/agents/domain.md`.

### Xcode builds and tests

Use `./scripts/xcodebuild-beta` for all `xcodebuild` builds and tests in this
repository. The wrapper selects `/Applications/Xcode-beta.app` through
`DEVELOPER_DIR` and forwards all command-line arguments unchanged. Do not
inline `DEVELOPER_DIR=... xcodebuild` in shell commands.

When build output needs to be saved, use
`./scripts/xcodebuild-beta-capture <log-path> <xcodebuild arguments...>` and
inspect the resulting log separately with `rg`. Do not combine the build,
redirection, and log inspection into one shell command.

Use `./scripts/xcrun-beta` for SwiftPM tests and simulator tooling that require
the pinned Xcode beta developer directory. Swift commands automatically use
stable project-specific module caches under `/tmp`; callers may override the
cache paths with `CLANG_MODULE_CACHE_PATH` and `SWIFTPM_MODULECACHE_OVERRIDE`.
For example:
`./scripts/xcrun-beta swift test --package-path Packages/GroceryModels` or
`./scripts/xcrun-beta simctl runtime list -j`.

### Commit messages

Every issue-driven implementation commit must reference its GitHub issue in the subject:

`<imperative summary> (#<issue-number>)`

Use `Closes #<number>` only when the issue is fully resolved; otherwise use `Refs #<number>`.
