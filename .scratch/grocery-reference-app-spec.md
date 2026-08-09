## Problem Statement

Developers need a functional, reproducible iOS Reference App that demonstrates how a grocery experience can use Apple’s on-device Foundation Models framework and Claude together without hiding the model transitions, privacy implications, or tool activity behind a generic chat interface. The app must be useful enough to demonstrate product discovery, meal planning, and cart assistance while remaining local-first, deterministic to set up, and inspectable without relying on production grocery infrastructure or personal data.

## Solution

Build the Grocery Shopping Assistant Reference App in two milestones.

Milestone one delivers a Thin Reference Shell for the Primary Interaction Loop. It ships a versioned SQLite catalog built offline from pinned Open Food Facts and Open Prices inputs, deterministic Demo Households, local-only Apple Foundation Models behavior, explicit Cart Proposal approval, Claude-backed Hybrid Orchestration using Foundation Models dynamic sessions, and an app-owned Model Trace. It is built and demonstrated in this order: local-only first, then Claude, then baton-pass, then phone-a-friend, then Manual Demo Scenarios.

Milestone two adds a custom OpenAI LanguageModelExecutor within the established Reference App architecture. It is an additive provider adapter and not a standalone prototype or a prerequisite for the first milestone.

## User Stories

1. As a developer evaluating Foundation Models, I want to open one native iOS Reference App, so that I can explore a useful grocery interaction instead of disconnected model demos.
2. As a developer, I want a Thin Reference Shell centered on a grocery request, so that the app demonstrates App-Owned Context without impersonating a production storefront.
3. As a shopper using a Demo Household, I want to ask about products, meals, substitutions, and purchase patterns, so that the Primary Interaction Loop provides evidence-backed grocery assistance.
4. As a shopper, I want to choose among deterministic Demo Households, so that I can observe how preferences, restrictions, pantry state, purchase history, and cart state change an answer without supplying real personal data.
5. As a shopper, I want the app to use a bundled catalog offline, so that core demonstrations are reproducible and do not depend on a backend or network connection.
6. As a developer, I want local-only Model Strategy to keep prompts, App-Owned Context, and tool results on-device, so that I can demonstrate the local privacy guarantee without configuring credentials.
7. As a shopper, I want an answer presented as a readable Model Run, so that the final answer is prominent while observable intermediate model and tool outputs remain inspectable.
8. As a developer, I want an expandable Model Trace attached to an ordinary grocery answer, so that I can inspect the selected Model Strategy, profile transitions, tools, timing, errors, and disclosure facts in the running app.
9. As a shopper, I want a Cart Proposal to remain non-mutating until I explicitly approve it, so that a model can suggest a cart change without silently changing my Demo Household.
10. As a developer, I want generated catalog data and Demo Household histories to be reproducible from pinned sources and fixed seeds, so that another developer can rebuild the same demonstration data.
11. As a developer, I want the app to keep catalog, household, pantry, cart, cached live product, and Model Trace state in one local data store, so that UI and model tools observe the same state.
12. As a developer configuring hybrid behavior, I want to enter a Claude credential at runtime and have it stored in Keychain, so that development and simulator demonstrations can use Claude without bundling a secret.
13. As a developer without a Claude credential, I want hybrid behavior to remain unavailable with a clear setup message, so that local-only exploration is never blocked.
14. As a developer, I want baton-pass to expose shared-history remote context, so that I can see which prior prompts, responses, and tool results become visible to Claude.
15. As a developer, I want phone-a-friend to use an isolated child session and a bounded Remote Task, so that I can compare it with baton-pass and inspect its narrower disclosure.
16. As a developer, I want every remote invocation to show an exact Remote Context View, so that privacy implications are observable rather than inferred or claimed away.
17. As a developer, I want Model Trace records to use app-owned stable identifiers and safe metadata, so that provider behavior is inspectable without logging secrets or hidden reasoning.
18. As a developer, I want Manual Demo Scenarios for the local-only and hybrid paths, so that the Reference App can be shown and verified by repeatable, human-readable runs rather than formal model-quality benchmarks.
19. As a developer, I want the project organized into deep Domain, Data, Models, and Composition modules, so that provider, persistence, and UI changes remain localized behind small interfaces.
20. As a developer extending milestone two, I want an OpenAI LanguageModelExecutor that preserves Foundation Models transcript and tool ownership, so that OpenAI becomes an adapter rather than a rewrite of GroceryDomain or the Primary Interaction Loop.
21. As a developer evaluating milestone two, I want OpenAI request mapping, streaming, cancellation, structured output, tool behavior, and error handling to fail closed when fidelity is unavailable, so that inspectability and app semantics are not silently degraded.
22. As a developer, I want OpenAI experimentation to occur in the Reference App after milestone one, so that the Apple-plus-Claude demo remains the first completed, stable reference surface.
23. As a developer rebuilding the Reference Dataset, I want a documented offline builder to consume pinned and checksummed Open Food Facts and Open Prices Parquet inputs, so that the shipped catalog can be reproduced without crawling an API or hand-authoring products.
24. As a developer running the Reference App, I want production composition to install and open the generated SQLite catalog and provenance manifest from app resources, so that the UI and model tools use the same genuine bundled product data without a runtime download.
25. As a developer studying Foundation Models, I want meaningful intents and orchestration phases represented by actual `DynamicProfile` configurations, so that model, instruction, tool, and session-setting changes use the framework behavior being demonstrated.
26. As a developer studying context composition, I want `DynamicInstructions` to be re-evaluated for each request and expose only currently relevant instructions and tools, so that dynamic behavior is observable rather than simulated with one fixed prompt and every tool loaded.
27. As a developer comparing Hybrid Orchestration, I want baton-pass to transition profiles within shared session history while phone-a-friend uses an independently owned child session, so that the two Foundation Models patterns differ in real transcript ownership rather than only in app-authored labels.

