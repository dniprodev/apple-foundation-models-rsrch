import Testing
import GroceryDomain
@testable import GroceryModels

struct GroceryModelsTests {
    @Test func localAssistantReturnsAnEvidenceBackedRun() async {
        let catalog = TestCatalog(products: [CatalogProduct(name: "Green lentils", detail: "A pantry staple.")])
        let run = await LocalGroceryAssistant(catalog: catalog).answer(for: GroceryRequest(text: "lentils"))

        #expect(run.answer.text.contains("Green lentils"))
        #expect(run.answer.evidence == ["Green lentils"])
    }

    @Test func localAssistantRecordsSelectedHouseholdAndToolActivity() async {
        let catalog = TestCatalog(products: [CatalogProduct(name: "Green lentils", detail: "A pantry staple.")])
        let household = DemoHousehold(
            id: .lowWasteSoloShopper,
            name: "Low-Waste Solo Shopper",
            members: [],
            weeklySpendingTargetCents: nil,
            restrictions: [.vegetarian],
            priorities: [.usePantryFirst],
            purchaseHistory: [],
            pantry: [],
            cart: []
        )

        let run = await LocalGroceryAssistant(catalog: catalog).answer(
            for: GroceryRequest(text: "lentils"),
            household: household
        )

        #expect(run.trace.householdID == .lowWasteSoloShopper)
        #expect(run.trace.strategy == .localOnly)
        #expect(run.events.map(\.kind) == [.toolCall, .toolOutput, .finalAnswer])
    }

    @Test func hybridAssistantExplainsWhenClaudeIsNotConfigured() async {
        let provider = TestRemoteProvider(state: .notConfigured)
        let assistant = HybridGroceryAssistant(
            localAssistant: TestLocalAssistant(),
            provider: provider
        )

        let run = await assistant.answer(for: GroceryRequest(text: "find lentils"))

        #expect(run.answer.text == "Hybrid assistance is not configured. Add a Claude credential to continue.")
        #expect(run.trace.strategy == .hybrid)
        #expect(run.trace.provider == .claude)
        #expect(run.trace.error == "claude-not-configured")
        #expect(run.events.map(\.kind) == [.error, .finalAnswer])
    }

    @Test func hybridAssistantUsesAConfiguredFakeProviderWithoutCredentials() async {
        let provider = TestRemoteProvider(
            state: .ready,
            response: RemoteProviderResponse(
                answer: GroceryAnswer(text: "Use the lentils already in the pantry.", evidence: ["Green lentils"]),
                events: [ModelRunEvent(kind: .toolOutput, label: "public-catalog", content: "Green lentils")],
                tools: ["public-catalog"]
            )
        )
        let assistant = HybridGroceryAssistant(
            localAssistant: TestLocalAssistant(),
            provider: provider
        )

        let run = await assistant.answer(
            for: GroceryRequest(text: "find lentils"),
            household: DemoHousehold(
                id: .lowWasteSoloShopper,
                name: "Low-Waste Solo Shopper",
                members: [],
                weeklySpendingTargetCents: nil,
                restrictions: [.vegetarian],
                priorities: [.usePantryFirst],
                purchaseHistory: [],
                pantry: [],
                cart: []
            )
        )

        #expect(run.answer.text == "Use the lentils already in the pantry.")
        #expect(run.trace.strategy == .hybrid)
        #expect(run.trace.provider == .claude)
        #expect(run.trace.householdID == .lowWasteSoloShopper)
        #expect(run.trace.remoteContextView?.contains("Pattern: baton-pass") == true)
        #expect(run.events.map(\.kind) == [.toolOutput, .finalAnswer])
    }

