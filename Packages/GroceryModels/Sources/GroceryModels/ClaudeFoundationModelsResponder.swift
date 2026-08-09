import ClaudeForFoundationModels
import Foundation
import FoundationModels
import GroceryDomain

enum ClaudeSessionKind: Sendable, Equatable {
    case sharedDynamicProfile
    case isolatedChild
}

struct ClaudeSessionRequest: Sendable, Equatable {
    let sessionID: String
    let kind: ClaudeSessionKind
    let instructions: String
    let prompt: String
    let toolNames: [String]
}

enum ClaudeSessionCompletion: Sendable, Equatable {
    case finished
    case failed
    case cancelled
}

enum ClaudeSessionEvent: Sendable, Equatable {
    case snapshot(String)
    case modelRun(ModelRunEvent)
}

struct ClaudeSessionOutput: Sendable, Equatable {
    let events: [ClaudeSessionEvent]
    let completion: ClaudeSessionCompletion
}

public protocol ClaudeSharedBatonPassResponder: Sendable {
    func respondWithSharedBatonPass(
        for request: GroceryRequest,
        household: DemoHousehold?,
        apiKey: String
    ) async throws -> SharedBatonPassResponse
}

protocol ClaudeFoundationModelsSessionFactory: Sendable {
    func response(
        for request: ClaudeSessionRequest,
        apiKey: String
    ) async -> ClaudeSessionOutput

    func sharedResponse(
        for request: ClaudeSessionRequest,
        apiKey: String
    ) async -> ClaudeSessionOutput
}

public struct ClaudeFoundationModelsResponder: ClaudeResponder, ClaudeSharedBatonPassResponder, Sendable {
    private let sessionFactory: any ClaudeFoundationModelsSessionFactory
    private let catalog: (any ProductCatalog)?

    public init(catalog: any ProductCatalog) {
        sessionFactory = LiveClaudeSessionFactory(catalog: catalog)
        self.catalog = catalog
    }

    init(sessionFactory: any ClaudeFoundationModelsSessionFactory) {
        self.sessionFactory = sessionFactory
        catalog = nil
    }

    public func availability() async -> RemoteProviderState {
        SystemLanguageModel.default.availability == .available ? .ready : .unavailable
    }

    public func respond(
        to invocation: RemoteGroceryInvocation,
        apiKey: String
    ) async throws -> RemoteProviderResponse {
        let request = try makeSessionRequest(for: invocation)
        let output = await sessionFactory.response(for: request, apiKey: apiKey)
        var latestSnapshot = ""
        var events: [ModelRunEvent] = []

        for event in output.events {
            switch event {
            case .snapshot(let snapshot):
                let delta = String(snapshot.dropFirst(latestSnapshot.count))
                guard !delta.isEmpty else { continue }
                latestSnapshot = snapshot
                events.append(
                    ModelRunEvent(kind: .modelOutput, label: "claude-stream", content: delta)
                )
            case .modelRun(let event):
                events.append(event)
            }
        }

        switch output.completion {
        case .finished:
            break
        case .cancelled:
            throw RemoteProviderFailure.cancelled(events: events)
        case .failed:
            guard !events.isEmpty else { throw RemoteProviderFailure.failed }
            throw RemoteProviderFailure.incomplete(events: events)
        }

        let answer = latestSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else {
            guard !events.isEmpty else { throw RemoteProviderFailure.failed }
            throw RemoteProviderFailure.incomplete(events: events)
        }
        return RemoteProviderResponse(
            answer: GroceryAnswer(text: answer),
            events: events,
            tools: request.toolNames
        )
    }