## Implementation Decisions

- Use a plain, checked-in native Xcode project with one app target and local Swift packages. Do not introduce Tuist or XcodeGen for milestone one.
- Organize application behavior across GroceryDomain, GroceryData, GroceryModels, and GroceryComposition. Keep concrete use cases in the Domain-facing design, use manual dependency injection, and keep public/private repository seams narrow.
- Treat the Primary Interaction Loop as the main application seam. It receives a grocery request and the selected Demo Household, retrieves catalog and App-Owned Context through tools, selects only relevant instructions and tools, produces an answer, and may return a Cart Proposal.
- Establish three parallel foundation deliverables before the first vertical slice: the native shell/package graph; a reproducible catalog artifact and GRDB-backed local data adapter; and deterministic Demo Household generation plus reset flows.
- Build the first runnable vertical slice only after those foundations are available. It contains local-only Foundation Models orchestration, catalog and household tools, Model Run/Trace presentation, and explicit Cart Proposal approval. It uses no OpenAI model.
- Treat Product Catalog Delivery as an end-to-end build-and-runtime contract. A documented offline builder consumes locally supplied Open Food Facts and Open Prices Parquet files whose immutable revisions and checksums are pinned, filters and joins them, normalizes textual barcodes, and emits a deterministic SQLite Reference Dataset plus a machine-readable provenance manifest. The app never downloads or processes the upstream Parquet datasets at runtime.
- Package the generated SQLite database and matching provenance manifest as versioned app resources. Production composition must use these artifacts; an in-memory or hard-coded catalog is permitted only as a test or preview fixture and does not satisfy Product Catalog Delivery.
- On first launch, validate the bundled artifact and copy it into Application Support; on subsequent launches, open the installed version through GRDB. The Local Data Store owns the bundled product catalog, generated household histories, pantry and cart state, cached live products, and Model Trace records. Demo reset regenerates fictional household state without rebuilding or mutating the public catalog.
- Target roughly 3,000 quality-gated France/EUR products. Use local SQLite indexes and full-text search for interactive catalog access. Reserve Open Food Facts API v3 for an optional lookup of a specifically requested product missing from the snapshot, apply the same validation semantics, and cache successful public results separately. Core demonstrations and generated Demo Household references must never depend on this network fallback.
- Provide the three Initial Demo Households: Budget Family, Nutrition-Focused Couple, and Low-Waste Solo Shopper. Their state is fictional, deterministic, and references bundled product identifiers.
- Maintain the local-only privacy guarantee: no prompt, App-Owned Context, or tool result leaves the device under the local-only Model Strategy.
- Add Claude after the local-only slice. Runtime developer-key entry is stored only in Keychain; no credential is committed, bundled, or required for local-only behavior. App Attest is an optional physical-device experiment, not a milestone-one prerequisite.
- Use actual Foundation Models `DynamicProfile` and `DynamicInstructions` APIs for intent-driven orchestration. A profile represents a meaningful intent or phase and may choose a local or remote model, dynamically composed instructions and tools, and session settings. `DynamicInstructions` are re-evaluated before each model request and include only task-relevant instructions and tools. Demo Households remain App-Owned Context and must not become profiles.
- Allow application state or a model-directed tool call to transition the active `DynamicProfile`. Record the active profile, transition trigger, effective instructions, available tools, selected model, and final-answer responsibility in Model Trace. A provider-neutral profile enum or fixed `LanguageModelSession` instructions alone do not satisfy this requirement.
- Build Hybrid Orchestration in a fixed order: baton-pass first, then phone-a-friend. Baton-pass uses a `DynamicProfile` transition within a shared Foundation Models session history and makes that disclosure visible. Phone-a-friend creates a short-lived child `LanguageModelSession` with an independently owned transcript, a validated Remote Task, and only permitted context and tools.
- Do not treat `DynamicProfile` or `DynamicInstructions` as a privacy boundary. Deterministic app-owned policy must construct and validate every remote payload, and private tools must be absent from remote profiles and child sessions rather than merely discouraged by instructions.
- Render an exact Remote Context View for each remote invocation from the final semantic request immediately before transport encoding. It includes effective instructions, transformed history or Remote Task, disclosed tool definitions and outputs, selected options, and omission/disclosure facts; it excludes credentials, raw authorization headers, and hidden reasoning.
- Make Model Trace an app-owned, expandable developer-facing record. Include selected Model Strategy and Orchestration Pattern, Demo Household, active profiles/transitions, instructions, tool calls, Remote Context Views, privacy concerns, safe timing and usage fields, correlation identifiers, errors, and approval identifiers. Do not persist raw private telemetry outside the explicit inspectable context view, secrets, or chain-of-thought.
- Make Model Run a chronological record of verbatim observable model and tool output with concise collapsed intermediate content, expandable complete observable output, and a visually dominant final answer. It is not a chat transcript or app-authored reasoning explanation.
- Cart Proposals are structured and non-mutating. Only explicit user approval applies a proposed change to the local Demo Household cart.
- Use Manual Demo Scenarios as acceptance evidence for local purchase analysis, hybrid substitutions and pantry-aware planning, cart review/approval, cross-household personalization, and comparable baton-pass and phone-a-friend runs. Do not add formal quality scores, exact generated-prose assertions, or production hardening matrices.
- After milestone-one Manual Demo Scenarios are complete, add the custom OpenAI LanguageModelExecutor inside the Reference App. It is an adapter at the existing Foundation Models provider seam; GroceryDomain, orchestration-adapter interfaces, tool ownership, disclosure enforcement, and Model Run presentation remain unchanged.
- The OpenAI adapter targets the Responses API, operates statelessly with Foundation Models as transcript and client-tool owner, uses streaming, maps supported strict schemas and function tools, publishes allow-listed safe metadata, and fails closed for unsupported transcript segments, schemas, options, hosted tools, background work, or ambiguous provider behavior.
- The OpenAI adapter does not use OpenAI-managed conversation state, silently truncate or summarize context, retry streamed requests automatically, expose hidden reasoning, or treat a direct API key as a release-build credential. Any direct credential use is limited to an opt-in development smoke check.
- No standalone OpenAI beta-seam prototype is part of this work. Any necessary OpenAI exploration belongs to the milestone-two Reference App implementation and starts only after milestone one.

