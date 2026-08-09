Research complete: [Foundation Models and Claude integration constraints](https://github.com/dniprodev/apple-foundation-models-rsrch/blob/main/docs/research/foundation-models-claude-constraints.md).

## Resolution

- Use `LanguageModelSession` as the common application-facing API for Apple's on-device model and Anthropic's `ClaudeLanguageModel`.
- Keep the original request, private tools, household data, and private tool results in the local session.
- Invoke Claude through a short-lived isolated child session created only from a deterministic, disclosure-approved `RemoteTask`; do not switch Claude into the local session's shared transcript.
- Use intent-driven `DynamicProfile` and `DynamicInstructions` for local orchestration, not as a security boundary.
- Expose public catalog tools to either provider, private tools only locally, and commit mutating actions only through user-approved app UI.
- Use developer-supplied API-key authentication for simulator work and keep App Attest as an optional physical-device experiment.
- Prototype the remaining beta risks: cross-provider tool/guided-generation parity, transcript/privacy behavior, error mapping, cancellation, and capability handling.
