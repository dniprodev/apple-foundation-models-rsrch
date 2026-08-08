import Combine
import GroceryComposition
import GroceryDomain

enum ManualDemoScenario: String, CaseIterable, Identifiable, Hashable {
    case privatePurchaseAnalysis
    case healthierSubstitutions
    case pantryAwarePlanning
    case cartReview
    case householdComparison
    case batonPass
    case phoneAFriend
    case missingClaudeSetup
    case providerFailure

    private struct Configuration {
        let title: String
        let description: String
        let householdID: DemoHouseholdID
        let strategy: ModelStrategy
        let orchestrationPattern: OrchestrationPattern
        let request: GroceryRequest
        let catalogQuery: String
    }

    var id: String { rawValue }

    private var configuration: Configuration {
        switch self {
        case .privatePurchaseAnalysis:
            Configuration(
                title: "Private purchase analysis",
                description: "Run a local-only request against a fictional household and inspect its household and catalog evidence.",
                householdID: .budgetFamily,
                strategy: .localOnly,
                orchestrationPattern: .batonPass,
                request: GroceryRequest(text: "lentils"),
                catalogQuery: ""
            )
        case .healthierSubstitutions:
            Configuration(
                title: "Hybrid healthier substitutions",
                description: "Compare a hybrid substitution request with the selected household's dietary priorities and inspect the remote context.",
                householdID: .nutritionFocusedCouple,
                strategy: .hybrid,
                orchestrationPattern: .batonPass,
                request: GroceryRequest(text: "Find a lower-sugar cereal"),
                catalogQuery: ""
            )
        case .pantryAwarePlanning:
            Configuration(
                title: "Pantry-aware planning",
                description: "Ask for a pantry-aware plan through an isolated child session and inspect the bounded Remote Task.",
                householdID: .lowWasteSoloShopper,
                strategy: .hybrid,
                orchestrationPattern: .phoneAFriend,
                request: GroceryRequest(text: "Plan a low-waste dinner using pantry items"),
                catalogQuery: ""
            )
        case .cartReview:
            Configuration(
                title: "Cart review and approval",
                description: "Open a cart proposal preview, verify the cart is unchanged, then approve or decline it explicitly.",
                householdID: .budgetFamily,
                strategy: .localOnly,
                orchestrationPattern: .batonPass,
                request: GroceryRequest(text: "weeknight"),
                catalogQuery: "weeknight"
            )
        case .householdComparison:
            Configuration(
                title: "Cross-household personalization",
                description: "Repeat the same request after switching households and compare the household IDs and evidence in Model Trace.",
                householdID: .nutritionFocusedCouple,
                strategy: .localOnly,
                orchestrationPattern: .batonPass,
                request: GroceryRequest(text: "lentils"),
                catalogQuery: ""
            )
        case .batonPass:
            Configuration(
                title: "Baton-pass disclosure",
                description: "Inspect shared-history disclosure and Claude's final-answer ownership.",
                householdID: .budgetFamily,
                strategy: .hybrid,
                orchestrationPattern: .batonPass,
                request: GroceryRequest(text: "Find a lower-sugar cereal"),
                catalogQuery: ""
            )
        case .phoneAFriend:
            Configuration(
                title: "Phone-a-friend disclosure",
                description: "Inspect isolated child-session disclosure and the local parent's final-answer ownership.",
                householdID: .lowWasteSoloShopper,
                strategy: .hybrid,
                orchestrationPattern: .phoneAFriend,
                request: GroceryRequest(text: "Plan a low-waste dinner using pantry items"),
                catalogQuery: ""
            )
        case .missingClaudeSetup:
            Configuration(
                title: "Missing Claude setup",
                description: "Remove the credential, run the request, and inspect the generic setup message and safe error code.",
                householdID: .budgetFamily,
                strategy: .hybrid,
                orchestrationPattern: .batonPass,
                request: GroceryRequest(text: "Find lentils"),
                catalogQuery: ""
            )
        case .providerFailure:
            Configuration(
                title: "Provider failure",
                description: "With a credential saved, run the request and inspect the generic provider failure and safe trace facts.",
                householdID: .budgetFamily,
                strategy: .hybrid,
                orchestrationPattern: .batonPass,
                request: GroceryRequest(text: "Find lentils"),
                catalogQuery: ""
            )
        }
    }

