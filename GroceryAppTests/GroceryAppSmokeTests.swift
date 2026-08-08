import XCTest
import GroceryDomain
@testable import GroceryApp

@MainActor
final class GroceryAppSmokeTests: XCTestCase {
    func testComposedShellRunsALocalRequest() async {
        let model = GroceryAppModel.makeDemo()

        await model.submit("lentils")

        XCTAssertEqual(model.modelRun?.answer.evidence, ["Green lentils"])
    }

    func testModelLoadsAllDemoHouseholdsAndTheirContext() async {
        let model = GroceryAppModel.makeDemo()

        await model.load()
        model.selectHousehold(.lowWasteSoloShopper)

        XCTAssertEqual(model.households.map(\.id), DemoHouseholdID.allCases)
        XCTAssertEqual(model.selectedHousehold?.name, "Low-Waste Solo Shopper")
        XCTAssertEqual(model.selectedHousehold?.restrictions, [.vegetarian])
        XCTAssertFalse(model.selectedHousehold?.pantry.isEmpty ?? true)
        XCTAssertFalse(model.selectedHousehold?.cart.isEmpty ?? true)
    }

    func testModelSearchesTheBundledCatalogAndResetsSelectedHousehold() async {
        let model = GroceryAppModel.makeDemo()

        await model.load()
        model.searchCatalog("weeknight")

        XCTAssertEqual(model.catalogResults.map(\.name), ["Whole-wheat pasta"])
        XCTAssertEqual(model.productName(for: ProductID("green-lentils")), "Green lentils")

        let originalCart = model.selectedHousehold?.cart
        await model.addToSelectedHouseholdCart(ProductID("whole-wheat-pasta"))
        XCTAssertNotEqual(model.selectedHousehold?.cart, originalCart)

        await model.resetSelectedHousehold()

        XCTAssertEqual(model.selectedHousehold?.cart, originalCart)
        XCTAssertEqual(model.catalogResults.map(\.name), ["Whole-wheat pasta"])
    }
}
