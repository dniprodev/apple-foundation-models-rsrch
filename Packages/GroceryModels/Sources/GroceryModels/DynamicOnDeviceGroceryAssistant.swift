import Foundation
import FoundationModels
import GroceryDomain

struct DynamicOnDeviceGroceryAssistant: Sendable {
    let catalog: any ProductCatalog

    func answer(for request: GroceryRequest, household: DemoHousehold?) async -> ModelRun {
        let startedAt = Date()
        let initialPlan = LocalGroceryPolicy.plan(for: request)
        let state = DynamicLocalProfileState(initialPlan: initialPlan)
        let recorder = DynamicLocalTraceRecorder()

        do {
            guard SystemLanguageModel.default.availability == .available else {
                return await failure(
                    for: request,
                    household: household,
                    startedAt: startedAt,
                    state: state,
                    recorder: recorder,
                    errorCode: "on-device-model-unavailable"
                )
            }

            let searchTool = DynamicCatalogSearchTool(catalog: catalog, recorder: recorder)
            let householdTool = DynamicHouseholdContextTool(
                household: household,
                recorder: recorder,
                profileState: state,
                transitionOnCall: false
            )
            let catalogEvidence: String
            if initialPlan.intent == .cartReview {
                catalogEvidence = "Use search-catalog after household context is loaded."
            } else {
                catalogEvidence = try await searchTool.call(
                    arguments: DynamicCatalogSearchArguments(query: request.text)
                )
            }
            let householdEvidence: String
            if initialPlan.intent == .householdPlanning {
                householdEvidence = try await householdTool.call(
                    arguments: DynamicHouseholdContextArguments(
                        householdID: household?.id.rawValue ?? "none"
                    )
                )
            } else if initialPlan.intent == .cartReview {
                householdEvidence = "Use household-context before answering."
            } else {
                householdEvidence = "Not loaded for the active product-discovery profile."
            }

            let session = LanguageModelSession(
                profile: GroceryDynamicProfile(
                    catalog: catalog,
                    household: household,
                    recorder: recorder,
                    state: state
                )
            )
            let response = try await session.respond(
                to: """
                Grocery request: \(request.text)

                Local catalog tool output:
                \(catalogEvidence)

                Local household-context tool output:
                \(householdEvidence)
                """,
                options: GenerationOptions(samplingMode: .greedy)
            )
            let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelProducedFinalAnswer = !content.isEmpty
            let finalText = content.isEmpty
                ? "The on-device model did not return an answer for this request."
                : content
            let answer = GroceryAnswer(
                text: finalText,
                evidence: catalog.search(matching: request.text).map(\.name)
            )
            let recordedEvents = await recorder.events()
            let finalPlan = state.currentPlan()
            return ModelRun(
                request: request,
                answer: answer,
                events: recordedEvents + [
                    ModelRunEvent(kind: .finalAnswer, label: "answer", content: finalText)
                ],
                trace: trace(
                    household: household,
                    startedAt: startedAt,
                    state: state,
                    events: recordedEvents,
                    error: nil,
                    finalProfile: modelProducedFinalAnswer ? finalPlan.profile : nil
                )
            )
        } catch {
            return await failure(
                for: request,
                household: household,
                startedAt: startedAt,
                state: state,
                recorder: recorder,
                errorCode: "on-device-model-failed"
            )
        }
    }

    private func failure(
        for request: GroceryRequest,
        household: DemoHousehold?,
        startedAt: Date,
        state: DynamicLocalProfileState,
        recorder: DynamicLocalTraceRecorder,
        errorCode: String
    ) async -> ModelRun {
        let message = "The local assistant could not complete this request."
        await recorder.record(ModelRunEvent(kind: .error, label: errorCode, content: message))
        let events = await recorder.events()
        return ModelRun(
            request: request,
            answer: GroceryAnswer(text: message),
            events: events + [ModelRunEvent(kind: .finalAnswer, label: "answer", content: message)],
            trace: trace(
                household: household,
                startedAt: startedAt,
                state: state,
                events: events,
                error: errorCode,
                finalProfile: nil
            )
        )
    }

