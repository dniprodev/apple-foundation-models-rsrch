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

    @Test func claudeProviderReportsSetupStateAndPassesCredentialOnlyToItsResponder() async throws {
        let credentials = TestClaudeCredentialStore(apiKey: "configured-key")
        let responder = TestClaudeResponder()
        let provider = ClaudeRemoteProvider(credentialStore: credentials, responder: responder)

        #expect(await provider.availability() == .ready)
        let response = try await provider.respond(
            to: RemoteGroceryInvocation(
                request: GroceryRequest(text: "lentils"),
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
        run
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
