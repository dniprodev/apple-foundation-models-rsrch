import Foundation
import Testing
import GroceryDomain
@testable import GroceryComposition

struct GroceryCompositionTests {
    @Test func compositionBuildsAWorkingDomainGraph() async {
        let dependencies = GroceryAppComposition.makeDemoDependencies(useOnDeviceModel: false)
        let run = await dependencies.assistant.answer(for: GroceryRequest(text: "lentils"))

        #expect(run.answer.evidence == ["Green lentils"])
    }

    @Test func compositionProvidesAllInitialDemoHouseholds() async {
        let dependencies = GroceryAppComposition.makeDemoDependencies(useOnDeviceModel: false)

        #expect(await dependencies.householdStore.households().map(\.id) == DemoHouseholdID.allCases)
        #expect(dependencies.phoneAFriendAssistant != nil)
    }

    @Test func productionCompositionUsesBundledPriceBackedCatalog() async throws {
        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        let dependencies = try GroceryAppComposition.makeAppDependencies(
            useOnDeviceModel: false,
            applicationSupportDirectory: supportDirectory
        )

        let nutella = try #require(
            dependencies.catalog.search(matching: "Nutella").first {
                $0.id == ProductID("3017620425035")
            }
        )
        #expect(nutella.name == "Nutella")
        #expect(nutella.detail.contains("EUR"))
        #expect(!dependencies.catalog.search(matching: "lentil").isEmpty)

        let households = await dependencies.householdStore.households()
        #expect(households.map(\.id) == DemoHouseholdID.allCases)
        for household in households {
            let referencedIDs = household.purchaseHistory.map(\.productID)
                + household.pantry.map(\.productID)
                + household.cart.map(\.productID)
            #expect(referencedIDs.allSatisfy { dependencies.catalog.product(for: $0) != nil })
        }
    }
}