    private func trace(
        household: DemoHousehold?,
        startedAt: Date,
        state: DynamicLocalProfileState,
        events: [ModelRunEvent],
        error: String?,
        finalProfile: ModelProfileID?
    ) -> ModelTrace {
        let activations = state.activationHistory(
            finalAnswerOwnedByProfile: finalProfile != nil
        )
        let profiles = activations.map(\.profile)
        let transitions = zip(profiles, profiles.dropFirst()).map {
            ModelProfileTransition(from: $0.0, to: $0.1)
        }
        let currentPlan = state.currentPlan()
        return ModelTrace(
            strategy: .localOnly,
            provider: .appleOnDevice,
            householdID: household?.id,
            intentID: currentPlan.intent.rawValue,
            tools: currentPlan.toolNames,
            toolEvents: events,
            durationMilliseconds: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)),
            error: error,
            activeProfiles: profiles,
            profileTransitions: transitions,
            profileActivations: activations,
            finalAnswerProfile: finalProfile
        )
    }
}

private struct GroceryDynamicProfile: LanguageModelSession.DynamicProfile {
    let catalog: any ProductCatalog
    let household: DemoHousehold?
    let recorder: DynamicLocalTraceRecorder
    let state: DynamicLocalProfileState

    var body: some LanguageModelSession.DynamicProfile {
        switch state.currentPlan().profile {
        case .localProductDiscovery:
            Profile {
                ProductDiscoveryInstructions(
                    plan: state.currentPlan(),
                    catalog: catalog,
                    recorder: recorder
                )
            }
            .model(SystemLanguageModel.default)
        case .localHouseholdPlanning:
            Profile {
                HouseholdPlanningInstructions(
                    plan: state.currentPlan(),
                    catalog: catalog,
                    household: household,
                    recorder: recorder,
                    state: state
                )
            }
            .model(SystemLanguageModel.default)
        case .localCartReview:
            Profile {
                CartReviewInstructions(
                    plan: state.currentPlan(),
                    household: household,
                    recorder: recorder,
                    state: state
                )
            }
            .model(SystemLanguageModel.default)
            .toolCallingMode(.required)
        case .localCartRecommendation:
            Profile {
                CartRecommendationInstructions(
                    plan: state.currentPlan(),
                    catalog: catalog,
                    recorder: recorder
                )
            }
            .model(SystemLanguageModel.default)
            .toolCallingMode(.allowed)
        case .localGrocery, .claudeGrocery, .claudeChildGrocery:
            Profile {
                ProductDiscoveryInstructions(
                    plan: state.currentPlan(),
                    catalog: catalog,
                    recorder: recorder
                )
            }
            .model(SystemLanguageModel.default)
        }
    }
}

private struct ProductDiscoveryInstructions: DynamicInstructions {
    let plan: LocalGroceryExecutionPlan
    let catalog: any ProductCatalog
    let recorder: DynamicLocalTraceRecorder

    var body: some DynamicInstructions {
        Instructions {
            plan.instructions.joined(separator: "\n")
        }
        DynamicCatalogSearchTool(catalog: catalog, recorder: recorder)
    }
}

private struct HouseholdPlanningInstructions: DynamicInstructions {
    let plan: LocalGroceryExecutionPlan
    let catalog: any ProductCatalog
    let household: DemoHousehold?
    let recorder: DynamicLocalTraceRecorder
    let state: DynamicLocalProfileState

    var body: some DynamicInstructions {
        Instructions {
            plan.instructions.joined(separator: "\n")
        }
        DynamicHouseholdContextTool(
            household: household,
            recorder: recorder,
            profileState: state,
            transitionOnCall: false
        )
        DynamicCatalogSearchTool(catalog: catalog, recorder: recorder)
    }
}

private struct CartReviewInstructions: DynamicInstructions {
    let plan: LocalGroceryExecutionPlan
    let household: DemoHousehold?
    let recorder: DynamicLocalTraceRecorder
    let state: DynamicLocalProfileState