    public func respondWithSharedBatonPass(
        for request: GroceryRequest,
        household: DemoHousehold?,
        apiKey: String
    ) async throws -> SharedBatonPassResponse {
        let sessionID = UUID().uuidString
        let householdEvidence = LocalHouseholdEvidence.render(household)
        let catalogEvidence = (catalog?.search(matching: request.text) ?? []).map {
            "\($0.name): \($0.detail)"
        }.joined(separator: "\n")
        let localEvidenceEvents = [
            ModelRunEvent(
                kind: .toolOutput,
                label: "household-context",
                content: householdEvidence
            ),
            ModelRunEvent(
                kind: .toolOutput,
                label: "search-catalog",
                content: catalogEvidence.isEmpty ? "No matching products were found." : catalogEvidence
            )
        ]
        let instructions = "Continue the grocery request using the shared local session history and answer for the shopper."
        let toolNames = [ClaudePublicCatalogTool.toolName]
        let sessionRequest = ClaudeSessionRequest(
            sessionID: sessionID,
            kind: .sharedDynamicProfile,
            instructions: instructions,
            prompt: """
            Grocery request: \(request.text)

            Local household context:
            \(householdEvidence)

            Local catalog evidence:
            \(catalogEvidence.isEmpty ? "No matching products were found." : catalogEvidence)

            Pass the baton to Claude after the local context has been considered.
            """,
            toolNames: toolNames
        )
        let output = await sessionFactory.sharedResponse(
            for: sessionRequest,
            apiKey: apiKey
        )
        let rendered = renderSharedSessionOutput(output.events)
        let localSessionEvents = Array(rendered.events.prefix(rendered.batonEventEndIndex ?? 0))
        let remoteEvents = Array(rendered.events.dropFirst(rendered.batonEventEndIndex ?? 0))
        let contextView = RemoteContextView(
            pattern: .batonPass,
            sessionOwnership: .sharedParent,
            instructions: instructions,
            prompt: sessionRequest.prompt,
            sharedHistory: localSessionEvents.compactMap(remoteHistoryEntry),
            toolDefinitions: toolNames,
            toolOutputs: remoteEvents.compactMap { event in
                guard event.kind == .toolOutput, event.label == ClaudePublicCatalogTool.toolName else {
                    return nil
                }
                return RemoteHistoryEntry(role: .toolOutput, label: event.label, content: event.content)
            },
            selectedOptions: [
                "history=shared",
                "final-answer-owner=claude-grocery",
                "private-tools=omitted"
            ],
            disclosureFacts: [
                "App-Owned Context is disclosed through the shared session prompt and history.",
                "Credentials and hidden reasoning are not included."
            ],
            privacyConcerns: [
                "Shared history contains App-Owned Context from the local household tools.",
                "Claude receives only the listed public tool definitions; private tools are not re-registered."
            ]
        )
        let invocation = RemoteGroceryInvocation(
            contextView: contextView,
            session: RemoteSession(ownership: .sharedParent, id: sessionID)
        )
        do {
            switch output.completion {
            case .finished:
                break
            case .cancelled:
                throw RemoteProviderFailure.cancelled(events: remoteEvents)
            case .failed:
                if rendered.events.isEmpty {
                    throw RemoteProviderFailure.failed
                }
                throw RemoteProviderFailure.incomplete(events: rendered.events)
            }
            let answer = rendered.latestSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else {
                throw RemoteProviderFailure.incomplete(events: rendered.events)
            }
            return SharedBatonPassResponse(
                localEvents: localEvidenceEvents + localSessionEvents,
                response: RemoteProviderResponse(
                    answer: GroceryAnswer(text: answer),
                    events: remoteEvents,
                    tools: contextView.toolDefinitions
                ),
                invocation: invocation
            )
        } catch let failure as RemoteProviderFailure {
            throw SharedBatonPassFailure(
                failure: failure,
                localEvents: localEvidenceEvents + localSessionEvents,
                invocation: invocation
            )
        }
    }

