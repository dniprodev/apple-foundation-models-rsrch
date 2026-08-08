## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues using the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The default five-label triage vocabulary is used. See `docs/agents/triage-labels.md`.

### Domain docs

This repository uses the single-context layout. See `docs/agents/domain.md`.

### Commit messages

Every issue-driven implementation commit must reference its GitHub issue in the subject:

`<imperative summary> (#<issue-number>)`

Use `Closes #<number>` only when the issue is fully resolved; otherwise use `Refs #<number>`.
