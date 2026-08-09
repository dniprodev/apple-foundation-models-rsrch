# Grocery Shopping Assistant

A functional, open-source iOS grocery app that uses real product data and fictional account state to demonstrate how local and remote generative-AI models can be used and combined.

## Language

**Reference App**:
An open-source, functional iOS grocery app that provides useful product discovery, meal planning, and cart assistance while making its AI architecture understandable and reproducible for developers.
_Avoid_: Developer laboratory, benchmark suite, disconnected demos

**Research Experiment**:
A supporting investigation used to choose or validate how a user-facing capability should employ models. It informs the Reference App but is not its primary navigation or product structure.
_Avoid_: Product feature, main app section

**Primary Interaction Loop**:
The assistant interprets a grocery-related request, retrieves the relevant catalog and App-Owned Context, activates only the instructions and tools needed for that intent, produces an evidence-backed answer, and optionally performs a user-approved cart action. Different requests reuse this loop rather than following one hard-coded journey.
_Avoid_: Fixed demo journey, general-purpose chat, disconnected feature demo

**Cart Proposal**:
A structured, non-mutating suggestion for changing a Demo Household's cart. A model may produce a Cart Proposal, but only an explicit user action may apply it.
_Avoid_: Model-executed cart mutation, implicit cart update

**Model Run**:
The readable record of one active request: a chronological sequence of verbatim observable model and tool outputs culminating in a visually dominant final answer. Intermediate excerpts stay concise by default, complete observable outputs remain expandable, and hidden chain-of-thought is never presented as an explanation.
_Avoid_: Chat transcript, app-authored reasoning summary, chain-of-thought display, debug log

**Model Strategy**:
The user-selected policy for a request. Local-only guarantees that no prompt, context, or tool result leaves the device; hybrid allows local and remote models to cooperate through a demonstrated Orchestration Pattern whose effective remote context is inspectable.
_Avoid_: Model picker, provider toggle

**Provider Plan**:
Apple's on-device system model and Claude, integrated through Anthropic's `ClaudeForFoundationModels` package, are the first-milestone models used to research and demonstrate Foundation Models orchestration. A custom OpenAI `LanguageModelExecutor` is a committed second milestone for studying provider integration without blocking the primary demo; Apple Private Cloud Compute is excluded because its access conditions cannot be assumed for this project.
_Avoid_: Requiring PCC, exposing provider choice as the normal user workflow, assuming one orchestration pattern before demonstrating its behavior

**Hybrid Orchestration**:
The research subject and visible demo of how Foundation Models combines local and remote models through dynamic profiles and model-directed tool calls. It covers both shared-history baton-pass and isolated phone-a-friend behavior without treating either as predetermined; any App-Owned Context made visible to a remote model is surfaced as an explicit privacy concern rather than silently assumed safe.
_Avoid_: Predetermined orchestration winner, hidden model transitions, claiming privacy without inspecting the effective remote context

**Orchestration Pattern**:
A named arrangement for model collaboration whose transcript ownership, profile transitions, tools, and final-answer responsibility can be observed and compared. The initial patterns are baton-pass, where profiles share one session history, and phone-a-friend, where a parent consults a short-lived child session with independent history.
_Avoid_: Provider routing, interchangeable implementation detail

**Remote Task**:
An app-owned structured request used when an Orchestration Pattern explicitly hands a bounded unit of work to another model. It is an inspectable input and experiment variable, not a universal requirement or an automatic privacy guarantee.
_Avoid_: Sanitized prompt, remote transcript, disclosure guarantee

**Remote Context View**:
The exact effective context presented to a remote model for one invocation: transformed history, instructions, prompt or Remote Task, attachments, and available tool definitions and outputs. It makes shared private context and other privacy implications visible for inspection rather than deciding whether that disclosure is acceptable.
_Avoid_: Privacy guarantee, sanitized summary, inferred disclosure

**Model Trace**:
An expandable developer-facing section attached to each otherwise normal grocery answer. In the first milestone it exposes the selected Model Strategy and Orchestration Pattern, Demo Household, active profiles and model transitions, instructions and tool calls, the Remote Context View for every Claude invocation, privacy concerns, timing, available token usage, and errors.
_Avoid_: Debug-console-first UI, requiring Xcode to understand the orchestration, hiding shared history or what crossed the model boundary

**Observability Strategy**:
Two complementary surfaces make behavior inspectable: app-owned Model Trace records for the running app and developer-only Foundation Models Instruments traces, treated as sensitive artifacts. Manual Demo Scenarios exercise the important local-only and hybrid paths without quality metrics or formal pass thresholds. The app owns stable correlation, provider, profile, instruction, remote-context, timing, error, and approval identifiers rather than expecting portable provider metadata.
_Avoid_: Persisting raw private prompts in telemetry, committing Instruments traces, formal model-quality benchmarks, treating missing token metadata as zero

**Dynamic Behavior**:
Foundation Models dynamic profiles represent meaningful phases or intents and may select different local or remote models, instructions, and tools. App state or a model-directed tool call can transition the active profile; `DynamicInstructions` narrow the current context and capabilities, while a Demo Household remains app data rather than a profile.
_Avoid_: One profile per household, loading every tool for every request, treating dynamic instructions as static prompt decoration, hiding model-directed profile transitions

