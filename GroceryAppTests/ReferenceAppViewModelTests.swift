import XCTest
import GroceryDomain
@testable import GroceryApp

@MainActor
final class ReferenceAppViewModelTests: XCTestCase {
    func testComposedShellRunsALocalRequest() async {
        let model = ReferenceAppViewModel.makeDemo()

        await model.submit("lentils")

        XCTAssertEqual(model.modelRun?.answer.evidence, ["Green lentils"])
    }

    func testSubmitPassesTheSelectedDemoHouseholdToTheLocalRun() async {
        let model = ReferenceAppViewModel.makeDemo()

        await model.load()
        model.selectHousehold(.nutritionFocusedCouple)
        await model.submit("lentils")

        XCTAssertEqual(model.modelRun?.trace.householdID, .nutritionFocusedCouple)
        XCTAssertNil(model.modelRun?.trace.remoteContextView)
    }

    func testModelLoadsAllDemoHouseholdsAndTheirContext() async {
        let model = ReferenceAppViewModel.makeDemo()

        await model.load()
        model.selectHousehold(.lowWasteSoloShopper)

        XCTAssertEqual(model.households.map(\.id), DemoHouseholdID.allCases)
        XCTAssertEqual(model.selectedHousehold?.name, "Low-Waste Solo Shopper")
        XCTAssertEqual(model.selectedHousehold?.restrictions, [.vegetarian])
        XCTAssertFalse(model.selectedHousehold?.pantry.isEmpty ?? true)
        XCTAssertFalse(model.selectedHousehold?.cart.isEmpty ?? true)
    }

    func testCatalogCartActionRequiresExplicitApproval() async {
        let model = ReferenceAppViewModel.makeDemo()

        await model.load()
        model.searchCatalog("weeknight")

        XCTAssertEqual(model.catalogResults.map(\.name), ["Whole-wheat pasta"])
        XCTAssertEqual(model.productName(for: ProductID("green-lentils")), "Green lentils")

        let originalCart = model.selectedHousehold?.cart
        await model.proposeAddingToSelectedHouseholdCart(ProductID("whole-wheat-pasta"))
        XCTAssertEqual(model.selectedHousehold?.cart, originalCart)
        XCTAssertEqual(model.cartProposal?.householdID, .budgetFamily)
        XCTAssertEqual(model.cartProposal?.reason, "Add one Whole-wheat pasta to the cart.")

        await model.declineCartProposal()
        XCTAssertNil(model.cartProposal)
        XCTAssertEqual(model.selectedHousehold?.cart, originalCart)

        await model.proposeAddingToSelectedHouseholdCart(ProductID("whole-wheat-pasta"))
        await model.approveCartProposal()

        XCTAssertNil(model.cartProposal)
        XCTAssertNotEqual(model.selectedHousehold?.cart, originalCart)
    }

    func testResetClearsAnUnapprovedCartProposal() async {
        let model = ReferenceAppViewModel.makeDemo()

        await model.load()
        let originalCart = model.selectedHousehold?.cart
        await model.proposeAddingToSelectedHouseholdCart(ProductID("whole-wheat-pasta"))
        XCTAssertNotNil(model.cartProposal)

        await model.resetSelectedHousehold()

        XCTAssertNil(model.cartProposal)
        XCTAssertEqual(model.selectedHousehold?.cart, originalCart)
    }
}
