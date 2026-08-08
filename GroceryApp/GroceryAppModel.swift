import Combine
import GroceryComposition
import GroceryDomain

@MainActor
final class GroceryAppModel: ObservableObject {
    @Published private(set) var modelRun: ModelRun?
    @Published private(set) var households: [DemoHousehold] = []
    @Published private(set) var catalogResults: [CatalogProduct] = []
    @Published private(set) var isLoaded = false
    @Published var requestText = ""
    @Published var catalogQuery = ""
    @Published private(set) var selectedHouseholdID: DemoHouseholdID = .budgetFamily

    private let assistant: any GroceryAssistant
    private let catalog: any ProductCatalog
    private let householdStore: any DemoHouseholdRepository

    init(dependencies: AppDependencies) {
        assistant = dependencies.assistant
        catalog = dependencies.catalog
        householdStore = dependencies.householdStore
    }

    static func makeDemo() -> GroceryAppModel {
        GroceryAppModel(dependencies: GroceryAppComposition.makeAppDependencies())
    }

    var selectedHousehold: DemoHousehold? {
        households.first { $0.id == selectedHouseholdID }
    }

    func load() async {
        households = await householdStore.households()
        if !households.contains(where: { $0.id == selectedHouseholdID }) {
            selectedHouseholdID = households.first?.id ?? .budgetFamily
        }
        isLoaded = true
    }

    func selectHousehold(_ id: DemoHouseholdID) {
        guard households.contains(where: { $0.id == id }) else { return }
        selectedHouseholdID = id
    }

    func searchCatalog(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        catalogResults = query.isEmpty ? [] : catalog.search(matching: query)
    }

    func productName(for id: ProductID) -> String {
        catalog.product(for: id)?.name ?? id.rawValue
    }

    func addToSelectedHouseholdCart(_ productID: ProductID) async {
        guard var household = await householdStore.household(for: selectedHouseholdID) else { return }
        if let index = household.cart.firstIndex(where: { $0.productID == productID }) {
            let item = household.cart[index]
            household.cart[index] = CartItem(productID: item.productID, quantity: item.quantity + 1)
        } else {
            household.cart.append(CartItem(productID: productID, quantity: 1))
        }
        await householdStore.replaceCart(for: selectedHouseholdID, with: household.cart)
        await load()
    }

    func resetSelectedHousehold() async {
        await householdStore.reset(selectedHouseholdID)
        await load()
    }

    func resetAllHouseholds() async {
        await householdStore.resetAll()
        await load()
    }

    func submit(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        requestText = trimmed
        modelRun = await assistant.answer(for: GroceryRequest(text: trimmed))
    }
}