**Initial Demo Households**:
Three switchable, deterministic fixtures reference real catalog products: a Budget Family with two adults, two children, a weekly spending target, and a peanut allergy; a Nutrition-Focused Couple with lactose intolerance and lower-sugar/lower-sodium priorities; and a Low-Waste Solo Shopper who is vegetarian, buys small portions, and prioritizes existing pantry stock. Their exact transaction histories are generated rather than manually authored.
_Avoid_: Hand-writing hundreds of transactions, coupling household identities to dynamic profiles, requiring real personal transaction imports

**Product Catalog Delivery**:
A reproducible, versioned snapshot generated from pinned official Open Food Facts and Open Prices Parquet revisions ships with the app for deterministic demonstrations, offline use, and fast local tools. The builder normalizes text barcodes, filters and joins sources offline, and emits checksummed SQLite plus a provenance manifest. An optional Open Food Facts API v3 lookup handles a specific requested product missing from the snapshot and caches successful public results locally. Generated household histories reference bundled product IDs so the primary demo never depends on network availability. The project operates without a custom catalog backend.
_Avoid_: Bundling the entire upstream dataset, hand-authoring products, network-dependent demo fixtures, maintaining a bespoke catalog service

**Claude Authentication**:
Local-only operation requires no credential. For development and simulator demos, a developer may enter their own Anthropic API key at runtime; the app stores it in Keychain and never bundles or commits it. Anthropic App Attest authentication is supported and documented as an optional physical-device experiment, not a first-milestone prerequisite. Hybrid mode remains unavailable with a clear setup message until a Claude authentication method is configured. Automated tests use a fake provider and no live credentials.
_Avoid_: Committed secrets, API keys in build settings or the app bundle, requiring Claude to explore the local demo, live-provider-dependent tests

**Local Data Store**:
The dataset builder produces a prebuilt SQLite database, and the app accesses it through GRDB. On first launch the database is copied into Application Support, where it holds the bundled product catalog, generated household histories, pantry and cart state, cached live products, and model traces. Indexed queries and full-text search back the model tools. Demo resets regenerate fictional household state without requiring the catalog to be rebuilt.
_Avoid_: SwiftData for the bulk catalog, loading the catalog into memory, separate persistence implementations for tools and UI

**Deferred Capture Inputs**:
Milestone one supports natural-language catalog lookup and manual product/barcode entry but excludes camera capture, barcode scanning, and product-photo recognition. These may be added after the primary Apple-plus-Claude demo through the existing product lookup boundary.
_Avoid_: Camera permissions and capture UI in milestone one, coupling catalog tools to a particular input method

**Manual Demo Scenario**:
A repeatable request used to exercise and inspect an important local-only or hybrid path: local purchase analysis; hybrid substitutions and pantry-aware planning; cart review with user-approved changes; cross-household personalization; or comparable baton-pass and phone-a-friend runs. A scenario demonstrates behavior through its Model Trace; it does not impose model-quality metrics, run counts, or formal pass thresholds.
_Avoid_: Acceptance benchmark, hard-coded prompt button as the product boundary, exact generated-prose assertion

**Reference Dataset**:
A large, legally reusable collection used to demonstrate, test, and evaluate the Reference App at realistic scale. It combines genuine product records with a Shopping History Dataset when real customer activity cannot be safely obtained or redistributed.
_Avoid_: Fixture data, sample records, demo JSON

**Shopping History Dataset**:
A reproducible collection of fictional carts, purchases, preferences, and pantry state that references genuine products from the Reference Dataset. It supplies realistic App-Owned Context without requiring a production commerce backend.
_Avoid_: Random cart fixtures, real customer records, unrelated product IDs

**Demo Household**:
A selectable fictional household with its own members, restrictions, preferences, purchase history, pantry, feedback, and cart. Multiple Demo Households exercise different private-context and recommendation scenarios; “profile” is reserved for Foundation Models `DynamicProfile` configurations.
_Avoid_: User profile, model profile, real household

**Evidence Workspace**:
A persistent, locally governed collection of private user material and retrieved public records that the app can search, relate, and selectively disclose to a model.
_Avoid_: Chat history, prompt attachments, context dump

**Context Advantage**:
The product value created by combining app-owned context with tools and repeatable workflows, especially when the data is too private, numerous, dynamic, or inconvenient to reproduce in a general-purpose chat.
_Avoid_: Chat wrapper, larger prompt

**App-Owned Context**:
Personal or account data the app can legitimately access, such as a cart, purchase history, tasks, bookings, location, or photos. It may be stored on-device or retrieved from the app's backend, but the user should not need to restate it in a prompt.
_Avoid_: Uploaded context dump, manually copied profile

**Thin Reference Shell**:
The smallest demoable mobile surface needed to expose grocery App-Owned Context, run the Primary Interaction Loop, and make a Model Run readable, with model inspection and any proposed actions remaining secondary. It is an AI reference interface, not a simulation of a production grocery storefront.
_Avoid_: Production clone, backend simulation platform, disconnected prototype screen
