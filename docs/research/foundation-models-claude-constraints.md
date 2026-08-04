# Foundation Models and Claude integration constraints

Research snapshot: 2026-08-04. This report resolves [Wayfinder issue #2](https://github.com/dniprodev/apple-foundation-models-rsrch/issues/2). Apple labels the iOS 27 Foundation Models surface documented here as beta, and Anthropic labels its package beta as well. The package source observations are pinned to commit [`98a74ff`](https://github.com/anthropics/ClaudeForFoundationModels/tree/98a74ff2300996ff192062c25114aea8c4103d2b) (package version 0.1.4), rather than an unversioned branch.

## Decision summary

- Use `LanguageModelSession` as the common application-facing API for the on-device system model and `ClaudeLanguageModel`. Anthropic's type conforms to Apple's `LanguageModel` protocol and declares tool calling, vision, reasoning, and guided generation according to the selected Claude model's capabilities. [Apple `LanguageModel`](https://developer.apple.com/documentation/foundationmodels/languagemodel) · [Anthropic `ClaudeLanguageModel.swift`](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/Sources/ClaudeForFoundationModels/ClaudeLanguageModel.swift)
- Keep the original request, household data, and private-tool results in the local session. Invoke Claude through a short-lived child `LanguageModelSession` built only from the disclosure-approved `RemoteTask` and public tools. Apple's “phone-a-friend” pattern explicitly uses a child session with an isolated transcript; a model switch inside one dynamic session otherwise shares transcript history. [WWDC26 session 242, “phone-a-friend” and profiles](https://developer.apple.com/videos/play/wwdc2026/242/)
- Use intent-driven `DynamicProfile` and `DynamicInstructions` for local orchestration, but do not treat them as a security boundary. Their bodies are re-evaluated before requests and their tool/instruction composition is dynamic; deterministic application code must still construct and validate the remote payload. [Apple dynamic sessions article](https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles)
- Support API-key authentication only as a developer/simulator path. Keep the key in app-managed Keychain storage, never in source or the bundle. Keep App Attest as a physical-device experiment. Anthropic also exposes proxy authentication, but a backend is outside the first milestone. [Anthropic README: authentication](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/README.md#authentication)
- Treat provider-neutral response content, transcript entries, and token totals as usable. Treat Claude request IDs, stop reasons, success-side provider metadata, and reasoning-token counts as unavailable through the package's current public bridge; record app-known provider/model/profile/tool/timing data separately.

## Documented Apple behavior

### Model and session abstraction

`LanguageModel` is a lightweight provider description: it exposes declared capabilities and an executor configuration. Its associated `LanguageModelExecutor` translates the framework request to the provider and streams events back. A `LanguageModelSession` is the stateful context and retains prompts, responses, reasoning, tool calls, and tool outputs in its transcript. A custom provider is passed to the same session initializer as Apple's model. [Apple `LanguageModel`](https://developer.apple.com/documentation/foundationmodels/languagemodel) · [Apple `LanguageModelExecutor`](https://developer.apple.com/documentation/foundationmodels/languagemodelexecutor) · [Apple `LanguageModelSession`](https://developer.apple.com/documentation/foundationmodels/languagemodelsession)

Capabilities must be checked, not assumed. Apple says the framework can reject a request before dispatch when the selected model does not advertise the required capability, using `LanguageModelError.unsupportedCapability`. [Apple `LanguageModelCapabilities`](https://developer.apple.com/documentation/foundationmodels/languagemodelcapabilities)

### Dynamic profiles and instructions

Apple defines three layers:

1. `DynamicInstructions` re-evaluates before every model request and composes instructions, client-side tools, and nested dynamic instructions.
2. A profile combines those instructions/tools with session settings such as model and reasoning level.
3. A `DynamicProfile` maintains one active profile and coordinates transitions while the session retains shared state.

The dynamic body is therefore runtime configuration, not a one-time session initializer. Apple advises keeping only task-relevant instructions and tools and preserving their relative position for prompt-cache performance. [Apple dynamic sessions article](https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles) · [WWDC26 session 242](https://developer.apple.com/videos/play/wwdc2026/242/)

This supports the Reference App's intent-driven local profiles. It also means private tools must be absent—not merely discouraged—in every remote profile or child session.

### Transcript and history transforms

`Transcript` is the linear session record. Its `history` view excludes only a leading instructions entry and includes subsequent prompts, responses, reasoning, tool calls, and tool outputs. A session can be rehydrated from selected transcript entries. [Apple `Transcript`](https://developer.apple.com/documentation/foundationmodels/transcript) · [Apple `Transcript.history`](https://developer.apple.com/documentation/foundationmodels/transcript/history)

`historyTransform` gives a profile a per-request, non-destructive view of history; Apple explicitly presents trimming irrelevant entries and redacting private entries before switching to a less-private model as use cases. Mutating the built-in history session property is instead lossy and affects all profiles. Dynamic instructions affect the instructions entry, while a history transform affects the remaining entries. [Apple dynamic sessions article](https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles) · [WWDC26 session 242](https://developer.apple.com/videos/play/wwdc2026/242/)

These APIs enable redaction but do not prove it complete. The app's hard privacy guarantee should use an isolated remote session and an allow-listed `RemoteTask`; a history transform may remain a defense-in-depth test target.

### Generated content

`@Generable` produces a schema-backed Swift type; `@Guide` supplies descriptions and programmatic constraints. Schema text consumes context, and Apple recommends small types, clear property names, and only useful guides. `GeneratedContent` can carry scalar, array, or keyed structured values and exposes JSON plus completion state. [Apple `Generable`](https://developer.apple.com/documentation/foundationmodels/generable) · [Apple `GeneratedContent`](https://developer.apple.com/documentation/foundationmodels/generatedcontent)

Generated structures are appropriate for `RemoteTask`, product evidence, recommendation candidates, and cart-change previews. They are not a privacy validator: the app must inspect the generated value and deterministically accept or reject it before networking.

### Client-side tools

A `Tool` is app code with generated arguments and `PromptRepresentable` output. The framework includes the tool definition in model context, executes the call, and returns its output for subsequent reasoning. Tools are `Sendable` and may be invoked concurrently; thrown tool errors are wrapped as `LanguageModelSession.ToolCallError`. Tool calling can be `.allowed`, `.required`, or `.disallowed` per generation request. [Apple `Tool`](https://developer.apple.com/documentation/foundationmodels/tool) · [Apple tool-calling article](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling) · [Apple `Tool.call`](https://developer.apple.com/documentation/foundationmodels/tool/call(arguments:))

Consequences for the app:

- Public catalog tools can be supplied to either provider.
- Household/history/pantry/cart tools belong only to the local session.
- Mutating tools should produce a preview; ordinary app UI performs the final commit after user approval.
- Tool implementations and trace collectors need concurrency-safe state.

### Streaming, usage, and errors

`streamResponse` exposes an async sequence of cumulative partial snapshots, including typed partial generated content. The provider executor emits incremental channel events; the channel completes when its `respond` method returns or throws. [Apple `LanguageModelSession`](https://developer.apple.com/documentation/foundationmodels/languagemodelsession) · [Apple generation channel](https://developer.apple.com/documentation/foundationmodels/languagemodelexecutorgenerationchannel)

The session publishes accumulated `usage`, including input, output, total token counts, and a metadata dictionary. The custom-provider channel can update entry metadata and token usage. [Apple session total token count](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/usage-swift.struct/totaltokencount) · [Apple generation-channel metadata](https://developer.apple.com/documentation/foundationmodels/languagemodelexecutorgenerationchannel/metadata)

Common model failures use `LanguageModelError`, including context overflow, rate limiting, refusal, timeout, guardrail violation, unsupported capability/content/guide, and unsupported language or locale. Session misuse and tool failures have session-specific errors. A session's beta transcript error policy can either preserve a possibly partial final entry or revert to the state before the failed request. [Apple `LanguageModelError`](https://developer.apple.com/documentation/foundationmodels/languagemodelerror) · [Apple `TranscriptErrorHandlingPolicy`](https://developer.apple.com/documentation/foundationmodels/transcripterrorhandlingpolicy)

### Local-model availability and test destinations

`SystemLanguageModel.availability` must be checked at runtime. Documented unavailable reasons are Apple Intelligence disabled, device ineligible, and model not ready. [Apple availability reasons](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum/unavailablereason)

Apple demonstrates the on-device model in iPhone and visionOS simulators when the host Mac has Apple Intelligence enabled and ready. Apple also warns that simulator performance is not representative of physical-device performance. Therefore simulator tests are useful for functionality, while latency, memory, energy, and App Attest validation require hardware. [WWDC25 Foundation Models code-along](https://developer.apple.com/videos/play/wwdc2025/259/)

## Observations from Anthropic's current source

These are implementation observations at commit `98a74ff`, not Apple API guarantees and not promises about later package releases.

### Supported surface and request translation

The package requires iOS/macOS/visionOS/watchOS 27 and Swift tools 6.2. `ClaudeLanguageModel` declares capabilities from a `ClaudeModel` capability matrix; the current built-in models advertise client tool calling, image input, adaptive reasoning where supported, and guided generation. [Anthropic `Package.swift`](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/Package.swift) · [Anthropic `ClaudeModel.swift`](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/Sources/ClaudeForFoundationModels/ClaudeModel.swift)

The executor translates all six known transcript entry kinds: instructions, prompt, reasoning, tool calls, tool output, and response. It converts client tool definitions and their argument schemas to Anthropic tool definitions. Image attachments are supported; unknown attachment kinds are skipped. Unknown transcript entries are ignored. Non-Anthropic custom segments fall back to their string description. [Anthropic `RequestBuilder.swift`](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/Sources/ClaudeForFoundationModels/RequestBuilder.swift)

The implication is that framework-level transcript compatibility is broad but not lossless for future/unknown segment types. Avoid relying on custom transcript segments for the disclosure contract.

### Guided generation details

For guided generation, the bridge converts Apple's `GenerationSchema` into strict JSON Schema and sends it through Claude constrained decoding when the selected model advertises structured output. It removes unsupported or framework-specific keys, including `minimum`, `maximum`, `minItems`, `maxItems`, and `pattern`, and notes that the Foundation Models layer validates `@Guide` bounds after decoding. If the selected Claude model lacks structured output, the bridge throws `LanguageModelError.unsupportedGenerationGuide` instead of silently degrading. [Anthropic `RequestBuilder.swift`](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/Sources/ClaudeForFoundationModels/RequestBuilder.swift)

Therefore schemas shared between Apple and Claude should initially use simple objects, enums, required fields, and bounded app validation. Exact parity for array/range guides needs a prototype.

### Tool and reasoning behavior

Client-side tool definitions come from the active framework request. `.required` maps to Anthropic `tool_choice: any`, `.disallowed` maps to `none`, and `.allowed` uses the API default. Required tool use disables Claude thinking for that request because the Messages API combination is rejected. Reasoning levels map `.light/.moderate/.deep` to `low/medium/high`; unsupported levels are dropped as hints, while a configured `fixedEffort` is treated as a contract. Sampling options are also capability-gated and are dropped when adaptive thinking is active. [Anthropic `RequestBuilder.swift`](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/Sources/ClaudeForFoundationModels/RequestBuilder.swift)

Anthropic server-side tools are separate model configuration and run remotely. They are not Foundation Models client tools. The first milestone should omit them to keep the privacy and trace story limited to public catalog tools controlled by the app. [Anthropic README: server-side tools](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/README.md#server-side-tools)

### Streaming and metadata behavior

The bridge maps Anthropic SSE text, thinking, tool calls, and server-tool activity into Foundation Models generation-channel events. It reports cumulative input totals as uncached input plus cache reads plus cache creation, reports cached input separately, and reports output tokens. It currently sets reasoning-token count to zero. Per-delta token counts are placeholders used to trigger partial snapshots; authoritative totals arrive at message boundaries. [Anthropic `EventTranslator.swift`](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/Sources/ClaudeForFoundationModels/EventTranslator.swift)

The translator does not currently publish successful response model ID, message ID, stop reason, or request ID into public response metadata. Its only metadata update marks internal redacted-thinking replay state. Request IDs are retained in error descriptions. Consequently, Model Trace must record configured provider/model and app timings itself, and must label reasoning-token count and provider request ID as unavailable unless the package changes.

### Authentication

The package supports:

- `.apiKey(String)`: suitable for simulator iteration, but the package explicitly warns that a bundled key is extractable.
- `.appAttest(clientID:)`: no shipped secret or developer backend; requires a registered team/bundle ID, App Attest entitlement, Secure Enclave, and a physical device.
- `.proxied(headers:)`: an app-owned relay adds provider credentials; outside the current no-backend scope.

The package does not persist API keys for the app. It stores App Attest key identifiers and short-lived bearer tokens in the data-protection Keychain as after-first-unlock, this-device-only items. `authenticateIfNeeded()` reports attestation failure; `prewarm()` starts it as a best-effort task and discards errors. [Anthropic README: App Attest](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/README.md#app-attest) · [Anthropic `AppAttestStore.swift`](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/Sources/ClaudeForFoundationModels/AppAttestStore.swift) · [Anthropic `ClaudeExecutor.swift`](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/Sources/ClaudeForFoundationModels/ClaudeExecutor.swift)

The app should gate hybrid mode on its own credential state. `LanguageModel` has provider capabilities but no common network/auth availability contract, and `ClaudeLanguageModel` does not add one; invalid credentials and reachability surface at authentication/request time.

### Error mapping and partial streams

The bridge maps timeouts, rate limit/overload, context overflow, and unsupported images/guides to corresponding `LanguageModelError` cases. Context-size errors currently carry unknown numeric limits (`0`), and rate-limit errors carry no reset date. Authentication failures become `ClaudeError.missingCredential` for API key/proxy or `ClaudeError.attestationFailed` for App Attest; unsupported attestation is its own `ClaudeError`. Other provider errors pass through without a public provider-specific enum suitable for exhaustive app switching. [Anthropic `ErrorMapper.swift`](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/Sources/ClaudeForFoundationModels/ErrorMapper.swift) · [Anthropic `ClaudeError.swift`](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/Sources/ClaudeForFoundationModels/ClaudeError.swift)

For App Attest only, the executor retries one authentication rejection if no generation-channel content has been written. It does not retry after partial content because that could duplicate output. App UI must therefore handle a failed stream with partial output according to the chosen transcript error policy. [Anthropic `ClaudeExecutor.swift`](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/Sources/ClaudeForFoundationModels/ClaudeExecutor.swift)

## Required specification constraints

1. **Deployment:** milestone one requires Xcode 27 and iOS 27. All of these APIs and the provider package are beta and may require source changes between seeds.
2. **Provider isolation:** the local session owns the raw prompt and every private tool. The Claude session is constructed from a validated `RemoteTask`; it receives only public tools. No shared transcript is passed to it.
3. **Disclosure enforcement:** allow-list fields and product identifiers in deterministic Swift code. Reject unknown fields, private identifiers, free-form dumps, and oversized payloads. Generated structures describe a candidate payload but do not authorize it.
4. **Dynamic behavior:** dynamic local profiles select only the tools and instructions needed for the detected intent. Household identity remains tool-accessed data, not a profile.
5. **Actions:** models may recommend and preview cart mutations; UI code commits only after explicit user approval.
6. **Capability gates:** check on-device availability and selected-model capabilities before a request. Gate Claude separately on configured authentication and handle runtime network/provider failure.
7. **Schema portability:** keep cross-provider `@Generable` schemas simple and validate every decoded value in application code.
8. **Trace ownership:** persist app-known strategy, profile, dynamic-instruction identifiers, tool lifecycle, disclosed payload, configured model, wall-clock timings, session usage, and normalized errors. Never claim unavailable Claude reasoning tokens or request metadata.
9. **Test split:** use fakes for deterministic automated orchestration tests; use simulator for functional model/API-key iteration; use eligible physical hardware for local performance and App Attest.

## Assumptions that require prototypes

These items are plausible from documentation/source but are not sufficiently guaranteed for the specification without executable evidence:

1. **Package/API compatibility:** compile package 0.1.4 against the exact Xcode 27 beta selected by the project and run one text response for each provider.
2. **Isolated handoff:** capture the Claude request at a fake transport and prove that the original prompt, household fields, and private tool definitions/results are absent while the approved `RemoteTask` and public catalog tool definitions are present.
3. **Dynamic reevaluation:** change intent and household-derived conditions between turns and verify active instructions/tools change as expected without stale capabilities.
4. **Cross-provider generated content:** generate the same small `@Generable` `RemoteTask` and recommendation schema locally and with Claude; test enum, optional, array-count, range, malformed, and validation-failure cases.
5. **Tool modes and concurrency:** verify `.required`, `.allowed`, and `.disallowed` for both providers, including repeated and concurrent tool calls and a thrown tool error.
6. **History/error policy:** fail a Claude stream after partial text and compare preserve/revert behavior; verify cancellation and retry do not duplicate transcript entries or cart previews.
7. **Usage semantics:** compare session totals before/after local and Claude calls; confirm cached input behavior and that no success metadata beyond what the package currently emits is assumed.
8. **Runtime matrix:** exercise an eligible physical iPhone, an Apple-Intelligence-ready simulator host, missing/invalid API-key cases, and App Attest unsupported/failure/success paths.

## Confidence boundary

The common `LanguageModelSession` API, dynamic configuration, client tools, structured output, streaming, and transcript mechanics are documented Apple beta APIs. Claude support for those mechanics is evidenced by Anthropic's official beta source. Privacy isolation, cross-provider behavioral parity, exact error-time transcript behavior, and beta-seed compatibility remain application properties that must be established by the prototypes above.
