import Combine
import GroceryComposition
import GroceryDomain

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
    @Published var requestText = ""
    @Published var catalogQuery = ""
    @Published var claudeCredentialInput = ""
    @Published var selectedStrategy: ModelStrategy = .localOnly
    @Published private(set) var selectedHouseholdID: DemoHouseholdID = .budgetFamily

    private let localAssistant: any GroceryAssistant
    private let hybridAssistant: (any GroceryAssistant)?
    private let catalog: any ProductCatalog
    private let householdStore: any DemoHouseholdRepository
    private let claudeCredentialStore: (any ClaudeCredentialStore)?

    init(dependencies: AppDependencies) {
        localAssistant = dependencies.assistant
        hybridAssistant = dependencies.hybridAssistant
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

    func submit(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        requestText = trimmed
        let household = await householdStore.household(for: selectedHouseholdID)
        let assistant = selectedStrategy == .hybrid ? hybridAssistant : localAssistant
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
