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
        let assistant = HybridGroceryAssistant(provider: provider)

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
                tools: ["public-catalog"],
                remoteContextView: "Remote Task: find a pantry-friendly lentil option."
            )
        )
        let assistant = HybridGroceryAssistant(provider: provider)

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
        #expect(run.trace.remoteContextView == "Remote Task: find a pantry-friendly lentil option.")
        #expect(run.events.map(\.kind) == [.toolOutput, .finalAnswer])
    }

    @Test func claudeProviderReportsSetupStateAndPassesCredentialOnlyToItsResponder() async throws {
        let credentials = TestClaudeCredentialStore(apiKey: "configured-key")
        let responder = TestClaudeResponder()
        let provider = ClaudeRemoteProvider(credentialStore: credentials, responder: responder)

        #expect(await provider.availability() == .ready)
        let response = try await provider.respond(to: GroceryRequest(text: "lentils"), household: nil)

        #expect(response.answer.text == "Remote lentil answer")
        #expect(await responder.lastCredential == "configured-key")
    }
}

private struct TestRemoteProvider: RemoteGroceryProvider {
    let state: RemoteProviderState
    var response = RemoteProviderResponse(answer: GroceryAnswer(text: "unused"))

    init(state: RemoteProviderState, response: RemoteProviderResponse? = nil) {
        self.state = state
        if let response {
            self.response = response
        }
    }

    var provider: ModelProvider { .claude }

    func availability() async -> RemoteProviderState { state }

    func respond(
        to request: GroceryRequest,
        household: DemoHousehold?
    ) async throws -> RemoteProviderResponse {
        response
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
        to request: GroceryRequest,
        household: DemoHousehold?,
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
