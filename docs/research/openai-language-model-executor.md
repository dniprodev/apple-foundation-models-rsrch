# OpenAI `LanguageModelExecutor` integration

Research snapshot: 2026-08-06. OpenAI API schema: OpenAPI 2.3.0; public API version header documented as `2020-10-01`. Target Apple SDK: Xcode 27 / iOS 27 beta, Swift 6.2. Target OpenAI model: `gpt-5.6-sol` through `POST /v1/responses`. [OpenAI Responses create reference](https://developers.openai.com/api/reference/resources/responses/methods/create) · [OpenAI API overview](https://developers.openai.com/api/reference/overview)

This report decides milestone two of the Grocery Shopping Assistant. It is a design, not an implementation. Apple’s iOS 27 Foundation Models APIs are beta, so every exact Swift symbol and event shape below remains subject to a compile-and-smoke proof with the selected Xcode 27 seed. OpenAI facts were refreshed from live official documentation on the snapshot date. The skill-local latest-model resolver failed twice with `fetch failed`; the official OpenAI documentation service was available and its live `latest-model.md` named `gpt-5.6-sol` and linked the GPT-5.6 migration and prompting guides used here. [OpenAI current model guide](https://developers.openai.com/api/docs/guides/latest-model) · [GPT-5.6 Sol migration guide](https://developers.openai.com/api/docs/guides/upgrading-to-gpt-5p6-sol) · [GPT-5.6 prompting guide](https://developers.openai.com/api/docs/guides/prompt-guidance-gpt-5p6)

## Decision

Build a small first-party Swift package, `OpenAIForFoundationModels`, with three deep boundaries:

1. `OpenAILanguageModel` describes the configured OpenAI model, declared Foundation Models capabilities, remote endpoint, and authorization mode.
2. `OpenAILanguageModelExecutor` translates the effective Foundation Models request into a stateless OpenAI Responses request, consumes its SSE stream, and emits Foundation Models generation-channel events.
3. `OpenAIResponsesTransport` owns HTTP, authorization, SSE decoding, response headers, and cancellation. Production and tests inject different transports or sessions without changing transcript translation.

Do not add a community Swift OpenAI SDK. OpenAI’s official SDK page lists JavaScript, Python, .NET, Java, and Go as official SDKs and lists Swift only under community libraries; OpenAI explicitly permits calling the HTTP API directly. A narrow `URLSession` transport avoids an unnecessary dependency and lets the executor preserve OpenAI event and header semantics precisely. [OpenAI SDKs and libraries](https://developers.openai.com/api/docs/libraries) · [OpenAI API overview](https://developers.openai.com/api/reference/overview)

Use the Responses API, which OpenAI recommends for new projects and for reasoning, tool-using, multi-turn workflows. Pin the model ID to `gpt-5.6-sol`, rather than the moving `gpt-5.6` alias, so Model Trace and repeatable scenarios identify the model actually requested. The live model page describes Sol as the frontier GPT-5.6 model and currently documents text/image input, text output, streaming, Structured Outputs, and function calling. Images remain outside the initial executor capability despite model support because Foundation Models attachment translation has not been proved. [Responses migration guide](https://developers.openai.com/api/docs/guides/migrate-to-responses) · [GPT-5.6 Sol model page](https://developers.openai.com/api/docs/models/gpt-5.6-sol)

Every request sets `store: false` and reconstructs OpenAI `input` from the complete effective Foundation Models transcript. Do not use Conversations, `previous_response_id`, background responses, or a provider-side thread. OpenAI stores Responses by default and documents both manual replay and provider-managed chaining; manual replay is the only design that keeps `LanguageModelSession` as the canonical transcript after profile changes, history transforms, cancellation, restoration, or switching between local and remote models. It also makes the exact Remote Context View derivable before networking. [OpenAI conversation state](https://developers.openai.com/api/docs/guides/conversation-state) · [Apple provider integration session](https://developer.apple.com/videos/play/wwdc2026/339/)

Set `reasoning.context` explicitly to `current_turn` initially. GPT-5.6 otherwise defaults to persisted reasoning across turns, and OpenAI says stateless clients seeking reasoning continuity must replay every output item, including encrypted reasoning items. Foundation Models does not yet have a documented, provider-neutral container that can round-trip an opaque OpenAI reasoning item exactly. Silently maintaining such state inside the executor would split transcript ownership; serializing hidden reasoning into ordinary assistant text would leak or distort it. This is an intentional quality/caching degradation in exchange for honest transcript semantics. Revisit only after a proof shows an opaque custom segment can survive profile changes, transcript restoration, and history transforms without entering Model Trace. [OpenAI current model guide](https://developers.openai.com/api/docs/guides/latest-model) · [OpenAI conversation state](https://developers.openai.com/api/docs/guides/conversation-state)

## Package and configuration

The intended public shape is:

```swift
public struct OpenAILanguageModel: LanguageModel, Sendable {
    public let modelID: String                 // default: "gpt-5.6-sol"
    public let authorization: OpenAIAuthorization
    public let endpoint: OpenAIEndpoint        // direct or transparent relay
    public let reasoning: OpenAIReasoningPolicy

    public var capabilities: LanguageModelCapabilities { /* tool calling,
        guided generation, reasoning; text input/output only */ }
    public var executorConfiguration: OpenAILanguageModelExecutor.Configuration
}

public protocol OpenAIAuthorization: Sendable {
    func authorizationHeader() async throws -> String
    var traceCategory: String { get }           // never the credential
}

public protocol OpenAIResponsesTransport: Sendable {
    func stream(
        _ request: OpenAIResponsesRequest,
        authorization: String,
        clientRequestID: String
    ) async throws -> OpenAIResponseStream
}
```

These names are design-level; Xcode proof may adjust syntax to the exact beta protocol. The invariants are more important:

- `executorConfiguration` is a `Hashable & Sendable` value containing endpoint identity, timeout policy, transport policy identifier, and schema/translator version, but no API key. Apple caches one executor per distinct configuration and passes the selected model on each request, so authorization can remain on the model while safe connection/parser resources live in the cached executor. [Apple provider integration session](https://developer.apple.com/videos/play/wwdc2026/339/)
- The configuration default is HTTPS `https://api.openai.com/v1`, Responses endpoint `/responses`, explicit `gpt-5.6-sol`, `store: false`, `reasoning.effort: medium`, `reasoning.context: current_turn`, and no reasoning summary. GPT-5.6 documentation calls `medium` the balanced default; the app should later tune it only from evaluations. [OpenAI current model guide](https://developers.openai.com/api/docs/guides/latest-model)
- `prewarm` performs no network request and never fetches credentials. It may initialize the JSON encoder/SSE parser or connection session. Apple says prewarm is not guaranteed to run, so `respond` remains fully self-sufficient. [Apple provider integration session](https://developer.apple.com/videos/play/wwdc2026/339/)
- Endpoint override exists for the transparent relay and fake server. It is not a general arbitrary-host option in production builds; allow-list HTTPS origins to prevent credential exfiltration.
- The app supplies the Foundation Models request UUID as ASCII `X-Client-Request-Id`. OpenAI documents this header for correlating requests even when no server request ID returns; the executor also records the server `x-request-id` response header. Neither identifier is secret. [OpenAI API debugging](https://developers.openai.com/api/reference/overview#debugging-requests)

### Authentication

The shippable mode is a transparent app-owned relay: the app authenticates to its relay with a short-lived app credential, and the relay owns the OpenAI API key. The relay forwards only the approved Responses contract and SSE events. OpenAI says API keys are secrets and must not be exposed in client-side apps; Apple likewise recommends a token provider or sign-in flow instead of a string API-key initializer for cloud model packages. [OpenAI authentication](https://developers.openai.com/api/reference/overview#authentication) · [Apple provider integration session](https://developer.apple.com/videos/play/wwdc2026/339/)

A `DEBUG`-only direct-key provider may exist solely for a developer-owned smoke test. It reads an uncommitted, user-entered key from Keychain at call time, never places the key in `Configuration`, logs, metadata, errors, request snapshots, or Model Trace, and displays that direct mobile API-key use is not a deployable authentication design. It must not compile into Release. The app’s OpenAI hybrid mode remains unavailable with an actionable setup message until either the relay or the debug-only provider is configured. Automated tests never use a live credential.

The relay implementation and account backend remain outside this planning ticket. The milestone-two executor must nevertheless define and test the relay contract; otherwise the only runnable path would contradict OpenAI’s client-secret guidance.

## Transcript and request mapping

Apple says an executor receives the full transcript on every request and translates six entry kinds—instructions, prompt, response, reasoning, tool calls, and tool output—plus context and generation options. Foundation Models’ one-shot and streaming APIs both ultimately consume executor channel events. [Apple provider integration session](https://developer.apple.com/videos/play/wwdc2026/339/)

The translator is a pure function returning both `OpenAIResponsesRequest` and `RemoteContextView`. It preserves source entry IDs and order in an internal mapping table but sends only OpenAI-supported fields.

| Foundation Models input | OpenAI Responses representation | Rule |
| --- | --- | --- |
| Leading instructions entry | top-level `instructions` | Render text exactly after the active `DynamicInstructions`/profile has resolved. If the beta SDK can produce more than one instruction segment, concatenate with explicit segment boundaries and preserve the pieces in Remote Context View. |
| Prompt text | `input` message with role `user` and `input_text` | Preserve order and text exactly. |
| Prior response text | `input` message with role `assistant` and `output_text`/the accepted assistant input form | Preserve only observable response content, not trace decorations. The exact accepted item variant is an Xcode/OpenAPI proof item. |
| Prior tool call | `function_call` input item | Preserve tool name, JSON arguments, and call correlation. Maintain a deterministic table from Foundation Models call ID to OpenAI `call_id`; never invent a different ID on later replay. |
| Tool output | `function_call_output` input item | Link by the mapped `call_id`; serialize `PromptRepresentable` output exactly as the framework exposes it. Tool failures become an explicit safe tool result only when Foundation Models represents them in the transcript. |
| Reasoning entry from any provider | omitted | Never serialize reasoning as an assistant message. Record an omission marker and source entry ID in Remote Context View, without its content. `current_turn` makes this loss explicit. |
| Text attachment | corresponding text part when representable | Initial scope is text only. |
| Image, file, or unknown/custom segment | reject with `unsupportedTranscriptContent` | Do not silently stringify or skip it; add vision only after a fidelity/privacy proof. |

This mapping deliberately does not send app prompt metadata as model input. Safe correlation values travel in `X-Client-Request-Id` and app trace state. Apple’s metadata dictionary is provider-defined plumbing, not a reason to disclose arbitrary app metadata remotely. Apple explicitly allows an executor to approximate an option only when it still honors developer intent; otherwise it should throw a built-in `LanguageModelError`. [Apple provider integration session](https://developer.apple.com/videos/play/wwdc2026/339/)

### Guided generation

When `request.schema` is present, convert Apple’s `GenerationSchema` into OpenAI Responses `text.format` with `type: json_schema`, a stable schema name, and `strict: true`. OpenAI Structured Outputs supports only a JSON Schema subset, requires all object fields to be required, requires `additionalProperties: false`, and rejects unsupported strict schemas. The translator must preflight the converted schema and throw `LanguageModelError.unsupportedGenerationGuide` before networking when fidelity is impossible. It must never fall back silently to JSON mode or prompt-only formatting. [OpenAI Structured Outputs guide](https://developers.openai.com/api/docs/guides/structured-outputs#supported-schemas) · [Responses migration guide](https://developers.openai.com/api/docs/guides/migrate-to-responses)

The first supported intersection is objects, arrays, strings, numbers, integers, booleans, enums, nullable fields represented by `null`, and nested definitions after dereferencing or proven `$ref` translation. Keep deterministic app validation after decoding: schema adherence does not authorize a Cart Proposal or a Remote Task and does not enforce domain facts.

Advertise `.guidedGeneration` only when the package’s schema translator is enabled. A failing schema should fail the individual request, not cause a best-effort unstructured response.

### Client-side tools

Translate each active Foundation Models `Tool` definition to an OpenAI function tool with its exact name, description, and JSON argument schema. Set `strict: true` after the same schema preflight. OpenAI recommends strict function schemas; function calls and outputs are separate Responses items correlated by `call_id`. [OpenAI function-calling guide](https://developers.openai.com/api/docs/guides/function-calling) · [Responses migration guide](https://developers.openai.com/api/docs/guides/migrate-to-responses)

Map Foundation Models tool-calling intent exactly:

- `.allowed` → `tool_choice: "auto"`;
- `.required` → `tool_choice: "required"`;
- `.disallowed` → `tool_choice: "none"` and omit tool definitions if the beta request does not expose them as usable.

Leave `parallel_tool_calls` enabled only if the Xcode proof shows the framework preserves multiple concurrent calls and their IDs; otherwise set it to `false` for milestone two. The executor never runs client tools itself. It streams the model’s tool-call deltas to Foundation Models, returns, and lets `LanguageModelSession` invoke the registered Swift tool and call the executor again with the resulting transcript. This preserves Foundation Models as the orchestration and tool-lifecycle owner. OpenAI documents the same multi-step application-owned tool loop. [OpenAI function-calling flow](https://developers.openai.com/api/docs/guides/function-calling#the-tool-calling-flow) · [Apple provider integration session](https://developer.apple.com/videos/play/wwdc2026/339/)

Do not expose OpenAI hosted tools, MCP, web search, code interpreter, computer use, custom free-form tools, Programmatic Tool Calling, or background mode in this milestone. Those activities would bypass the app-owned Foundation Models tool boundary or require new transcript segment semantics. Public catalog access remains a Foundation Models client tool; private household/history/pantry/cart tools remain governed by the selected Orchestration Pattern.

### Generation options

- Map `maximumResponseTokens` to `max_output_tokens` exactly.
- Map `.greedy` to the closest documented sampling form only if GPT-5.6 accepts it with the selected reasoning setting; otherwise throw rather than pretend. Apple explicitly gives greedy-to-zero-temperature as an example of an honest approximation, but GPT-5.6 parameter compatibility still needs a live proof. [Apple provider integration session](https://developer.apple.com/videos/play/wwdc2026/339/)
- Map Foundation Models reasoning `.light`, `.moderate`, and `.deep` provisionally to OpenAI `low`, `medium`, and `high`. Do not expose `xhigh`, `max`, or Pro through the provider-neutral API. Verify exact Xcode enum cases and model acceptance.
- Do not set both temperature and top-p automatically. Unsupported sampling requests throw a provider-specific, user-readable `OpenAIExecutorError.unsupportedGenerationOption` unless a built-in Foundation Models error fits.
- No automatic truncation. Let context overflow map to `LanguageModelError.contextSizeExceeded`; silent truncation would make Remote Context View differ from the actual semantic request.

## Streaming, cancellation, and completion

Use HTTP SSE with `stream: true`. OpenAI documents typed semantic events, including response creation/completion, output text deltas, and function-call argument deltas. Apple expects the executor to send metadata first, usage updates, then response deltas; its session accumulates those deltas for both streaming and one-shot callers. [OpenAI streaming guide](https://developers.openai.com/api/docs/guides/streaming-responses) · [OpenAI Responses streaming events](https://developers.openai.com/api/reference/resources/responses/streaming-events) · [Apple generation channel](https://developer.apple.com/documentation/foundationmodels/languagemodelexecutorgenerationchannel)

Event mapping:

| OpenAI event/header | Foundation Models channel / app action |
| --- | --- |
| HTTP `x-request-id` and `response.created` | Send response metadata containing namespaced `openai.response_id`, `openai.request_id`, actual model ID, API schema version, and translator version. Never include headers wholesale. |
| `response.output_text.delta` | Append text immediately; token count remains unknown until authoritative usage arrives. |
| function-call item added / argument delta / done | Create and update the corresponding Foundation Models tool call using stable entry and call IDs. Buffer incomplete JSON only until enough data exists for the beta channel event required by Foundation Models. |
| reasoning summary events | Do not request them initially; if unexpectedly present, discard content and record only `reasoning_summary_present: true` in safe metadata. |
| `response.completed` | Publish final input, cached-input, output, and reasoning-token usage, actual model, status, and completion timing; then return. |
| `response.incomplete` | Publish safe status/usage, then throw a mapped limit/interruption error; do not present partial output as complete. |
| `response.failed` or SSE error event | Map and throw as below. |
| unknown event | Ignore only when it cannot contain a new output item; otherwise fail closed with a safe unsupported-event error so output is not silently lost. |

Cancellation of the Swift task must cancel the active `URLSessionTask`/byte stream immediately and rethrow `CancellationError`; it is not a timeout and must not be retried. The parser checks cancellation between SSE frames and before every channel send. After cancellation it sends no further channel event. Whether the partial transcript entry remains or rolls back is controlled by the session’s selected `TranscriptErrorHandlingPolicy`, which Apple provides for failed requests. [Apple dynamic-agent session](https://developer.apple.com/videos/play/wwdc2026/242/) · [Apple provider integration session](https://developer.apple.com/videos/play/wwdc2026/339/)

No request is automatically retried in the initial implementation. In particular, never retry after any text/tool delta, because doing so can duplicate observable output or actions. A later retry policy may retry connection establishment only when the transport proves no response headers or bytes were received and the caller opts in.

## Error contract

Decode the structured OpenAI error body and retain `x-request-id`, HTTP status, provider error `type`, `code`, and `param` in an internal safe error. Never include authorization headers, request bodies, raw private prompts, or tool outputs in error descriptions.

Prefer standard Foundation Models errors where semantics match, as Apple recommends: context-length rejection → `contextSizeExceeded`; 429 → `rateLimited` with reset information when available; model refusal → `refusal`; policy/guardrail rejection → `guardrailViolation`; unsupported content/capability/schema/language → the corresponding unsupported case; transport deadline → `timeout`. OpenAI documents 401 authentication failures, 429 rate limits/quota failures, and 5xx service errors, while its response headers expose request and rate-limit identifiers. [OpenAI error guide](https://developers.openai.com/api/docs/guides/error-codes) · [OpenAI API debugging](https://developers.openai.com/api/reference/overview#debugging-requests) · [Apple provider integration session](https://developer.apple.com/videos/play/wwdc2026/339/)

Use a small custom `OpenAIExecutorError` only for provider-specific states with no honest framework equivalent:

- `missingAuthentication` / `invalidAuthentication` (401);
- `permissionDenied` or `modelNotProvisioned` (403/404 when applicable);
- `quotaExceeded` when a 429 is billing quota rather than rate limiting;
- `requestRejected(status:type:code:)` for a safe 4xx not covered above;
- `serviceUnavailable(requestID:)` for 5xx;
- `malformedResponse` and `unsupportedStreamEvent` for protocol failures.

Cancellation remains `CancellationError`. Never map a decoding bug, missing credential, or server outage to a model refusal. If failure follows partial output, attach only a `partialOutput: true` fact to trace/error metadata and let the transcript error policy decide preservation.

## Orchestration Pattern and transcript ownership

The executor does not choose baton-pass or phone-a-friend. It faithfully serializes the effective transcript handed to it; the orchestrator owns session topology.

### Baton-pass

The local and OpenAI profiles inhabit one `LanguageModelSession`. A profile tool changes the active profile, and the OpenAI executor receives the shared effective history after any configured `historyTransform`. Apple defines baton-pass as collaboration with full transcript visibility and with the receiving profile responsible for the final response. Therefore App-Owned Context already in the effective history can cross the remote boundary; this is a visible privacy concern, not a privacy guarantee. [Apple dynamic-agent session](https://developer.apple.com/videos/play/wwdc2026/242/)

OpenAI receives no server-side thread ID and retains no app-owned canonical history: each call is a stateless serialization of that effective history. On return, Foundation Models appends OpenAI response/tool-call entries to the shared transcript. A later local profile can see them through the same session.

### Phone-a-friend

The local parent tool creates a short-lived child `LanguageModelSession` using `OpenAILanguageModel`, remote-specific instructions, one validated Remote Task prompt, and only explicitly selected public tools. The child transcript is independent. Its final observable answer is returned to the parent as tool output, and the parent produces the final answer. This matches Apple’s documented phone-a-friend ownership. [Apple dynamic-agent session](https://developer.apple.com/videos/play/wwdc2026/242/)

The disclosure validator remains app-owned and deterministic. A generated Remote Task is merely a candidate. The validator allow-lists fields and identifiers, limits size, and rejects private household/history/pantry/cart content not authorized for that experiment before creating the child session.

## Exact Remote Context View

Create `RemoteContextView` from the final serialized request value immediately before the transport attaches authorization and encodes JSON. It is not reconstructed later from the Foundation Models transcript and not authored by a model. This makes it the exact semantic context sent remotely while excluding transport secrets.

```text
RemoteContextView
  invocationID, parentTraceID, orchestrationPattern
  provider = "openai"
  endpointOrigin, endpointPath = "/v1/responses"
  modelRequested, store = false
  reasoningEffort, reasoningContext = "current_turn", reasoningSummary = "none"
  instructions: [RenderedSegment { sourceEntryID, exactText }]
  input: [
    RemoteInputItem {
      sourceEntryIDs, openAIType, role?, callID?, toolName?,
      exactTextOrJSON, attachmentDescriptor?
    }
  ]
  tools: [RemoteToolDefinition { name, exactDescription, exactJSONSchema, strict }]
  toolChoice, parallelToolCalls
  responseSchema: { name, exactJSONSchema, strict }?
  maxOutputTokens, mappedSampling
  omittedEntries: [Omission { sourceEntryID, kind, reason }]
  disclosureDecisionID, translatorVersion
```

“Exact” means every semantic body field that can influence generation is shown in stable order using the same in-memory values that the JSON encoder receives. It excludes `Authorization`, relay cookies/tokens, Keychain references, raw HTTP headers, and secrets; it may show the endpoint origin and safe correlation IDs. Reasoning content is never present—only an omission/presence marker. The view records tool outputs verbatim when those outputs are actually disclosed; its UI can collapse them, but the complete value remains expandable as required by Model Run. Hashes supplement but never replace inspectable content.

For baton-pass, the view will usually contain shared prior prompts, responses, and tool results. For phone-a-friend, it will contain only the child instructions, approved Remote Task, public tools, and any child tool loop. This concrete difference is the experiment.

## Model Trace metadata

Use namespaced, allow-listed metadata and the existing app-owned recorder. Apple allows providers to publish response metadata and usage through the generation channel and recommends model/request identifiers first; OpenAI documents response/request IDs and token usage. [Apple provider integration session](https://developer.apple.com/videos/play/wwdc2026/339/) · [OpenAI API debugging](https://developers.openai.com/api/reference/overview#debugging-requests)

Record:

- provider `openai`, configured and actual model IDs, endpoint category (`openai-direct-debug` or `app-relay`), auth category, and API/translator versions;
- Foundation Models request UUID, app trace/invocation IDs, OpenAI response ID, `x-request-id`, and `X-Client-Request-Id`;
- Orchestration Pattern, profile transition, Remote Context View pointer/hash, and disclosure decision;
- request start, headers/created event, first visible text/tool delta, completion/cancellation/error, and transport/app durations;
- final input, cached input, output, and reasoning token fields exactly as OpenAI reports them, each optional rather than defaulted to zero;
- tool names/call IDs, safe status/timing, partial-output state, normalized error category, HTTP status, provider error code, and rate-limit reset facts when present.

Never record API/relay credentials, authorization/cookie headers, raw private local transcript outside the explicit Remote Context View, hidden reasoning, encrypted reasoning payloads, internal chain of thought, full error request bodies, or arbitrary provider headers. Do not request reasoning summaries merely to populate Model Trace. The Model Run explains observable orchestration, evidence, and output; hidden reasoning is not an explanation.

## Explicit rejections and degradations

- **No OpenAI-managed conversation state.** `store: false`; no Conversations or `previous_response_id`. Cost/cache/quality may be worse, but the framework transcript remains authoritative.
- **No cross-turn persisted reasoning initially.** Explicit `current_turn`; no fabricated or exposed reasoning entries.
- **No official Swift SDK claim.** Direct `URLSession` because Swift is currently listed as community support.
- **No Release-build API key in the app.** Production-like use needs a relay; direct key is debug smoke-test scaffolding only.
- **No image/file/custom-segment support initially.** Reject rather than silently stringify or drop.
- **No hosted/server tools or background jobs.** Only Foundation Models client tools.
- **No silent schema downgrade.** Unsupported guided generation or tool schema throws.
- **No automatic retries.** Especially none after any streamed delta.
- **No hidden truncation or transcript summarization in the executor.** Orchestrator-visible history transforms own context reduction.
- **No guarantee of sampling parity.** Unsupported generation settings throw until proved.
- **No provider metadata dump.** Only documented, allow-listed identifiers/usage/timing enter Model Trace.

## Small proof required before implementation tickets

One throwaway Xcode 27 proof is justified because Apple’s beta API signatures are the largest unknown. It should do only this:

1. Compile minimal `OpenAILanguageModel` and executor conformances and print the exact accessible fields/cases of generation request, transcript segments, schema, tool definitions, generation options, and channel actions.
2. Against a local fixture SSE server, prove text deltas, function-call argument deltas, final usage, metadata, cancellation, and thrown errors create the expected `LanguageModelSession` transcript.
3. Prove a supported `@Generable` schema converts to an OpenAI-accepted strict schema and an unsupported guide fails before transport.
4. Prove `.allowed`, `.required`, and `.disallowed` reach the translator, and determine whether parallel calls are faithfully representable.
5. With an explicitly provided debug credential, run four live calls: text streaming, strict guided generation, one client-tool round trip, and cancellation. Record model/response/request IDs and usage, but no content or credentials in committed artifacts.
6. Run one baton-pass and one phone-a-friend invocation and byte-compare each captured HTTP JSON body (minus operational metadata) with its Remote Context View canonical JSON.

The live OpenAI smoke test is an assumption until executed: docs establish the API contract, not account entitlement, model availability for this project, relay behavior, or Xcode’s beta event fidelity. The proof must pin Xcode build, OS build, model ID, OpenAPI version, and date.

## Test specification

### Provider conformance suite

Define a provider-neutral `LanguageModelExecutorConformance` fixture suite and run it against both `OpenAILanguageModelExecutor` with a scripted transport and a minimal scripted fake executor. Where possible, also run the same higher-level scenarios against Apple’s model and the milestone-one Claude bridge without asserting provider-private metadata.

Required cases:

- one-shot and streaming text produce the same final observable content;
- instructions, alternating prompts/responses, every supported tool call/output, and history transforms preserve order;
- unsupported/custom transcript content fails closed;
- generation maximum, reasoning level, and supported/unsupported sampling map as specified;
- guided schema and function schemas pass/fail deterministically; decoded content still undergoes app validation;
- tool modes map exactly; call IDs survive argument streaming, tool execution, output replay, repeated calls, and (if enabled) parallel calls;
- response refusal is distinct from HTTP error, cancellation, timeout, and malformed SSE;
- cancellation before headers, between frames, during text, during tool arguments, and after completion has no late events or retry;
- 400, 401, 403, 404, 408/transport timeout, 429 rate/quota variants, 5xx, malformed error bodies, incomplete responses, and midstream failure map correctly;
- authoritative final usage replaces unknown partial counts; absent token fields remain unavailable;
- request/response IDs and safe metadata are present, while credentials, headers, hidden reasoning, and unapproved context never enter trace or errors.

### Fake transport tests

`ScriptedOpenAIResponsesTransport` captures the typed request and authorization separately and yields an ordered async stream of headers/events/errors under test control. Tests compare the encoder’s canonical body to Remote Context View, fuzz SSE frame boundaries (including UTF-8 split across network chunks), inject unknown events, and assert the HTTP task is cancelled. Golden fixtures should come from the pinned OpenAPI schema, not copied community SDK types.

### Orchestration/privacy tests

- Local-only produces zero OpenAI transport calls.
- Baton-pass sends exactly the transformed shared history and its Remote Context View flags every disclosed App-Owned Context category.
- Phone-a-friend sends only approved Remote Task fields and public tools; the child answer returns as one parent tool output and the parent owns the final response.
- Any difference between encoded request and Remote Context View fails the test.
- Credentials and private local-only tools never appear in either pattern unless an explicit experiment’s deterministic disclosure policy allows the data category.
- Cancellation or failure cannot duplicate a Cart Proposal or cross the UI approval boundary.

Live-provider tests are opt-in smoke tests, never CI gates. Normal CI uses fake transport/provider data and contains no credential or network dependency.

## Documented guarantees versus proof assumptions

Documented guarantees used by the design:

- Foundation Models supplies a model/executor abstraction, caches executors by configuration, hands the executor a full transcript plus options, and receives streaming metadata/usage/text/tool/reasoning events. [Apple provider integration session](https://developer.apple.com/videos/play/wwdc2026/339/)
- Baton-pass shares transcript and transfers final-answer responsibility; phone-a-friend uses an independent child transcript and leaves the final answer to the parent. [Apple dynamic-agent session](https://developer.apple.com/videos/play/wwdc2026/242/)
- Responses is the recommended OpenAI API for new tool-using/reasoning integrations; stateless manual history with `store: false` is supported. [Responses migration guide](https://developers.openai.com/api/docs/guides/migrate-to-responses) · [OpenAI conversation state](https://developers.openai.com/api/docs/guides/conversation-state)
- GPT-5.6 Sol currently supports Responses, streaming, Structured Outputs, and function calling. [GPT-5.6 Sol model page](https://developers.openai.com/api/docs/models/gpt-5.6-sol)
- OpenAI function tools use JSON Schema and correlated call/output items; Structured Outputs uses a documented JSON Schema subset. [OpenAI function-calling guide](https://developers.openai.com/api/docs/guides/function-calling) · [OpenAI Structured Outputs guide](https://developers.openai.com/api/docs/guides/structured-outputs)
- API keys must not be exposed in client apps, and request/rate-limit metadata is available in response headers. [OpenAI API overview](https://developers.openai.com/api/reference/overview)

Assumptions requiring Xcode 27/OpenAI smoke proof:

- the exact Swift accessors and channel actions for tool-call deltas, reasoning, usage, schema, metadata, and cancellation in the chosen beta seed;
- lossless conversion of the app’s actual `@Generable` and Tool schemas into OpenAI’s strict subset;
- a stable way to preserve Foundation Models tool-call identity while satisfying OpenAI `call_id` replay;
- compatibility of the proposed reasoning/sampling options with `gpt-5.6-sol` and the selected tool/structured-output combinations;
- `URLSession` SSE behavior and cancellation timing on the supported iOS 27 simulator/device;
- actual project access to `gpt-5.6-sol`, exact returned metadata/usage fields, and whether relay streaming is byte/event transparent;
- equivalence between app-measured stream timing and any provider/Instrument timing. No equivalence is claimed before measurement.

## Resulting milestone-two scope

Milestone two adds a text-only, stateless OpenAI Responses executor; shippable relay authentication plus a debug-only direct-key smoke path; strict guided generation and client-side tool calling; streaming, cancellation, normalized errors, safe provider metadata, and full fake-transport conformance tests. It reuses the existing Model Strategy, Orchestration Pattern, Remote Task, Remote Context View, Model Run, Model Trace, disclosure validator, and approval boundary. It does not add a provider picker, server-side OpenAI tools, provider-managed threads, multimodal attachments, a backend implementation, or a new product journey.