    private func renderSharedSessionOutput(
        _ events: [ClaudeSessionEvent]
    ) -> (events: [ModelRunEvent], latestSnapshot: String, batonEventEndIndex: Int?) {
        var latestSnapshot = ""
        var renderedEvents: [ModelRunEvent] = []
        var batonEventEndIndex: Int?
        for event in events {
            switch event {
            case .snapshot(let snapshot):
                let delta = String(snapshot.dropFirst(latestSnapshot.count))
                guard !delta.isEmpty else { continue }
                latestSnapshot = snapshot
                renderedEvents.append(
                    ModelRunEvent(kind: .modelOutput, label: "shared-session-stream", content: delta)
                )
            case .modelRun(let event):
                renderedEvents.append(event)
                if event.label == ClaudeBatonPassTool.toolName,
                   event.kind == .toolOutput,
                   batonEventEndIndex == nil {
                    batonEventEndIndex = renderedEvents.count
                }
            }
        }
        return (renderedEvents, latestSnapshot, batonEventEndIndex)
    }

    private func remoteHistoryEntry(from event: ModelRunEvent) -> RemoteHistoryEntry? {
        switch event.kind {
        case .toolCall:
            return RemoteHistoryEntry(role: .toolCall, label: event.label, content: event.content)
        case .toolOutput:
            return RemoteHistoryEntry(role: .toolOutput, label: event.label, content: event.content)
        case .modelOutput:
            return RemoteHistoryEntry(role: .assistant, label: event.label, content: event.content)
        case .finalAnswer, .error:
            return nil
        }
    }

    private func makeSessionRequest(
        for invocation: RemoteGroceryInvocation
    ) throws -> ClaudeSessionRequest {
        let context = invocation.contextView
        guard context.toolDefinitions.allSatisfy({ $0 == ClaudePublicCatalogTool.toolName }) else {
            throw RemoteProviderFailure.failed
        }

        switch invocation.session.ownership {
        case .sharedParent:
            return ClaudeSessionRequest(
                sessionID: invocation.sessionID,
                kind: .sharedDynamicProfile,
                instructions: context.instructions,
                prompt: renderSharedPrompt(context),
                toolNames: context.toolDefinitions
            )
        case .isolatedChild:
            guard let task = context.remoteTask else { throw RemoteProviderFailure.failed }
            guard context.instructions == ClaudeRemoteInvocationPolicy.isolatedChildInstructions else {
                throw RemoteProviderFailure.failed
            }
            return ClaudeSessionRequest(
                sessionID: invocation.sessionID,
                kind: .isolatedChild,
                instructions: context.instructions,
                prompt: renderChildPrompt(task: task, toolOutputs: context.toolOutputs),
                toolNames: context.toolDefinitions
            )
        }
    }

    private func renderSharedPrompt(_ context: RemoteContextView) -> String {
        var sections = ["Request:\n\(context.prompt)"]
        if !context.sharedHistory.isEmpty {
            sections.append(
                "Approved shared history:\n" + context.sharedHistory.map {
                    "[\($0.role.rawValue)] \($0.label): \($0.content)"
                }.joined(separator: "\n")
            )
        }
        if !context.toolOutputs.isEmpty {
            sections.append("Approved public tool results:\n" + renderToolOutputs(context.toolOutputs))
        }
        return sections.joined(separator: "\n\n")
    }

    private func renderChildPrompt(
        task: RemoteTask,
        toolOutputs: [RemoteHistoryEntry]
    ) -> String {
        var sections = ["Validated Remote Task:\n\(task.instructionText)"]
        if !toolOutputs.isEmpty {
            sections.append("Approved public tool results:\n" + renderToolOutputs(toolOutputs))
        }
        return sections.joined(separator: "\n\n")
    }

    private func renderToolOutputs(_ outputs: [RemoteHistoryEntry]) -> String {
        outputs.map { "\($0.label): \($0.content)" }.joined(separator: "\n")
    }
}

private struct LiveClaudeSessionFactory: ClaudeFoundationModelsSessionFactory {
    let catalog: any ProductCatalog

