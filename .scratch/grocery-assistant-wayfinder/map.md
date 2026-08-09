## Destination

Produce an implementation-ready specification for the Grocery Shopping Assistant: milestone one using Apple's on-device model plus Claude, and milestone two adding a custom OpenAI `LanguageModelExecutor`. The route is clear when the app architecture, data pipeline, privacy contract, user surface, framework usage, and evaluation strategy are decided well enough for build tickets to be written without product or feasibility guesses.

## Notes

- This map plans decisions; it does not implement the app.
- Read `CONTEXT.md` before working any ticket and use its domain vocabulary.
- Use the repository's `research`, `prototype`, `grilling`, `domain-modeling`, and `codebase-design` skills according to ticket type.
- Prefer primary Apple, Anthropic, OpenAI, Open Food Facts, and library sources.
- Preserve the Thin Reference Shell and the local-only privacy guarantee.
- Record newly resolved domain language in `CONTEXT.md`.

## Decisions so far

The destination constraints agreed before charting are recorded in `CONTEXT.md`.

- [Verify Foundation Models and Claude integration constraints](https://github.com/dniprodev/apple-foundation-models-rsrch/issues/2) — Foundation Models supports both shared-history baton-pass and isolated phone-a-friend orchestration; the Reference App will make their remote context and privacy implications visible.
- [Define the Open Food Facts ingestion contract](https://github.com/dniprodev/apple-foundation-models-rsrch/issues/3) — Generate a deterministic checksummed SQLite snapshot from pinned official Parquet sources; reserve API v3 for narrow live lookup.
- [Define Foundation Models observability and evaluation constraints](https://github.com/dniprodev/apple-foundation-models-rsrch/issues/4) — Combine sanitized app-owned Model Trace, sensitive developer-only Instruments traces, and invariant-plus-aggregate evaluations.
- [Prove the local-first hybrid boundary](https://github.com/dniprodev/apple-foundation-models-rsrch/issues/5) — Skip a throwaway prototype: the Reference App itself will demonstrate baton-pass and phone-a-friend behavior, including shared-history privacy concerns.
- [Prototype the Thin Reference Shell](https://github.com/dniprodev/apple-foundation-models-rsrch/issues/6) — Use a grocery-assistant-first narrative Model Run with chronological verbatim intermediate outputs and a dominant final answer; defer detailed UX to Reference App implementation.

## Not yet specified

- Milestone-two OpenAI executor design after milestone one's provider-neutral contract is settled.
- Final build sequence and implementation ticket breakdown after all architectural decisions close.

## Out of scope

- Production grocery storefront, checkout, account backend, and retailer integrations.
- Real customer transaction imports or real personal household data.
- Apple Private Cloud Compute.
- Camera capture, barcode scanning, and product-photo recognition in milestone one.
- Shipping credentials, maintaining a catalog backend, or bundling the complete Open Food Facts corpus.
