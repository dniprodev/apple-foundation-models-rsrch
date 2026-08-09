import Foundation
import GroceryDomain

public protocol PhoneAFriendParentAnswerer: Sendable {
    func answer(
        for request: GroceryRequest,
        childAnswer: GroceryAnswer,
        household: DemoHousehold?
    ) async -> GroceryAnswer
}

public struct LocalPhoneAFriendParentAnswerer: PhoneAFriendParentAnswerer, Sendable {
    public init() {}

    public func answer(
        for request: GroceryRequest,
        childAnswer: GroceryAnswer,
        household: DemoHousehold?
    ) async -> GroceryAnswer {
        GroceryAnswer(
            text: "The local parent synthesized this answer from the child finding: \(childAnswer.text)",
            evidence: childAnswer.evidence
        )
    }
}

/// Runs a request through the configured remote provider while keeping setup and
/// provider failures visible in the ordinary Model Run surface.
public struct HybridGroceryAssistant: GroceryAssistant, Sendable {
    private let localAssistant: any GroceryAssistant
    private let provider: any RemoteGroceryProvider
    private let parentAnswerer: any PhoneAFriendParentAnswerer
    private let pattern: OrchestrationPattern

    private enum AssistantError: Error {
        case disallowedRemoteTool
    }

    public init(
        localAssistant: any GroceryAssistant,
        provider: any RemoteGroceryProvider,
        pattern: OrchestrationPattern = .batonPass,
        parentAnswerer: any PhoneAFriendParentAnswerer = LocalPhoneAFriendParentAnswerer()
    ) {
        self.localAssistant = localAssistant
        self.provider = provider
        self.pattern = pattern
        self.parentAnswerer = parentAnswerer
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
            if pattern == .phoneAFriend {
                do {
                    let task = try RemoteTask(request: request)
                    return await answerWithPhoneAFriend(
                        request: request,
                        household: household,
                        task: task,
                        startedAt: startedAt
                    )
                } catch {
                    return failure(
                        for: request,
                        household: household,
                        startedAt: startedAt,
                        tools: [],
                        errorCode: "phone-friend-task-invalid",
                        message: "The phone-a-friend task could not be validated before disclosure."
                    )
                }
            }

            return await answerWithBatonPass(
                request: request,
                household: household,
                startedAt: startedAt
            )
        }
    }

    private func answerWithBatonPass(
        request: GroceryRequest,
        household: DemoHousehold?,
        startedAt: Date
    ) async -> ModelRun {
        let localRun = await localAssistant.answer(for: request, household: household)
        let invocation = makeBatonPassInvocation(request: request, localRun: localRun)

        do {
            let response = try validatedResponse(
                try await provider.respond(to: invocation),
                for: invocation
            )
            let localEvents = localRun.events.map { event in
                event.kind == .finalAnswer
                    ? ModelRunEvent(kind: .modelOutput, label: "local-answer", content: event.content)
                    : event
            }
            let events = response.events + [
                ModelRunEvent(kind: .finalAnswer, label: "claude-answer", content: response.answer.text)
            ]
            return makeSuccessfulRun(
                request: request,
                household: household,
                startedAt: startedAt,
                localRuns: [localRun],
                response: response,
                invocation: invocation,
                events: localEvents + events,
                activeProfiles: [.localGrocery, .claudeGrocery],
                transitions: [
                    ModelProfileTransition(from: .localGrocery, to: .claudeGrocery)
                ],
                finalAnswerProfile: .claudeGrocery
            )
        } catch AssistantError.disallowedRemoteTool {
            return failure(
                for: request,
                household: household,
                startedAt: startedAt,
                tools: localRun.trace.tools,
                errorCode: "claude-disallowed-tool",
                message: "Hybrid assistance returned a tool outside the disclosed tool set.",
                localRun: localRun,
                invocation: invocation
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

    private func answerWithPhoneAFriend(
        request: GroceryRequest,
        household: DemoHousehold?,
        task: RemoteTask,
        startedAt: Date
    ) async -> ModelRun {
        let localRun = await localAssistant.answer(for: request, household: household)
        let invocation = makePhoneAFriendInvocation(
            request: request,
            localRun: localRun,
            task: task
        )

        do {
            let response = try validatedResponse(
                try await provider.respond(to: invocation),
                for: invocation
            )
            let localEvents = localRun.events.map { event in
                event.kind == .finalAnswer
                    ? ModelRunEvent(kind: .modelOutput, label: "local-parent-context", content: event.content)
                    : event
            }
            let childEvents = response.events + [
                ModelRunEvent(kind: .modelOutput, label: "claude-child-answer", content: response.answer.text)
            ]
            let parentAnswer = await parentAnswerer.answer(
                for: request,
                childAnswer: response.answer,
                household: household
            )
            let parentResponse = RemoteProviderResponse(
                answer: parentAnswer,
                events: response.events,
                tools: response.tools
            )
            return makeSuccessfulRun(
                request: request,
                household: household,
                startedAt: startedAt,
                localRuns: [localRun],
                response: parentResponse,
                invocation: invocation,
                events: localEvents + childEvents + [
                    ModelRunEvent(kind: .modelOutput, label: "local-parent-synthesis", content: parentAnswer.text),
                    ModelRunEvent(kind: .finalAnswer, label: "local-parent-answer", content: parentAnswer.text)
                ],
                activeProfiles: [.localGrocery, .claudeChildGrocery],
                transitions: [
                    ModelProfileTransition(from: .localGrocery, to: .claudeChildGrocery),
                    ModelProfileTransition(from: .claudeChildGrocery, to: .localGrocery)
                ],
                finalAnswerProfile: .localGrocery
            )
        } catch AssistantError.disallowedRemoteTool {
            return failure(
                for: request,
                household: household,
                startedAt: startedAt,
                tools: localRun.trace.tools,
                errorCode: "claude-disallowed-tool",
                message: "Hybrid assistance returned a tool outside the disclosed tool set.",
                localRun: localRun,
                invocation: invocation
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

    private func makeSuccessfulRun(
        request: GroceryRequest,
        household: DemoHousehold?,
        startedAt: Date,
        localRuns: [ModelRun],
        response: RemoteProviderResponse,
        invocation: RemoteGroceryInvocation,
        events: [ModelRunEvent],
        activeProfiles: [ModelProfileID],
        transitions: [ModelProfileTransition],
        finalAnswerProfile: ModelProfileID
    ) -> ModelRun {
        let toolEvents = (localRuns.flatMap(\.trace.toolEvents) + response.events)
            .filter { $0.kind == .toolCall || $0.kind == .toolOutput }
        return ModelRun(
            request: request,
            answer: response.answer,
            events: events,
            trace: ModelTrace(
                strategy: .hybrid,
                provider: provider.provider,
                householdID: household?.id,
                intentID: "catalog-and-household",
                tools: unique(localRuns.flatMap(\.trace.tools) + response.tools),
                toolEvents: toolEvents,
                durationMilliseconds: elapsedMilliseconds(since: startedAt),
                remoteContextView: invocation.contextView.rendered,
                correlationID: invocation.correlationID,
                remoteContextID: invocation.remoteContextID,
                remoteSessionID: invocation.sessionID,
                parentRemoteSessionID: invocation.parentSessionID,
                orchestrationPattern: invocation.contextView.pattern,
                activeProfiles: activeProfiles,
                profileTransitions: transitions,
                finalAnswerProfile: finalAnswerProfile,
                privacyConcerns: invocation.contextView.privacyConcerns
            )
        )
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
        let failureProfiles: [ModelProfileID]
        let failureTransitions: [ModelProfileTransition]
        let finalAnswerProfile: ModelProfileID?
        switch invocation?.contextView.pattern {
        case .batonPass:
            failureProfiles = [.localGrocery, .claudeGrocery]
            failureTransitions = [ModelProfileTransition(from: .localGrocery, to: .claudeGrocery)]
            finalAnswerProfile = .claudeGrocery
        case .phoneAFriend:
            failureProfiles = [.localGrocery, .claudeChildGrocery]
            failureTransitions = [
                ModelProfileTransition(from: .localGrocery, to: .claudeChildGrocery),
                ModelProfileTransition(from: .claudeChildGrocery, to: .localGrocery)
            ]
            finalAnswerProfile = .localGrocery
        case nil:
            failureProfiles = []
            failureTransitions = []
            finalAnswerProfile = nil
        }
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
                remoteSessionID: invocation?.sessionID,
                parentRemoteSessionID: invocation?.parentSessionID,
                orchestrationPattern: invocation?.contextView.pattern,
                activeProfiles: failureProfiles,
                profileTransitions: failureTransitions,
                finalAnswerProfile: finalAnswerProfile,
                privacyConcerns: invocation?.contextView.privacyConcerns ?? []
            )
        )
    }

    private func validatedResponse(
        _ response: RemoteProviderResponse,
        for invocation: RemoteGroceryInvocation
    ) throws -> RemoteProviderResponse {
        let allowedTools = Set(invocation.contextView.toolDefinitions)
        guard response.tools.allSatisfy(allowedTools.contains) else {
            throw AssistantError.disallowedRemoteTool
        }
        let emittedToolLabels = response.events
            .filter { $0.kind == .toolCall || $0.kind == .toolOutput }
            .map(\.label)
        guard emittedToolLabels.allSatisfy(allowedTools.contains) else {
            throw AssistantError.disallowedRemoteTool
        }
        return response
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
            sessionOwnership: .sharedParent,
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
        return RemoteGroceryInvocation(
            contextView: contextView,
            session: RemoteSession(ownership: .sharedParent)
        )
    }

    private func makePhoneAFriendInvocation(
        request: GroceryRequest,
        localRun: ModelRun,
        task: RemoteTask
    ) -> RemoteGroceryInvocation {
        let publicCatalogOutputs = localRun.events.compactMap { event -> RemoteHistoryEntry? in
            guard event.kind == .toolOutput,
                  event.label == LocalGroceryToolID.catalogSearch.rawValue
                    || event.label == "public-catalog" else {
                return nil
            }
            return RemoteHistoryEntry(role: .toolOutput, label: event.label, content: event.content)
        }
        let contextView = RemoteContextView(
            pattern: .phoneAFriend,
            sessionOwnership: .isolatedChild,
            instructions: "Complete only the validated Remote Task in an isolated child session. Do not answer for the shopper.",
            prompt: "",
            sharedHistory: [],
            toolDefinitions: ["public-catalog"],
            toolOutputs: publicCatalogOutputs,
            selectedOptions: [
                "history=isolated-child",
                "final-answer-owner=local-grocery",
                "private-tools=omitted"
            ],
            remoteTask: task,
            disclosureFacts: [
                "The child session owns an independent transcript.",
                "Only the bounded Remote Task and public catalog outputs are disclosed.",
                "Credentials and hidden reasoning are not included."
            ],
            privacyConcerns: [
                "Narrower disclosure excludes shared parent history and household-context output.",
                "Household-context output remains app-local in the Model Trace but is not sent to the child.",
                "Claude receives only the listed public tool definitions; private tools are not re-registered."
            ]
        )
        return RemoteGroceryInvocation(
            contextView: contextView,
            session: RemoteSession(
                ownership: .isolatedChild,
                parentID: UUID().uuidString
            )
        )
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