    func response(
        for request: ClaudeSessionRequest,
        apiKey: String
    ) async -> ClaudeSessionOutput {
        let model = ClaudeLanguageModel(name: .sonnet4_6, auth: .apiKey(apiKey))
        let recorder = ClaudeSessionEventRecorder()
        let publicCatalogTool = request.toolNames.isEmpty
            ? nil
            : ClaudePublicCatalogTool(catalog: catalog, recorder: recorder)
        let session: LanguageModelSession
        switch request.kind {
        case .sharedDynamicProfile:
            // The reference app currently treats one Model Run as the session boundary.
            // Do not retain this transcript across runs or household selections.
            session = LanguageModelSession(
                profile: ClaudeSharedDynamicProfile(
                    model: model,
                    instructions: request.instructions,
                    publicCatalogTool: publicCatalogTool
                )
            )
        case .isolatedChild:
            session = LanguageModelSession(
                profile: ClaudeChildDynamicProfile(
                    model: model,
                    instructions: request.instructions,
                    publicCatalogTool: publicCatalogTool
                )
            )
        }

        let eventOffset = await recorder.count()
        do {
            for try await snapshot in session.streamResponse(to: request.prompt) {
                try Task.checkCancellation()
                await recorder.record(.snapshot(snapshot.content))
            }
            return ClaudeSessionOutput(
                events: await recorder.events(since: eventOffset),
                completion: .finished
            )
        } catch is CancellationError {
            return ClaudeSessionOutput(
                events: await recorder.events(since: eventOffset),
                completion: .cancelled
            )
        } catch {
            return ClaudeSessionOutput(
                events: await recorder.events(since: eventOffset),
                completion: .failed
            )
        }
    }

    func sharedResponse(
        for request: ClaudeSessionRequest,
        apiKey: String
    ) async -> ClaudeSessionOutput {
        guard SystemLanguageModel.default.availability == .available else {
            return ClaudeSessionOutput(events: [], completion: .failed)
        }

        let model = ClaudeLanguageModel(name: .sonnet4_6, auth: .apiKey(apiKey))
        let state = ClaudeBatonPassState()
        let recorder = ClaudeSessionEventRecorder()
        let publicCatalogTool = ClaudePublicCatalogTool(catalog: catalog, recorder: recorder)
        let session = LanguageModelSession(
            profile: ClaudeBatonPassDynamicProfile(
                model: model,
                state: state,
                recorder: recorder,
                publicCatalogTool: publicCatalogTool,
                instructions: request.instructions
            )
        )
        session.transcriptErrorHandlingPolicy = .preserveTranscript

        do {
            for try await snapshot in session.streamResponse(to: request.prompt) {
                try Task.checkCancellation()
                await recorder.record(.snapshot(snapshot.content))
            }
            return ClaudeSessionOutput(
                events: await recorder.events(since: 0),
                completion: .finished
            )
        } catch is CancellationError {
            return ClaudeSessionOutput(
                events: await recorder.events(since: 0),
                completion: .cancelled
            )
        } catch {
            return ClaudeSessionOutput(
                events: await recorder.events(since: 0),
                completion: .failed
            )
        }
    }
}

private struct ClaudeSharedDynamicProfile: LanguageModelSession.DynamicProfile {
    let model: ClaudeLanguageModel
    let instructions: String
    let publicCatalogTool: ClaudePublicCatalogTool?

    var body: some LanguageModelSession.DynamicProfile {
        Profile {
            Instructions { instructions }
            if let publicCatalogTool {
                publicCatalogTool
            }
        }
        .model(model)
        .transcriptErrorHandlingPolicy(.preserveTranscript)
    }
}

/// The phone-a-friend profile is intentionally constructed for one validated
/// Remote Task. It owns a new session transcript and re-composes its
/// instructions and public tools as the child session is created; no parent
/// history or private household tools are carried across this boundary.
private struct ClaudeChildDynamicProfile: LanguageModelSession.DynamicProfile {
    let model: ClaudeLanguageModel
    let instructions: String
    let publicCatalogTool: ClaudePublicCatalogTool?

