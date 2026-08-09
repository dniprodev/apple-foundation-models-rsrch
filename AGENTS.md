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

### Commit messages

Every issue-driven implementation commit must reference its GitHub issue in the subject:

`<imperative summary> (#<issue-number>)`

Use `Closes #<number>` only when the issue is fully resolved; otherwise use `Refs #<number>`.