    @Test func batonPassSharesObservableLocalHistoryAndRecordsTheRemoteTransition() async {
        let localRun = ModelRun(
            request: GroceryRequest(text: "find lentils"),
            answer: GroceryAnswer(text: "The pantry already has lentils."),
            events: [
                ModelRunEvent(kind: .toolCall, label: "household-context", content: "pantry=green-lentils"),
                ModelRunEvent(kind: .toolOutput, label: "household-context", content: "Green lentils ×2"),
                ModelRunEvent(kind: .finalAnswer, label: "answer", content: "The pantry already has lentils.")
            ],
            trace: ModelTrace(
                strategy: .localOnly,
                provider: .appleOnDevice,
                householdID: .lowWasteSoloShopper,
                intentID: "catalog-and-household",
                tools: ["household-context"],
                toolEvents: [
                    ModelRunEvent(kind: .toolCall, label: "household-context", content: "pantry=green-lentils"),
                    ModelRunEvent(kind: .toolOutput, label: "household-context", content: "Green lentils ×2")
                ]
            )
        )
        let provider = TestRemoteProvider(
            state: .ready,
            response: RemoteProviderResponse(
                answer: GroceryAnswer(text: "Use the lentils already in the pantry."),
                events: [ModelRunEvent(kind: .toolOutput, label: "public-catalog", content: "Green lentils")],
                tools: ["public-catalog"]
            )
        )
        let assistant = HybridGroceryAssistant(
            localAssistant: TestLocalAssistant(run: localRun),
            provider: provider
        )

        let run = await assistant.answer(
            for: GroceryRequest(text: "find lentils"),
            household: DemoHousehold(
                id: .lowWasteSoloShopper,
                name: "Low-Waste Solo Shopper",
                members: [],
                weeklySpendingTargetCents: nil,
                restrictions: [.vegetarian],
                priorities: [.usePantryFirst],
                purchaseHistory: [],
                pantry: [],
                cart: []
            )
        )

        let invocation = await provider.lastInvocation
        #expect(invocation?.contextView.pattern == .batonPass)
        #expect(invocation?.contextView.sharedHistory.contains {
            $0.content == "Green lentils ×2"
        } == true)
        #expect(invocation?.contextView.privacyConcerns.contains {
            $0.contains("App-Owned Context")
        } == true)
        #expect(run.answer.text == "Use the lentils already in the pantry.")
        #expect(run.trace.orchestrationPattern == .batonPass)
        #expect(run.trace.profileTransitions == [
            ModelProfileTransition(from: .localGrocery, to: .claudeGrocery)
        ])
        #expect(run.trace.finalAnswerProfile == .claudeGrocery)
        #expect(run.trace.correlationID == invocation?.correlationID)
        #expect(run.trace.remoteContextID == invocation?.remoteContextID)
        #expect(invocation?.contextView.toolOutputs.map(\.content) == ["Green lentils ×2"])
        #expect(invocation?.contextView.selectedOptions.contains("history=shared") == true)
        #expect(run.trace.remoteContextView == invocation?.contextView.rendered)
        #expect(run.events.map(\.kind) == [.toolCall, .toolOutput, .modelOutput, .toolOutput, .finalAnswer])
        #expect(run.events.last?.label == "claude-answer")
    }

    @Test func batonPassKeepsDisclosureFactsWhenTheRemoteRequestFails() async {
        let localRun = ModelRun(
            request: GroceryRequest(text: "find lentils"),
            answer: GroceryAnswer(text: "The pantry already has lentils."),
            events: [
                ModelRunEvent(kind: .toolOutput, label: "household-context", content: "Green lentils ×2"),
                ModelRunEvent(kind: .finalAnswer, label: "answer", content: "The pantry already has lentils.")
            ],
            trace: ModelTrace(
                strategy: .localOnly,
                provider: .appleOnDevice,
                householdID: .lowWasteSoloShopper,
                intentID: "catalog-and-household",
                tools: ["household-context"],
                toolEvents: [
                    ModelRunEvent(kind: .toolOutput, label: "household-context", content: "Green lentils ×2")
                ]
            )
        )
        let provider = TestRemoteProvider(
            state: .ready,
            failure: .transportFailed
        )
        let assistant = HybridGroceryAssistant(
            localAssistant: TestLocalAssistant(run: localRun),
            provider: provider
        )

        let run = await assistant.answer(for: GroceryRequest(text: "find lentils"))

        #expect(run.trace.error == "claude-request-failed")
        #expect(run.trace.orchestrationPattern == .batonPass)
        #expect(run.trace.remoteContextView?.contains("Green lentils ×2") == true)
        #expect(run.trace.toolEvents.map(\.label) == ["household-context"])
        #expect(run.events.map(\.kind) == [.toolOutput, .modelOutput, .error, .finalAnswer])
    }

    @Test func phoneAFriendUsesAnIsolatedValidatedTaskAndKeepsFinalAnswerWithTheParent() async {
        let localRun = ModelRun(
            request: GroceryRequest(text: "Find a lower-sugar cereal"),
            answer: GroceryAnswer(text: "The household prefers lower sugar."),
            events: [
                ModelRunEvent(kind: .toolCall, label: "search-catalog", content: "Find a lower-sugar cereal"),
                ModelRunEvent(kind: .toolOutput, label: "search-catalog", content: "Plain oats"),
                ModelRunEvent(kind: .toolOutput, label: "household-context", content: "lower-sugar"),
                ModelRunEvent(kind: .finalAnswer, label: "answer", content: "The household prefers lower sugar.")
            ],
            trace: ModelTrace(
                strategy: .localOnly,
                provider: .appleOnDevice,
                householdID: .nutritionFocusedCouple,
                intentID: "catalog-and-household",
                tools: ["search-catalog", "household-context"],
                toolEvents: [
                    ModelRunEvent(kind: .toolCall, label: "search-catalog", content: "Find a lower-sugar cereal"),
                    ModelRunEvent(kind: .toolOutput, label: "search-catalog", content: "Plain oats"),
                    ModelRunEvent(kind: .toolOutput, label: "household-context", content: "lower-sugar")
                ]
            )
        )
        let provider = TestRemoteProvider(
            state: .ready,
            response: RemoteProviderResponse(
                answer: GroceryAnswer(text: "Plain oats are the narrowest public-catalog match."),
                events: [ModelRunEvent(kind: .toolOutput, label: "public-catalog", content: "Plain oats")],
                tools: ["public-catalog"]
            )
        )
        let assistant = HybridGroceryAssistant(
            localAssistant: TestLocalAssistant(run: localRun),
            provider: provider,
            pattern: .phoneAFriend,
            parentAnswerer: TestPhoneParentAnswerer(
                answer: GroceryAnswer(text: "The local parent recommends plain oats while respecting lower-sugar priorities.")
            )
        )

        let run = await assistant.answer(
            for: GroceryRequest(text: "Find a lower-sugar cereal"),
            household: DemoHousehold(
                id: .nutritionFocusedCouple,
                name: "Nutrition-Focused Couple",
                members: [],
                weeklySpendingTargetCents: nil,
                restrictions: [.lactoseIntolerance],
                priorities: [.lowerSugar],
                purchaseHistory: [],
                pantry: [],
                cart: []
            )
        )

        let invocation = await provider.lastInvocation
        #expect(invocation?.contextView.pattern == .phoneAFriend)
        #expect(invocation?.contextView.sessionOwnership == .isolatedChild)
        #expect(invocation?.session.ownership == .isolatedChild)
        #expect(invocation?.sessionID != invocation?.parentSessionID)
        #expect(invocation?.contextView.remoteTask?.instructionText == "Use only public catalog evidence to help the parent answer: Find a lower-sugar cereal")
        #expect(invocation?.contextView.sharedHistory.isEmpty == true)
        #expect(invocation?.contextView.toolOutputs.map(\.content) == ["Plain oats"])
        #expect(invocation?.contextView.toolDefinitions == ["public-catalog"])
        #expect(invocation?.contextView.selectedOptions.contains("history=isolated-child") == true)
        #expect(invocation?.contextView.selectedOptions.contains("final-answer-owner=local-grocery") == true)
        #expect(invocation?.contextView.privacyConcerns.contains {
            $0.contains("Narrower")
        } == true)
        #expect(run.answer.text == "The local parent recommends plain oats while respecting lower-sugar priorities.")
        #expect(run.trace.orchestrationPattern == .phoneAFriend)
        #expect(run.trace.activeProfiles == [.localGrocery, .claudeChildGrocery])
        #expect(run.trace.profileTransitions == [
            ModelProfileTransition(from: .localGrocery, to: .claudeChildGrocery),
            ModelProfileTransition(from: .claudeChildGrocery, to: .localGrocery)
        ])
        #expect(run.trace.finalAnswerProfile == .localGrocery)
        #expect(run.trace.remoteSessionID == invocation?.sessionID)
        #expect(run.trace.parentRemoteSessionID == invocation?.parentSessionID)
        #expect(run.trace.remoteContextView == invocation?.contextView.rendered)
        #expect(run.events.last?.kind == .finalAnswer)
        #expect(run.events.last?.label == "local-parent-answer")
    }

    @Test func phoneAFriendRejectsAnInvalidTaskBeforeCallingTheRemoteProvider() async {
        let provider = TestRemoteProvider(state: .ready)
        let assistant = HybridGroceryAssistant(
            localAssistant: TestLocalAssistant(),
            provider: provider,
            pattern: .phoneAFriend
        )

        let run = await assistant.answer(for: GroceryRequest(text: " \n"))

        #expect(run.trace.error == "phone-friend-task-invalid")
        #expect(run.trace.orchestrationPattern == nil)
        #expect(run.trace.remoteContextView == nil)
        #expect(run.events.map(\.kind) == [.error, .finalAnswer])
        #expect(await provider.lastInvocation == nil)
    }

    @Test func phoneAFriendFailsClosedWhenTheChildReturnsAnUndisclosedTool() async {
        let provider = TestRemoteProvider(
            state: .ready,
            response: RemoteProviderResponse(
                answer: GroceryAnswer(text: "unused"),
                tools: ["private-household"]
            )
        )
        let assistant = HybridGroceryAssistant(
            localAssistant: TestLocalAssistant(),
            provider: provider,
            pattern: .phoneAFriend
        )

        let run = await assistant.answer(for: GroceryRequest(text: "Find cereal"))

        #expect(run.trace.error == "claude-disallowed-tool")
        #expect(run.trace.orchestrationPattern == .phoneAFriend)
        #expect(run.trace.remoteContextView?.contains("Session ownership: isolated-child-session") == true)
        #expect(run.events.last?.kind == .finalAnswer)
    }

    @Test func claudeProviderReportsSetupStateAndPassesCredentialOnlyToItsResponder() async throws {
        let credentials = TestClaudeCredentialStore(apiKey: "configured-key")
        let responder = TestClaudeResponder()
        let provider = ClaudeRemoteProvider(credentialStore: credentials, responder: responder)

        #expect(await provider.availability() == .ready)
        let response = try await provider.respond(
            to: RemoteGroceryInvocation(
                contextView: RemoteContextView(
                    pattern: .batonPass,
                    instructions: "Answer the grocery request.",
                    prompt: "lentils",
                    sharedHistory: [],
                    toolDefinitions: [],
                    privacyConcerns: []
                )
            )
        )

        #expect(response.answer.text == "Remote lentil answer")
        #expect(await responder.lastCredential == "configured-key")
    }
}