    var body: some LanguageModelSession.DynamicProfile {
        Profile {
            Instructions { instructions }
            if let publicCatalogTool {
                publicCatalogTool
            }
        }
        .model(model)
        .transcriptErrorHandlingPolicy(.preserveTranscript)
    }
}

private final class ClaudeBatonPassState: @unchecked Sendable {
    enum Phase: Sendable {
        case local
        case claude
    }

    private let lock = NSLock()
    private var phase: Phase = .local

    var currentPhase: Phase {
        lock.withLock { phase }
    }

    func passBaton() {
        lock.withLock { phase = .claude }
    }
}

private struct ClaudeBatonPassDynamicProfile: LanguageModelSession.DynamicProfile {
    let model: ClaudeLanguageModel
    let state: ClaudeBatonPassState
    let recorder: ClaudeSessionEventRecorder
    let publicCatalogTool: ClaudePublicCatalogTool
    let instructions: String

    var body: some LanguageModelSession.DynamicProfile {
        switch state.currentPhase {
        case .local:
            Profile {
                Instructions {
                    "Use the local grocery context, then call pass-to-claude to hand the shared session to Claude."
                }
                ClaudeBatonPassTool(state: state, recorder: recorder)
            }
            .model(SystemLanguageModel.default)
            .toolCallingMode(.required)
        case .claude:
            Profile {
                Instructions { instructions }
                publicCatalogTool
            }
            .model(model)
            .transcriptErrorHandlingPolicy(.preserveTranscript)
        }
    }
}

@Generable
private struct ClaudeBatonPassArguments: Sendable {
    let reason: String
}

private struct ClaudeBatonPassTool: Tool, Sendable {
    static let toolName = "pass-to-claude"

    let state: ClaudeBatonPassState
    let recorder: ClaudeSessionEventRecorder

    var name: String { Self.toolName }
    var description: String { "Hand the shared grocery session to Claude for the final answer." }

    @concurrent
    func call(arguments: ClaudeBatonPassArguments) async throws -> String {
        await recorder.record(.modelRun(
            ModelRunEvent(kind: .toolCall, label: name, content: arguments.reason)
        ))
        state.passBaton()
        let output = "The shared grocery session was handed to Claude."
        await recorder.record(.modelRun(
            ModelRunEvent(kind: .toolOutput, label: name, content: output)
        ))
        return output
    }
}

@Generable
private struct ClaudePublicCatalogArguments: Sendable {
    let query: String
}

private struct ClaudePublicCatalogTool: Tool, Sendable {
    static let toolName = "public-catalog"

    let catalog: any ProductCatalog
    let recorder: ClaudeSessionEventRecorder

    var name: String { Self.toolName }
    var description: String { "Search the app's public grocery catalog." }

    @concurrent
    func call(arguments: ClaudePublicCatalogArguments) async throws -> String {
        await recorder.record(.modelRun(
            ModelRunEvent(kind: .toolCall, label: name, content: arguments.query)
        ))
        let matches = catalog.search(matching: arguments.query)
        let output = matches.isEmpty
            ? "No matching public products were found."
            : matches.map { "\($0.name): \($0.detail)" }.joined(separator: "\n")
        await recorder.record(.modelRun(
            ModelRunEvent(kind: .toolOutput, label: name, content: output)
        ))
        return output
    }
}

private actor ClaudeSessionEventRecorder {
    private var recordedEvents: [ClaudeSessionEvent] = []

    func record(_ event: ClaudeSessionEvent) { recordedEvents.append(event) }
    func count() -> Int { recordedEvents.count }
    func events(since offset: Int) -> [ClaudeSessionEvent] {
        Array(recordedEvents.dropFirst(offset))
    }
}
