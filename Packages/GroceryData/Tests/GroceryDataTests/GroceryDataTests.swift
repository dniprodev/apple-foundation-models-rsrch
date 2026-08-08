import Testing
import GroceryDomain
@testable import GroceryData

struct GroceryDataTests {
    @Test func demoCatalogFindsProductsByNameOrDetail() {
        let catalog = DemoCatalog()

        #expect(catalog.search(matching: "lentil").map(\.name) == ["Green lentils"])
        #expect(catalog.search(matching: "weeknight").map(\.name) == ["Whole-wheat pasta"])
    }

    @Test func demoCatalogFindsEvidenceInsideNaturalLanguageRequests() {
        let catalog = DemoCatalog()

        #expect(catalog.search(matching: "What can I make with lentils?").map(\.name) == ["Green lentils"])
    }

    @Test func householdGenerationIsDeterministicAndUsesCatalogProducts() {
        let products = [
            CatalogProduct(id: ProductID("lentils"), name: "Green lentils", detail: "Pantry staple"),
            CatalogProduct(id: ProductID("pasta"), name: "Whole-wheat pasta", detail: "Weeknight base"),
            CatalogProduct(id: ProductID("tomatoes"), name: "Canned tomatoes", detail: "For sauces")
        ]
        let generator = DemoHouseholdGenerator(catalogProducts: products, seed: 42)

        let first = generator.generate()
        let second = generator.generate()
        let productIDs = Set(products.map(\.id))
        let referencedIDs = Set(first.flatMap { household in
            household.purchaseHistory.map(\.productID)
                + household.pantry.map(\.productID)
                + household.cart.map(\.productID)
        })

        #expect(first == second)
        #expect(first.map(\.id) == DemoHouseholdID.allCases)
        #expect(first.allSatisfy { !$0.purchaseHistory.isEmpty && !$0.pantry.isEmpty })
        #expect(referencedIDs.isSubset(of: productIDs))
    }

    @Test func generatedHouseholdsHaveTheThreeInitialFixtureProfiles() {
        let products = [CatalogProduct(id: ProductID("lentils"), name: "Green lentils", detail: "Pantry staple")]
        let households = DemoHouseholdGenerator(catalogProducts: products, seed: 42).generate()

        let budgetFamily = households[0]
        #expect(budgetFamily.id == .budgetFamily)
        #expect(budgetFamily.members.filter { $0.role == .adult }.count == 2)
        #expect(budgetFamily.members.filter { $0.role == .child }.count == 2)
        #expect(budgetFamily.weeklySpendingTargetCents == 8_500)
        #expect(budgetFamily.restrictions == [.peanutAllergy])

        let nutritionFocusedCouple = households[1]
        #expect(nutritionFocusedCouple.members.count == 2)
        #expect(nutritionFocusedCouple.restrictions == [.lactoseIntolerance])
        #expect(nutritionFocusedCouple.priorities == [.lowerSugar, .lowerSodium])

        let lowWasteSoloShopper = households[2]
        #expect(lowWasteSoloShopper.members.count == 1)
        #expect(lowWasteSoloShopper.restrictions == [.vegetarian])
        #expect(lowWasteSoloShopper.priorities == [.smallPortions, .usePantryFirst])
    }

    @Test func householdStoreResetRestoresGeneratedState() async {
        let products = [CatalogProduct(id: ProductID("lentils"), name: "Green lentils", detail: "Pantry staple")]
        let store = DemoHouseholdStore(catalogProducts: products, seed: 42)
        let original = await store.household(for: .budgetFamily)

        await store.replaceCart(for: .budgetFamily, with: [CartItem(productID: ProductID("lentils"), quantity: 7)])
        await store.reset(.budgetFamily)

        #expect(await store.household(for: .budgetFamily) == original)
    }
}