private actor TestRemoteProvider: RemoteGroceryProvider {
    let state: RemoteProviderState
    let response: RemoteProviderResponse
    let failure: TestRemoteProviderError?
    private(set) var lastInvocation: RemoteGroceryInvocation?

    init(
        state: RemoteProviderState,
        response: RemoteProviderResponse? = nil,
        failure: TestRemoteProviderError? = nil
    ) {
        self.state = state
        self.response = response ?? RemoteProviderResponse(answer: GroceryAnswer(text: "unused"))
        self.failure = failure
    }

    nonisolated var provider: ModelProvider { .claude }

    func availability() async -> RemoteProviderState { state }

    func respond(
        to invocation: RemoteGroceryInvocation
    ) async throws -> RemoteProviderResponse {
        lastInvocation = invocation
        if let failure {
            throw failure
        }
        return response
    }
}

private enum TestRemoteProviderError: Error, Sendable {
    case transportFailed
}

private struct TestLocalAssistant: GroceryAssistant {
    let run: ModelRun

    init(run: ModelRun? = nil) {
        self.run = run ?? ModelRun(
            request: GroceryRequest(text: "local request"),
            answer: GroceryAnswer(text: "local answer")
        )
    }

    func answer(for request: GroceryRequest, household: DemoHousehold?) async -> ModelRun {
        return run
    }
}

