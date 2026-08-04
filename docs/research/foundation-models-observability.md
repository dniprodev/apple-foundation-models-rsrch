# Foundation Models observability and evaluation constraints

Research snapshot: 2026-08-04. This report resolves [Wayfinder issue #4](https://github.com/dniprodev/apple-foundation-models-rsrch/issues/4). It uses current Apple iOS/Xcode 27 beta documentation and Anthropic's official package source pinned to commit [`98a74ff`](https://github.com/anthropics/ClaudeForFoundationModels/tree/98a74ff2300996ff192062c25114aea8c4103d2b) (package version 0.1.4).

## Decision summary

The project needs three complementary observability surfaces:

1. **Model Trace:** app-owned, persisted, sanitized facts that make each demo request explainable without Xcode.
2. **Foundation Models Instrument:** development-time inspection of the exact framework flow and performance. It is not an in-app API or a production telemetry source.
3. **Reference Acceptance Suite:** deterministic invariant tests plus aggregate evaluations of probabilistic model behavior. It must not compare generated prose verbatim.

The public framework provides transcripts, tool-call structure, request/response metadata dictionaries, and token usage. It does not provide an in-app timing breakdown or semantic names for the app's profiles/dynamic-instruction branches. The app must own correlation IDs, provider/profile/instruction identifiers, disclosure decisions, wall-clock timing, tool timing, normalized errors, and action-approval state.

## What Instruments provides

With Xcode 27 and a current OS, the Foundation Models Instruments template records Foundation Models activity for any model used through the framework. Its timeline has Session, Request, Instructions, Model Inference, Tool, and Model Loading lanes. Its tree organizes sessions, requests, inferences, instructions, prompts, responses, tool calls, and errors. [Apple runtime-performance article](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app) · [WWDC26 session 243](https://developer.apple.com/videos/play/wwdc2026/243/)

For a model inference, Instruments exposes:

- instructions, prompt, response, and errors;
- total duration and response-generation duration;
- time to first token, tokens per second, and total latency;
- total, consumed-input, generated-output, and cached-token counts;
- tool name, timing, and output;
- the duration for which a resolved instruction/tool set was active.

This is sufficient to diagnose a missing dynamic handoff, unexpected tool loop, excessive context, cache regression, or provider-independent latency problem. Apple explicitly says the instrument supports any Foundation Models provider. [Apple runtime-performance article](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app) · [WWDC26 session 243](https://developer.apple.com/videos/play/wwdc2026/243/)

### Instruments constraints

- Instruments is an interactive developer tool, not a documented runtime API for feeding Model Trace or automated assertions.
- A trace stores prompts and responses unencrypted and may contain sensitive data. Apple says recording is disabled in production and enabled for the trace duration; trace files must be handled as sensitive artifacts. They must not be committed to this open-source repository. [Apple runtime-performance article](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app)
- Timing is affected by device performance state and thermal pressure. Use a named physical-device/OS/model configuration for performance comparisons; simulator measurements are functional evidence, not performance baselines. [Apple runtime-performance article](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app) · [Apple Foundation Models code-along](https://developer.apple.com/videos/play/wwdc2025/259/)
- Instruments can show the rendered instruction/tool set, but the app still needs stable semantic IDs such as `nutrition-and-restrictions` and `allergy-protection` for user-facing trace and tests.

## Public runtime data

### Transcript

`LanguageModelSession.transcript` is a public linear record whose entries cover instructions, prompts, reasoning, tool calls, tool outputs, and responses. `structuredTranscript` groups tool calls, outputs, and responses into typed arrays and is the input Apple demonstrates for tool-call evaluations. [Apple `Transcript`](https://developer.apple.com/documentation/foundationmodels/transcript) · [Apple `structuredTranscript`](https://developer.apple.com/documentation/foundationmodels/transcript/structuredtranscript) · [Apple tool-call evaluation article](https://developer.apple.com/documentation/evaluations/evaluating-tool-calling-behavior)

A completed `LanguageModelSession.Response` exposes its content, raw `GeneratedContent`, response-scoped usage, and the transcript entries produced by that call. Prompt entries have an ID plus generation/context options and app-supplied metadata; response and tool-call entries can carry provider-produced metadata dictionaries. [Apple `LanguageModelSession.Response`](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/response) · [Apple `Transcript.Prompt`](https://developer.apple.com/documentation/foundationmodels/transcript/prompt/id) · [Apple `Transcript.Response`](https://developer.apple.com/documentation/foundationmodels/transcript/response) · [Apple `Transcript.ToolCall`](https://developer.apple.com/documentation/foundationmodels/transcript/toolcall)

The transcript is therefore a useful post-request audit source, but it has no documented timestamps, profile names, or dynamic-instruction component identities. Reasoning entries must not be presented as an authoritative explanation of a decision; Model Trace should explain observable orchestration and evidence instead.

### Request correlation metadata

The iOS 27 response APIs accept an app-supplied metadata dictionary. Apple attaches it to the prompt and passes it in `LanguageModelExecutorGenerationRequest`, which also contains a request UUID intended for logging/tracing. Use only non-sensitive values such as a random trace ID, acceptance-scenario ID, and schema version. [Apple metadata-enabled `respond`](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/respond(to:generating:options:contextoptions:metadata:)) · [Apple executor generation request](https://developer.apple.com/documentation/foundationmodels/languagemodelexecutorgenerationrequest)

Do not rely on this metadata reaching a provider's wire API. Anthropic's current request builder does not consume the framework request ID or metadata when constructing a Messages API request. [Anthropic `RequestBuilder.swift`](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/Sources/ClaudeForFoundationModels/RequestBuilder.swift)

### Token usage

Both a response and a session expose `LanguageModelSession.Usage`; session usage increases monotonically across responses. It separates input and output usage, includes cached input and reasoning output fields, and provides a metadata dictionary. [Apple response usage](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/response/usage) · [Apple session usage](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/usage-swift.property) · [Apple total-token definition](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/usage-swift.struct/totaltokencount)

Anthropic's current bridge reports final input tokens as uncached input plus cache-read plus cache-creation tokens, reports cached input separately, reports output tokens, and always reports zero reasoning tokens. Its per-delta token values are placeholders to enable streaming snapshots; final boundary updates are authoritative. [Anthropic `EventTranslator.swift`](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/Sources/ClaudeForFoundationModels/EventTranslator.swift)

Model Trace may show final input/output/cached totals when present. It must render unavailable values as unavailable, not zero-cost or zero-work. In particular, Claude's zero reasoning-token value is not evidence that no reasoning occurred.

### Provider metadata

Foundation Models allows provider executors to publish response, reasoning, and tool-call metadata through generation-channel events. The keys are provider-defined; Apple does not document a portable set beyond the typed token usage fields. [Apple generation channel](https://developer.apple.com/documentation/foundationmodels/languagemodelexecutorgenerationchannel) · [Apple channel metadata](https://developer.apple.com/documentation/foundationmodels/languagemodelexecutorgenerationchannel/metadata)

Anthropic's current translator does not publish successful message ID, model ID, stop reason, or request ID as response metadata. It uses metadata only to mark an internal redacted-thinking entry; a provider request ID appears only in error detail when supplied by the API. The app already knows the configured Claude model and should record it itself. [Anthropic `EventTranslator.swift`](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/Sources/ClaudeForFoundationModels/EventTranslator.swift) · [Anthropic `ErrorMapper.swift`](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/Sources/ClaudeForFoundationModels/ErrorMapper.swift)

## App-owned instrumentation

Persist a single sanitized `ModelTraceRecord` per user request and child-model phase. The model must not author this record.

| Signal | Collection point | Constraint |
| --- | --- | --- |
| Trace/request ID | Generated before orchestration; also passed as prompt metadata | Random, non-sensitive, stable across local and remote phases |
| Model strategy and provider/model ID | Orchestrator configuration | Record requested strategy and actual phases separately |
| Demo Household | App selection | Store fixture ID/display name, not the full private context |
| Intent/profile ID | Deterministic intent/profile selection state | Use stable semantic IDs, not rendered prompt text |
| Dynamic-instruction IDs | The same conditions that compose `DynamicInstructions` | Record active rule IDs and reasons; do not infer them later from prose |
| Request boundaries | `ContinuousClock` immediately around `respond`/stream iteration | Store start, first snapshot, completion/cancellation/error |
| Tool lifecycle | Profile callbacks plus an instrumented tool wrapper | Store tool name, sanitized argument/result summary, start/end, status; wrapper is authoritative for duration/errors |
| Disclosure decision | Deterministic `RemoteTask` validator | Store candidate hash, approved serialized payload, rejected fields/categories, and decision reason |
| Remote invocation | Immediately before constructing the isolated Claude session | Store configured model/auth mode category; never store credential material |
| Token usage | Completed response `usage`; session totals for cross-check | Provider semantics differ; preserve input/output/cached/reasoning fields individually |
| Transcript evidence | Response `transcriptEntries` or post-call transcript delta | Persist only the sanitized fields needed by Model Trace; raw private transcript stays in app data |
| Error | Catch at orchestration, provider, and tool boundaries | Normalize category while retaining a safe debug description; record partial-stream status |
| Cart action | Preview creation and UI approval/commit boundary | Prove no mutation occurred before approval |

Dynamic profiles provide `onActivate`, `onDeactivate`, `onPrompt`, `onResponse`, `onToolCall`, and `onToolOutput` lifecycle modifiers. Nested callbacks accumulate, and thrown callback errors propagate to the response call. Instrumentation callbacks must therefore be non-throwing in practice and send events to a concurrency-safe recorder. [Apple `DynamicProfile`](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/dynamicprofile) · [Apple dynamic sessions article](https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles)

Public APIs do not expose an in-app time-to-first-token or duration property. Measure total latency around the request and time to first visible snapshot while consuming `streamResponse`. Do not call this measurement identical to Instruments' provider-level time to first token until a prototype shows they align; app measurement also includes framework scheduling and UI-consumer overhead.

## Reference Acceptance Suite

### Test layers

#### 1. Deterministic contract tests

Use fake model/provider responses and stub tools in ordinary Swift tests. These are release-blocking and assert exact invariants:

- local-only makes zero network/provider calls;
- no original prompt, private tool definition/output, household field, or forbidden identifier appears in the captured Claude request;
- disclosure validation rejects any non-allow-listed or oversized `RemoteTask`;
- remote sessions receive only the approved payload and public tool definitions;
- tool/database arithmetic is exact for the versioned fixture;
- cart state cannot mutate before explicit approval;
- trace events correlate to one request and never contain credentials;
- failure, cancellation, retry, and partial-stream paths do not duplicate actions.

These are software properties and should be 100% reliable. Do not delegate them to a model-as-judge.

#### 2. Model behavior evaluations

Apple's Evaluations framework integrates datasets, generated subjects, programmatic/model judges, aggregate metrics, and Swift Testing. For tool behavior, `ToolCallEvaluator` consumes `structuredTranscript` and can assert ordered, unordered, and disallowed calls, flexible argument matchers, and whether additional calls are permitted. It reports strict all-pass and percentage-pass metrics. [Apple `Evaluation`](https://developer.apple.com/documentation/evaluations/evaluation) · [Apple language-model evaluation article](https://developer.apple.com/documentation/evaluations/evaluating-language-model-responses) · [Apple tool-call evaluation article](https://developer.apple.com/documentation/evaluations/evaluating-tool-calling-behavior)

Run live local and Claude evaluations against a versioned dataset grouped into golden, edge, adversarial, and known-failure cases. Apple warns that a happy-path-only dataset creates false confidence. [Apple dataset design guidance](https://developer.apple.com/documentation/evaluations/designing-evaluation-datasets)

Prefer code-based evaluation for criteria derivable from catalog/household fixtures:

- returned product IDs exist in the catalog snapshot;
- price/savings totals equal deterministic calculations;
- recommendations violate no allergy/diet exclusion;
- pantry-aware missing lists exclude products already present;
- evidence references correspond to tools actually called;
- generated structures decode and pass app validation;
- expected/disallowed tool trajectories and disclosure categories are respected.

Use a model judge only for irreducibly qualitative dimensions such as clarity, relevance, or usefulness. Apple recommends narrow observable dimensions, small scales, and calibration against 20–50 human-scored responses until judge-human agreement is comparable to human-human agreement. Until that calibration exists, judge scores are exploratory, not release gates. [Apple model-judge design guidance](https://developer.apple.com/documentation/evaluations/designing-effective-model-judges) · [Apple model-judge scoring article](https://developer.apple.com/documentation/evaluations/scoring-with-model-as-judge-evaluators)

#### 3. Device performance runs

Use Instruments for diagnosis and an app-owned benchmark harness for repeatable numeric exports. Pin device, OS build, model/package version, dataset version, thermal state, and whether the model was cold/prewarmed. Compare distributions across multiple runs rather than a single duration. Establish latency/token budgets only after a baseline exists; do not invent universal thresholds.

### Scenario assertions

The six reference scenarios should assert observable outcomes, not exact prose:

| Scenario | Hard assertions | Aggregate model metrics |
| --- | --- | --- |
| Private purchase analysis | No remote phase; only private/local tools; cited products and calculations exist in fixture | Relevant anomalies/savings found; unnecessary calls rate |
| Hybrid healthier substitutions | Remote payload passes disclosure validator; Claude gets no private tools/data; prohibited products never reach display | Remote-routing rate, public-tool trajectory score, evidence completeness, recommendation usefulness |
| Pantry-aware planning | Missing-product set excludes pantry stock; dietary exclusions enforced | Plan feasibility, missing-list completeness, tool trajectory score |
| Cart review/action | Only a preview before approval; committed changes exactly match approved preview | Conflict-detection recall, valid replacement rate, unnecessary replacement rate |
| Household comparison | Correct fixture selected and trace records its active restrictions/instructions | Answers use household-specific evidence/constraints; no requirement for different wording |
| Privacy comparison | Local-only has zero remote events; hybrid shows the exact approved `RemoteTask` and excluded categories | Capability/evidence score by strategy; no requirement that one prose answer be longer or stylistically different |

Hard safety and privacy assertions remain zero-tolerance application checks. Generated-behavior criteria are evaluated across the dataset (and, where affordable, repeated runs) with thresholds chosen from an initial baseline and then held constant for regression comparison.

## What not to assert

- Exact generated strings, paragraph ordering, or product ordering when several choices satisfy the constraints.
- That the model always follows one hidden reasoning path.
- That a tool must be called when the same evidence is already validly available, unless the scenario explicitly requires fresh grounding with `toolCallingMode.required`.
- Exact local-versus-Claude token equivalence; tokenizers and provider accounting differ.
- A universal latency number across simulator, device, OS/model update, cold/warm state, or network conditions.
- Claude request ID, stop reason, success metadata, or reasoning-token counts that its current bridge does not publish.
- Instruments data as proof of the production privacy boundary; the captured outbound request and deterministic disclosure tests provide that proof.

## Prototype checks before finalizing the trace schema

1. Verify which Apple and Claude transcript metadata keys are actually populated in the selected Xcode 27 beta; treat undocumented keys as optional.
2. Compare app-measured request start/first snapshot/end with Instruments' time-to-first-token and total latency.
3. Verify lifecycle callback ordering for nested profiles, repeated/concurrent tool calls, cancellation, and errors.
4. Confirm response usage versus session-usage deltas for local and Claude streaming/non-streaming requests.
5. Capture an Instruments trace for local and Claude requests and verify the documented lanes/data appear for both providers.
6. Prove the trace sanitizer removes private tool results, credentials, raw reasoning, and disallowed household fields before SQLite persistence/export.
7. Run a small `ToolCallEvaluator` suite against both providers and confirm their `structuredTranscript` entries are equivalent enough for shared evaluators.

## Resulting scope

Milestone one should build a small concurrency-safe trace recorder and trace schema alongside orchestration, not derive Model Trace later from the raw transcript. Instruments remains a developer diagnostic, and the Evaluations framework supplies aggregate quality/regression reports. This division makes the demo explainable in-app while keeping privacy, correctness, and performance claims independently verifiable.
