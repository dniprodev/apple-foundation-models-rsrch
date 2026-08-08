import Foundation
import FoundationModels
import GroceryDomain

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
public struct OnDeviceGroceryAssistant: GroceryAssistant, Sendable {
    private let catalog: any ProductCatalog

    public init(catalog: any ProductCatalog) {
        self.catalog = catalog
    }

    public func answer(for request: GroceryRequest, household: DemoHousehold?) async -> ModelRun {
        let startedAt = Date()
        let recorder = LocalTraceRecorder()
        let toolNames = ["search-catalog", "household-context"]

        do {
            guard SystemLanguageModel.default.availability == .available else {
                return await failure(
                    for: request,
                    household: household,
                    startedAt: startedAt,
                    recorder: recorder,
                    toolNames: toolNames,
                    errorCode: "on-device-model-unavailable"
                )
            }

            let searchTool = CatalogSearchTool(catalog: catalog, recorder: recorder)
            let householdTool = HouseholdContextTool(household: household, recorder: recorder)
            let catalogEvidence = try await searchTool.call(arguments: CatalogSearchArguments(query: request.text))
            let householdContext = try await householdTool.call(
                arguments: HouseholdContextArguments(householdID: household?.id.rawValue ?? "none")
            )

            let session = LanguageModelSession(
                model: .default,
                tools: [searchTool, householdTool],
                instructions: """
                You are the local grocery assistant. You are running on the device.
                Answer only from the supplied local tool evidence. Be concise and useful.
                Respect every restriction and priority in the household context. If the
                catalog evidence is insufficient, say so instead of inventing a product.
                Never claim that a cart or household state changed.
                """
            )
            let prompt = """
            Grocery request: \(request.text)

            Local catalog tool output:
            \(catalogEvidence)

            Local household-context tool output:
            \(householdContext)
            """
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(sampling: .greedy)
            )
            let answerText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalText = answerText.isEmpty
                ? "The on-device model did not return an answer for this request."
                : answerText
            let answer = GroceryAnswer(
                text: finalText,
                evidence: catalog.search(matching: request.text).map(\.name)
            )
            let recordedEvents = await recorder.events()
            let events = recordedEvents + [
                ModelRunEvent(kind: .finalAnswer, label: "answer", content: finalText)
            ]
            let toolEvents = recordedEvents.filter { $0.kind == .toolCall || $0.kind == .toolOutput }
            return ModelRun(
                request: request,
                answer: answer,
                events: events,
                trace: ModelTrace(
                    strategy: .localOnly,
                    provider: .appleOnDevice,
                    householdID: household?.id,
                    intentID: "catalog-and-household",
                    tools: toolNames,
                    toolEvents: toolEvents,
                    durationMilliseconds: elapsedMilliseconds(since: startedAt)
                )
            )
        } catch {
            return await failure(
                for: request,
                household: household,
                startedAt: startedAt,
                recorder: recorder,
                toolNames: toolNames,
                errorCode: "on-device-model-failed"
            )
        }
    }

    private func failure(
        for request: GroceryRequest,
        household: DemoHousehold?,
        startedAt: Date,
        recorder: LocalTraceRecorder,
        toolNames: [String],
        errorCode: String
    ) async -> ModelRun {
        let message = "The local assistant could not complete this request."
        await recorder.record(ModelRunEvent(kind: .error, label: errorCode, content: message))
        let recordedEvents = await recorder.events()
        let events = recordedEvents + [
            ModelRunEvent(kind: .finalAnswer, label: "answer", content: message)
        ]
        let toolEvents = recordedEvents.filter { $0.kind == .toolCall || $0.kind == .toolOutput }
        return ModelRun(
            request: request,
            answer: GroceryAnswer(text: message),
            events: events,
            trace: ModelTrace(
                strategy: .localOnly,
                provider: .appleOnDevice,
                householdID: household?.id,
                intentID: "catalog-and-household",
                tools: toolNames,
                toolEvents: toolEvents,
                durationMilliseconds: elapsedMilliseconds(since: startedAt),
                error: errorCode
            )
        )
    }

    private func elapsedMilliseconds(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private actor LocalTraceRecorder {
    private var recordedEvents: [ModelRunEvent] = []

    func record(_ event: ModelRunEvent) {
        recordedEvents.append(event)
    }

    func events() -> [ModelRunEvent] {
        recordedEvents
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
private struct CatalogSearchArguments: Sendable {
    let query: String
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
private struct HouseholdContextArguments: Sendable {
    let householdID: String
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private struct CatalogSearchTool: Tool, Sendable {
    let catalog: any ProductCatalog
    let recorder: LocalTraceRecorder

    var name: String { "search-catalog" }
    var description: String { "Search the bundled, on-device grocery catalog for evidence." }

    @concurrent
    func call(arguments: CatalogSearchArguments) async throws -> String {
        await recorder.record(
            ModelRunEvent(kind: .toolCall, label: name, content: arguments.query)
        )
        let products = catalog.search(matching: arguments.query)
        let output = products.map { "\($0.name): \($0.detail)" }.joined(separator: "\n")
        await recorder.record(ModelRunEvent(kind: .toolOutput, label: name, content: output))
        return output.isEmpty ? "No matching products were found." : output
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private struct HouseholdContextTool: Tool, Sendable {
    let household: DemoHousehold?
    let recorder: LocalTraceRecorder

    var name: String { "household-context" }
    var description: String { "Read the selected fictional Demo Household's local grocery context." }

    @concurrent
    func call(arguments: HouseholdContextArguments) async throws -> String {
        await recorder.record(
            ModelRunEvent(kind: .toolCall, label: name, content: arguments.householdID)
        )
        let output: String
        if let household {
            let restrictions = household.restrictions.map(\.rawValue).joined(separator: ", ")
            let priorities = household.priorities.map(\.rawValue).joined(separator: ", ")
            let pantry = household.pantry.map { "\($0.productID.rawValue) ×\($0.quantity)" }.joined(separator: ", ")
            let cart = household.cart.map { "\($0.productID.rawValue) ×\($0.quantity)" }.joined(separator: ", ")
            output = """
            Household: \(household.name)
            Restrictions: \(restrictions.isEmpty ? "none" : restrictions)
            Priorities: \(priorities.isEmpty ? "none" : priorities)
            Pantry: \(pantry.isEmpty ? "empty" : pantry)
            Cart: \(cart.isEmpty ? "empty" : cart)
            """
        } else {
            output = "No Demo Household is selected."
        }
        await recorder.record(ModelRunEvent(kind: .toolOutput, label: name, content: output))
        return output
    }
}