    var title: String { configuration.title }
    var description: String { configuration.description }
    var householdID: DemoHouseholdID { configuration.householdID }
    var strategy: ModelStrategy { configuration.strategy }
    var orchestrationPattern: OrchestrationPattern { configuration.orchestrationPattern }
    var request: GroceryRequest { configuration.request }
    var catalogQuery: String { configuration.catalogQuery }
}

@MainActor
final class ReferenceAppViewModel: ObservableObject {
    @Published private(set) var modelRun: ModelRun?
    @Published private(set) var cartProposal: CartProposal?
    @Published private(set) var cartProposalError: String?
    @Published private(set) var households: [DemoHousehold] = []
    @Published private(set) var catalogResults: [CatalogProduct] = []
    @Published private(set) var isLoaded = false
    @Published private(set) var claudeCredentialConfigured = false
    @Published private(set) var claudeCredentialError: String?
    @Published private(set) var selectedScenario: ManualDemoScenario?
    @Published var requestText = ""
    @Published var catalogQuery = ""
    @Published var claudeCredentialInput = ""
    @Published var selectedStrategy: ModelStrategy = .localOnly
    @Published var selectedOrchestrationPattern: OrchestrationPattern = .batonPass
    @Published private(set) var selectedHouseholdID: DemoHouseholdID = .budgetFamily

    private let localAssistant: any GroceryAssistant
    private let hybridAssistant: (any GroceryAssistant)?
    private let phoneAFriendAssistant: (any GroceryAssistant)?
    private let catalog: any ProductCatalog
    private let householdStore: any DemoHouseholdRepository
    private let claudeCredentialStore: (any ClaudeCredentialStore)?

    init(dependencies: AppDependencies) {
        localAssistant = dependencies.assistant
        hybridAssistant = dependencies.hybridAssistant
        phoneAFriendAssistant = dependencies.phoneAFriendAssistant
        catalog = dependencies.catalog
        householdStore = dependencies.householdStore
        claudeCredentialStore = dependencies.claudeCredentialStore
    }

    static func makeDemo() -> ReferenceAppViewModel {
        ReferenceAppViewModel(
            dependencies: GroceryAppComposition.makeAppDependencies(useOnDeviceModel: false)
        )
    }

    var selectedHousehold: DemoHousehold? {
        households.first { $0.id == selectedHouseholdID }
    }

    func load() async {
        households = await householdStore.households()
        if !households.contains(where: { $0.id == selectedHouseholdID }) {
            selectedHouseholdID = households.first?.id ?? .budgetFamily
        }
        await refreshClaudeCredentialState()
        isLoaded = true
    }

    func refreshClaudeCredentialState() async {
        claudeCredentialConfigured = await claudeCredentialStore?.hasCredential() ?? false
    }

    func saveClaudeCredential() async {
        guard let claudeCredentialStore else { return }
        claudeCredentialError = nil
        do {
            try await claudeCredentialStore.save(apiKey: claudeCredentialInput)
            claudeCredentialInput = ""
            await refreshClaudeCredentialState()
        } catch {
            claudeCredentialError = "The Claude credential could not be saved."
        }
    }

    func removeClaudeCredential() async {
        guard let claudeCredentialStore else { return }
        claudeCredentialError = nil
        do {
            try await claudeCredentialStore.remove()
            await refreshClaudeCredentialState()
        } catch {
            claudeCredentialError = "The Claude credential could not be removed."
        }
    }