private struct TestPhoneParentAnswerer: PhoneAFriendParentAnswerer {
    let answer: GroceryAnswer

    func answer(
        for request: GroceryRequest,
        childAnswer: GroceryAnswer,
        household: DemoHousehold?
    ) async -> GroceryAnswer {
        answer
    }
}

private actor TestClaudeCredentialStore: ClaudeCredentialStore {
    let apiKey: String?

    init(apiKey: String?) {
        self.apiKey = apiKey
    }

    func hasCredential() async -> Bool { apiKey != nil }

    func credential() async -> String? { apiKey }

    func save(apiKey: String) async throws {}

    func remove() async throws {}
}

private actor TestClaudeResponder: ClaudeResponder {
    private(set) var lastCredential: String?

    func availability() async -> RemoteProviderState { .ready }

    func respond(
        to invocation: RemoteGroceryInvocation,
        apiKey: String
    ) async throws -> RemoteProviderResponse {
        lastCredential = apiKey
        return RemoteProviderResponse(answer: GroceryAnswer(text: "Remote lentil answer"))
    }
}

private struct TestCatalog: ProductCatalog, Sendable {
    let products: [CatalogProduct]

    func search(matching text: String) -> [CatalogProduct] {
        let query = text.lowercased()
        return products.filter { $0.name.lowercased().contains(query) }
    }

    func product(for id: ProductID) -> CatalogProduct? {
        products.first { $0.id == id }
    }
}