    var body: some DynamicInstructions {
        Instructions {
            plan.instructions.joined(separator: "\n")
        }
        DynamicHouseholdContextTool(
            household: household,
            recorder: recorder,
            profileState: state,
            transitionOnCall: true
        )
    }
}

private struct CartRecommendationInstructions: DynamicInstructions {
    let plan: LocalGroceryExecutionPlan
    let catalog: any ProductCatalog
    let recorder: DynamicLocalTraceRecorder

    var body: some DynamicInstructions {
        Instructions {
            plan.instructions.joined(separator: "\n")
        }
        DynamicCatalogSearchTool(catalog: catalog, recorder: recorder)
    }
}

private final class DynamicLocalProfileState: @unchecked Sendable {
    private let lock = NSLock()
    private var plan: LocalGroceryExecutionPlan
    private var activations: [ModelProfileActivation]

    init(initialPlan: LocalGroceryExecutionPlan) {
        plan = initialPlan
        activations = [initialPlan.activation]
    }

    func currentPlan() -> LocalGroceryExecutionPlan {
        lock.withLock { plan }
    }

    func transitionToCartRecommendation(toolName: String) {
        lock.withLock {
            guard plan.profile == .localCartReview else { return }
            let next = LocalGroceryPolicy.cartRecommendationPlan()
            plan = next
            activations.append(next.activation(trigger: "model-tool:\(toolName)"))
        }
    }

    func activationHistory(finalAnswerOwnedByProfile: Bool = true) -> [ModelProfileActivation] {
        lock.withLock {
            activations.enumerated().map { index, activation in
                ModelProfileActivation(
                    profile: activation.profile,
                    trigger: activation.trigger,
                    effectiveInstructions: activation.effectiveInstructions,
                    tools: activation.tools,
                    selectedModel: activation.selectedModel,
                    ownsFinalAnswer: finalAnswerOwnedByProfile && index == activations.count - 1
                )
            }
        }
    }
}

private actor DynamicLocalTraceRecorder {
    private var recordedEvents: [ModelRunEvent] = []

    func record(_ event: ModelRunEvent) { recordedEvents.append(event) }
    func events() -> [ModelRunEvent] { recordedEvents }
}

@Generable
private struct DynamicCatalogSearchArguments: Sendable {
    let query: String
}

@Generable
private struct DynamicHouseholdContextArguments: Sendable {
    let householdID: String
}

private struct DynamicCatalogSearchTool: Tool, Sendable {
    let catalog: any ProductCatalog
    let recorder: DynamicLocalTraceRecorder

    var name: String { LocalGroceryToolID.catalogSearch.rawValue }
    var description: String { "Search the bundled, on-device grocery catalog for evidence." }

    @concurrent
    func call(arguments: DynamicCatalogSearchArguments) async throws -> String {
        await recorder.record(ModelRunEvent(kind: .toolCall, label: name, content: arguments.query))
        let products = catalog.search(matching: arguments.query)
        let output = products.map { "\($0.name): \($0.detail)" }.joined(separator: "\n")
        let result = output.isEmpty ? "No matching products were found." : output
        await recorder.record(ModelRunEvent(kind: .toolOutput, label: name, content: result))
        return result
    }
}

private struct DynamicHouseholdContextTool: Tool, Sendable {
    let household: DemoHousehold?
    let recorder: DynamicLocalTraceRecorder
    let profileState: DynamicLocalProfileState
    let transitionOnCall: Bool

    var name: String { LocalGroceryToolID.householdContext.rawValue }
    var description: String { "Read the selected fictional Demo Household's local grocery context." }

    @concurrent
    func call(arguments: DynamicHouseholdContextArguments) async throws -> String {
        await recorder.record(
            ModelRunEvent(kind: .toolCall, label: name, content: arguments.householdID)
        )
        if transitionOnCall {
            profileState.transitionToCartRecommendation(toolName: name)
        }
        let output = LocalHouseholdEvidence.render(household)
        await recorder.record(ModelRunEvent(kind: .toolOutput, label: name, content: output))
        return output
    }
}