    func selectHousehold(_ id: DemoHouseholdID) {
        guard households.contains(where: { $0.id == id }) else { return }
        selectedHouseholdID = id
        cartProposal = nil
        cartProposalError = nil
    }

    func searchCatalog(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        catalogResults = query.isEmpty ? [] : catalog.search(matching: query)
    }

    func productName(for id: ProductID) -> String {
        catalog.product(for: id)?.name ?? id.rawValue
    }

    func proposeAddingToSelectedHouseholdCart(_ productID: ProductID) async {
        guard var household = await householdStore.household(for: selectedHouseholdID) else { return }
        guard let product = catalog.product(for: productID) else { return }
        let originalCart = household.cart
        if let index = household.cart.firstIndex(where: { $0.productID == productID }) {
            let item = household.cart[index]
            household.cart[index] = CartItem(productID: item.productID, quantity: item.quantity + 1)
        } else {
            household.cart.append(CartItem(productID: productID, quantity: 1))
        }
        cartProposalError = nil
        cartProposal = CartProposal(
            householdID: selectedHouseholdID,
            originalCart: originalCart,
            proposedCart: household.cart,
            reason: "Add one \(product.name) to the cart."
        )
    }

    func approveCartProposal() async {
        guard let proposal = cartProposal else { return }
        if await householdStore.apply(proposal) {
            cartProposal = nil
            cartProposalError = nil
            await load()
        } else {
            cartProposalError = "The cart changed before this proposal was approved. Review it and try again."
        }
    }

    func declineCartProposal() async {
        cartProposal = nil
        cartProposalError = nil
    }

    func resetSelectedHousehold() async {
        await householdStore.reset(selectedHouseholdID)
        cartProposal = nil
        cartProposalError = nil
        await load()
    }

    func resetAllHouseholds() async {
        await householdStore.resetAll()
        cartProposal = nil
        cartProposalError = nil
        await load()
    }

    func runScenario(_ scenario: ManualDemoScenario) async {
        let isCartReview = scenario == .cartReview
        let preservesComparisonHousehold = selectedScenario == scenario && scenario == .householdComparison
        if isCartReview {
            await householdStore.reset(scenario.householdID)
        }
        selectedScenario = scenario
        if !preservesComparisonHousehold {
            selectHousehold(scenario.householdID)
        }
        selectedStrategy = scenario.strategy
        selectedOrchestrationPattern = scenario.orchestrationPattern
        catalogQuery = scenario.catalogQuery
        searchCatalog(catalogQuery)

        await submit(scenario.request.text)

        if isCartReview {
            await load()
            await proposeAddingToSelectedHouseholdCart(ProductID("whole-wheat-pasta"))
        }
    }

    func submit(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        requestText = trimmed
        let household = await householdStore.household(for: selectedHouseholdID)
        let assistant: (any GroceryAssistant)?
        if selectedStrategy == .localOnly {
            assistant = localAssistant
        } else {
            assistant = selectedOrchestrationPattern == .phoneAFriend
                ? phoneAFriendAssistant
                : hybridAssistant
        }
        guard let assistant else {
            modelRun = ModelRun(
                request: GroceryRequest(text: trimmed),
                answer: GroceryAnswer(text: "Hybrid assistance is not available in this build."),
                events: [
                    ModelRunEvent(kind: .error, label: "hybrid-unavailable", content: "Hybrid assistance is not available in this build."),
                    ModelRunEvent(kind: .finalAnswer, label: "answer", content: "Hybrid assistance is not available in this build.")
                ],
                trace: ModelTrace(
                    strategy: .hybrid,
                    provider: .claude,
                    householdID: household?.id,
                    intentID: "catalog-and-household",
                    tools: [],
                    error: "hybrid-unavailable"
                )
            )
            return
        }
        modelRun = await assistant.answer(
            for: GroceryRequest(text: trimmed),
            household: household
        )
    }
}
