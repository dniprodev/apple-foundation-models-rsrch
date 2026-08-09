Product data comes from:

  - Official Open Food Facts product records.
  - Official Open Prices price records.
  - Both are pinned to immutable Parquet revisions, filtered/joined offline, and emitted as a sorted, checksummed SQLite database with a provenance manifest.
  - The initial France/EUR Reference Dataset contains 500 quality-gated products; its manifest records the selection size and any source-constrained category shortfalls.
  - Open Food Facts API v3 is only an optional fallback for a specific product missing locally; successful results are cached. The core demo does not depend on the
    network.

  The app copies the bundled SQLite database into Application Support on first launch. GRDB provides indexed/full-text queries over products, prices, household history,
  pantry, cart, cached products, and Model Trace. See CONTEXT.md:67 and CONTEXT.md:75.

  Models never access SQLite directly. They use app-owned tools through the Primary Interaction Loop:

  1. The model requests a tool such as product search or pantry/cart lookup.
  2. The app executes that tool against the local GRDB store.
  3. The structured result is returned to the model.
  4. The app records the observable tool activity in the Model Run/Trace.

  For local-only operation, prompts, context, and tool results remain on-device.

  For remote Claude/OpenAI operation, Foundation Models remains the transcript and tool owner. Remote models receive only the effective disclosed context and approved
  tool definitions/results. That disclosure is materialized in an exact Remote Context View; private household tools and context are not automatically sent. Baton-pass
  exposes more shared history, while phone-a-friend sends a bounded Remote Task with narrower context. See CONTEXT.md:47.
