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

protocol ClaudeFoundationModelsSessionFactory: Sendable {
    func response(
        for request: ClaudeSessionRequest,
        apiKey: String
    ) async -> ClaudeSessionOutput
}

public struct ClaudeFoundationModelsResponder: ClaudeResponder, Sendable {
    private let sessionFactory: any ClaudeFoundationModelsSessionFactory

    public init(catalog: any ProductCatalog) {
        sessionFactory = LiveClaudeSessionFactory(catalog: catalog)
    }

    init(sessionFactory: any ClaudeFoundationModelsSessionFactory) {
        self.sessionFactory = sessionFactory
    }

    public func availability() async -> RemoteProviderState { .ready }

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
        let tools: [any Tool] = publicCatalogTool.map { [$0] } ?? []
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
                model: model,
                tools: tools,
                instructions: request.instructions
            )
            session.transcriptErrorHandlingPolicy = .preserveTranscript
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