## Testing Decisions

- Test behavior at the highest seam available: repeatable Manual Demo Scenarios through the running Reference App, with the Model Trace as the primary observable evidence. A good test verifies user-visible answers, proposals, state changes after approval, disclosed remote context, and safe trace facts—not private implementation structure or exact generated prose.
- Exercise production app composition at the Primary Interaction Loop seam. A catalog scenario must start from the packaged SQLite and provenance resources, cover first-launch installation, find a genuine bundled product through the same GRDB path used by UI and model tools, and prove that Demo Household references resolve against that artifact. A hard-coded fixture cannot serve as this acceptance evidence.
- Use Model Trace as the observable seam for dynamic behavior. Representative local-only, baton-pass, and phone-a-friend scenarios must expose the active `DynamicProfile`, transition trigger, effective `DynamicInstructions`, available tools, selected model, transcript ownership, disclosed remote context, and final-answer responsibility.
- Use focused package-level tests beneath the app seam for GroceryDomain use cases, catalog/household repositories, generated data reproducibility, artifact and manifest validation, first-launch database installation, GRDB queries, Cart Proposal validation and approval, and local reset behavior.
- Test model behavior through a provider-neutral fake at the existing provider seam. Automated tests must never require a live Claude or OpenAI credential.
- Add conformance-style adapter tests for the OpenAI executor in milestone two: transcript ordering, history transforms, supported and rejected schemas, tool modes/call identities, streaming text/tool deltas, usage/metadata, cancellation, incomplete responses, and normalized errors.
- Test that local-only behavior produces no Remote Context View or remote transport request, and that every hybrid remote invocation has an inspectable Remote Context View matching the semantic request while excluding secrets.
- Test baton-pass and phone-a-friend as different observable Orchestration Patterns: shared-history disclosure for the former, isolated child-session disclosure and bounded Remote Task validation for the latter.
- Test failure and setup behavior externally: unavailable model conditions, missing Claude configuration, visible generic error behavior, error facts in Model Trace, and no automatic silent fallback or retry.
- Verify that the offline builder produces byte-identical catalog and manifest artifacts from identical pinned inputs, rejects checksum mismatches, satisfies row and coverage expectations, supports indexed queries, and emits only Demo Household-resolvable product identifiers. Also verify that the generated artifacts are present in the app resources used by production composition.
- Use Manual Demo Scenarios as the principal acceptance suite, retaining developer-only Foundation Models Instruments traces as sensitive, non-committed supplemental evidence.

