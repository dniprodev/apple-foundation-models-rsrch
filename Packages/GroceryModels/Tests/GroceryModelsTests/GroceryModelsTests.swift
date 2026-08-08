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
