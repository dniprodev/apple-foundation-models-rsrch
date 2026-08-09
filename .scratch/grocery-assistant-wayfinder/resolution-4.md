Research complete: [Foundation Models observability and evaluation constraints](https://github.com/dniprodev/apple-foundation-models-rsrch/blob/main/docs/research/foundation-models-observability.md).

## Resolution

- Use three complementary surfaces: a sanitized app-owned Model Trace, developer-only Foundation Models Instruments traces, and a Reference Acceptance Suite.
- Instruments provides rich provider-independent prompts, responses, tools, timing, and token diagnostics but is neither a runtime API nor safe production telemetry; traces can contain unencrypted sensitive data.
- The app owns correlation IDs, provider/model/profile/instruction identifiers, phase and tool timing, disclosure decisions, normalized errors, and action-approval state.
- Use public transcripts and final usage values where available, while treating provider metadata and Claude reasoning-token counts as incomplete.
- Assert privacy, disclosure, and action invariants deterministically at 100%; evaluate probabilistic routing/tool/answer behavior over repeated runs and never compare generated prose verbatim.