## Out of Scope

- Production grocery storefront behavior, checkout, account backend, retailer integrations, or a custom catalog backend.
- Real customer transaction imports, real personal household data, or a requirement for users to upload their own data.
- Apple Private Cloud Compute.
- Camera capture, barcode scanning, and product-photo recognition in milestone one.
- Shipping credentials; putting API keys in build settings, the app bundle, or source control; or requiring live credentials for automated tests.
- Bundling the complete Open Food Facts corpus or making the core demo network-dependent.
- Downloading or processing Open Food Facts/Open Prices bulk datasets on app launch, using a custom catalog backend, or substituting a hard-coded catalog in production composition.
- Creating one Foundation Models profile per Demo Household, treating dynamic instructions as static prompt decoration, or loading every tool for every request.
- Production-grade retry, fallback, availability, partial-result, or resilience policies beyond a visible generic failure and Model Trace error facts.
- Formal model-quality metrics, benchmark thresholds, mandated run counts, or exact generated-text assertions.
- A standalone throwaway OpenAI executor prototype.
- OpenAI work before the Apple-plus-Claude milestone-one Manual Demo Scenarios are complete.
- OpenAI hosted/server tools, managed conversation state, background jobs, images/files/custom segments, silent schema degradation, hidden transcript truncation, or chain-of-thought display.

## Further Notes

- This spec synthesizes the completed Wayfinder map, especially the resolved architecture, ingestion, observability, hybrid-boundary, Thin Reference Shell, Demo Household, OpenAI executor, and implementation-sequence decisions.
- The `DynamicProfile` and `DynamicInstructions` decision from resolution #2 remains in force. Only its earlier prescription to isolate every Claude invocation was superseded; the clarified design deliberately demonstrates both shared-history baton-pass and isolated phone-a-friend behavior.
- Completing the offline builder alone does not complete Product Catalog Delivery. The generated SQLite and provenance artifacts must also be packaged, installed, opened through GRDB, and selected by production composition.
- The app requires the documented Xcode 27/iOS or iPadOS 27 Foundation Models environment for the complete Apple-plus-Claude path; hardware, language, region, and account availability remain explicit Manual Demo Scenario checks.
- The intended implementation order is: parallel foundations; local-only vertical slice; Claude integration; baton-pass; phone-a-friend; milestone-one Manual Demo Scenarios; then the in-app OpenAI executor adapter.
- The running app through production composition and the Primary Interaction Loop is the principal acceptance seam; focused package seams should exist only where necessary to make artifact generation, installation, dynamic-session behavior, and state changes deterministic and testable.
