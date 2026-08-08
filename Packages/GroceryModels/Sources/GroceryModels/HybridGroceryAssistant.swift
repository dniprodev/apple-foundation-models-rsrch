import Foundation
import GroceryDomain

/// Runs a request through the configured remote provider while keeping setup and
/// provider failures visible in the ordinary Model Run surface.
public struct HybridGroceryAssistant: GroceryAssistant, Sendable {
    private let provider: any RemoteGroceryProvider

    public init(provider: any RemoteGroceryProvider) {
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
            do {
                let response = try await provider.respond(to: request, household: household)
                let events = response.events + [
                    ModelRunEvent(kind: .finalAnswer, label: "answer", content: response.answer.text)
                ]
                return ModelRun(
                    request: request,
                    answer: response.answer,
                    events: events,
                    trace: ModelTrace(
                        strategy: .hybrid,
                        provider: provider.provider,
                        householdID: household?.id,
                        intentID: "catalog-and-household",
                        tools: response.tools,
                        toolEvents: response.events,
                        durationMilliseconds: elapsedMilliseconds(since: startedAt),
                        remoteContextView: response.remoteContextView
                    )
                )
            } catch {
                return failure(
                    for: request,
                    household: household,
                    startedAt: startedAt,
                    tools: [],
                    errorCode: "claude-request-failed",
                    message: "Hybrid assistance could not complete this request."
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
        message: String
    ) -> ModelRun {
        let error = ModelRunEvent(kind: .error, label: errorCode, content: message)
        let finalAnswer = ModelRunEvent(kind: .finalAnswer, label: "answer", content: message)
        return ModelRun(
            request: request,
            answer: GroceryAnswer(text: message),
            events: [error, finalAnswer],
            trace: ModelTrace(
                strategy: .hybrid,
                provider: provider.provider,
                householdID: household?.id,
                intentID: "catalog-and-household",
                tools: tools,
                durationMilliseconds: elapsedMilliseconds(since: startedAt),
                error: errorCode
            )
        )
    }

    private func elapsedMilliseconds(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
    }
}
