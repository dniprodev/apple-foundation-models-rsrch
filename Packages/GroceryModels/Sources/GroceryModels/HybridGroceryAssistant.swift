import Foundation
import GroceryDomain

/// Runs a request through the configured remote provider while keeping setup and
/// provider failures visible in the ordinary Model Run surface.
public struct HybridGroceryAssistant: GroceryAssistant, Sendable {
    private let localAssistant: any GroceryAssistant
    private let provider: any RemoteGroceryProvider

    public init(
        localAssistant: any GroceryAssistant,
        provider: any RemoteGroceryProvider
    ) {
        self.localAssistant = localAssistant
        self.provider = provider
    }

    public func answer(for request: GroceryRequest, household: DemoHousehold?) async -> ModelRun {
        let startedAt = Date()

        switch await provider.availability() {
        case .notConfigured:
            return failure(
                for: request,
                household: household,
                startedAt: startedAt,
                tools: [],
                errorCode: "claude-not-configured",
                message: "Hybrid assistance is not configured. Add a Claude credential to continue."
            )
        case .unavailable:
            return failure(
                for: request,
                household: household,
                startedAt: startedAt,
                tools: [],
                errorCode: "claude-unavailable",
                message: "Hybrid assistance is currently unavailable. Use local-only assistance or try again later."
            )
        case .ready:
            let localRun = await localAssistant.answer(for: request, household: household)
            let invocation = makeBatonPassInvocation(
                request: request,
                localRun: localRun
            )
            do {
                let response = try await provider.respond(to: invocation)
                let localEvents = localRun.events.map { event in
                    event.kind == .finalAnswer
                        ? ModelRunEvent(kind: .modelOutput, label: "local-answer", content: event.content)
                        : event
                }
                let events = response.events + [
                    ModelRunEvent(kind: .finalAnswer, label: "claude-answer", content: response.answer.text)
                ]
                let toolEvents = (localRun.trace.toolEvents + response.events)
                    .filter { $0.kind == .toolCall || $0.kind == .toolOutput }
                return ModelRun(
                    request: request,
                    answer: response.answer,
                    events: localEvents + events,
                    trace: ModelTrace(
                        strategy: .hybrid,
                        provider: provider.provider,
                        householdID: household?.id,
                        intentID: "catalog-and-household",
                        tools: unique(localRun.trace.tools + response.tools),
                        toolEvents: toolEvents,
                        durationMilliseconds: elapsedMilliseconds(since: startedAt),
                        remoteContextView: invocation.contextView.rendered,
                        correlationID: invocation.correlationID,
                        remoteContextID: invocation.remoteContextID,
                        orchestrationPattern: .batonPass,
                        activeProfiles: [.localGrocery, .claudeGrocery],
                        profileTransitions: [
                            ModelProfileTransition(from: .localGrocery, to: .claudeGrocery)
                        ],
                        finalAnswerProfile: .claudeGrocery,
                        privacyConcerns: invocation.contextView.privacyConcerns
                    )
                )
            } catch {
                return failure(
                    for: request,
                    household: household,
                    startedAt: startedAt,
                    tools: localRun.trace.tools,
                    errorCode: "claude-request-failed",
                    message: "Hybrid assistance could not complete this request.",
                    localRun: localRun,
                    invocation: invocation
                )
            }
        }
    }

    private func failure(
        for request: GroceryRequest,
        household: DemoHousehold?,
        startedAt: Date,
        tools: [String],
        errorCode: String,
        message: String,
        localRun: ModelRun? = nil,
        invocation: RemoteGroceryInvocation? = nil
    ) -> ModelRun {
        let error = ModelRunEvent(kind: .error, label: errorCode, content: message)
        let finalAnswer = ModelRunEvent(kind: .finalAnswer, label: "answer", content: message)
        let priorEvents = localRun?.events.map { event in
            event.kind == .finalAnswer
                ? ModelRunEvent(kind: .modelOutput, label: "local-answer", content: event.content)
                : event
        } ?? []
        let toolEvents = localRun?.trace.toolEvents ?? []
        return ModelRun(
            request: request,
            answer: GroceryAnswer(text: message),
            events: priorEvents + [error, finalAnswer],
            trace: ModelTrace(
                strategy: .hybrid,
                provider: provider.provider,
                householdID: household?.id,
                intentID: "catalog-and-household",
                tools: tools,
                toolEvents: toolEvents,
                durationMilliseconds: elapsedMilliseconds(since: startedAt),
                error: errorCode,
                remoteContextView: invocation?.contextView.rendered,
                correlationID: invocation?.correlationID,
                remoteContextID: invocation?.remoteContextID,
                orchestrationPattern: invocation?.contextView.pattern,
                activeProfiles: invocation == nil ? [] : [.localGrocery, .claudeGrocery],
                profileTransitions: invocation == nil ? [] : [
                    ModelProfileTransition(from: .localGrocery, to: .claudeGrocery)
                ],
                privacyConcerns: invocation?.contextView.privacyConcerns ?? []
            )
        )
    }

    private func makeBatonPassInvocation(
        request: GroceryRequest,
        localRun: ModelRun
    ) -> RemoteGroceryInvocation {
        let privacyConcerns = [
            "Shared history contains App-Owned Context from the local household tools.",
            "Claude receives only the listed public tool definitions; private tools are not re-registered."
        ]
        let contextView = RemoteContextView(
            pattern: .batonPass,
            instructions: "Continue the grocery request using the shared local session history and answer for the shopper.",
            prompt: request.text,
            sharedHistory: localRun.events.compactMap(remoteHistoryEntry),
            toolDefinitions: ["public-catalog"],
            toolOutputs: localRun.events.compactMap { event in
                guard event.kind == .toolOutput else { return nil }
                return RemoteHistoryEntry(role: .toolOutput, label: event.label, content: event.content)
            },
            selectedOptions: [
                "history=shared",
                "final-answer-owner=claude-grocery",
                "private-tools=omitted"
            ],
            disclosureFacts: [
                "App-Owned Context is disclosed through shared history.",
                "Credentials and hidden reasoning are not included."
            ],
            privacyConcerns: privacyConcerns
        )
        return RemoteGroceryInvocation(request: request, contextView: contextView)
    }

    private func remoteHistoryEntry(from event: ModelRunEvent) -> RemoteHistoryEntry? {
        switch event.kind {
        case .toolCall:
            return RemoteHistoryEntry(role: .toolCall, label: event.label, content: event.content)
        case .toolOutput:
            return RemoteHistoryEntry(role: .toolOutput, label: event.label, content: event.content)
        case .finalAnswer:
            return RemoteHistoryEntry(role: .assistant, label: event.label, content: event.content)
        case .modelOutput, .error:
            return nil
        }
    }

    private func unique(_ values: [String]) -> [String] {
        values.reduce(into: []) { result, value in
            if !result.contains(value) {
                result.append(value)
            }
        }
    }

    private func elapsedMilliseconds(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
    }
}
