import XCTest
import GroceryDomain
import GroceryModels
@testable import GroceryApp
import GroceryComposition

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

    func testManualDemoScenariosCoverMilestoneOnePaths() {
        XCTAssertEqual(
            Set(ManualDemoScenario.allCases),
            Set([
                .privatePurchaseAnalysis,
                .healthierSubstitutions,
                .pantryAwarePlanning,
                .cartReview,
                .householdComparison,
                .batonPass,
                .phoneAFriend,
                .missingClaudeSetup,
                .providerFailure
            ])
        )
    }

    func testRunningPhoneAFriendScenarioSelectsItsHouseholdStrategyAndRequest() async {
        let model = ReferenceAppViewModel.makeDemo()

        await model.load()
        await model.runScenario(.phoneAFriend)

        XCTAssertEqual(model.selectedHouseholdID, .lowWasteSoloShopper)
        XCTAssertEqual(model.selectedStrategy, .hybrid)
        XCTAssertEqual(model.selectedOrchestrationPattern, .phoneAFriend)
        XCTAssertEqual(model.requestText, ManualDemoScenario.phoneAFriend.request.text)
        XCTAssertEqual(model.modelRun?.request.text, ManualDemoScenario.phoneAFriend.request.text)
        XCTAssertEqual(model.modelRun?.trace.strategy, .hybrid)
    }

    func testCartScenarioCreatesAProposalWithoutChangingTheCart() async {
        let model = ReferenceAppViewModel.makeDemo()

        await model.load()
        let originalCart = model.selectedHousehold?.cart
        await model.runScenario(.cartReview)

        XCTAssertEqual(model.selectedHousehold?.cart, originalCart)
        XCTAssertEqual(model.catalogQuery, ManualDemoScenario.cartReview.catalogQuery)
        XCTAssertEqual(model.cartProposal?.householdID, .budgetFamily)
        XCTAssertTrue(model.cartProposal?.proposedCart.contains {
            $0.productID == ProductID("whole-wheat-pasta")
        } == true)
        XCTAssertNotEqual(model.cartProposal?.proposedCart, originalCart)
    }

    func testCartScenarioResetsStateBeforeARepeatableReplay() async {
        let model = ReferenceAppViewModel.makeDemo()

        await model.load()
        await model.runScenario(.cartReview)
        await model.approveCartProposal()
        await model.runScenario(.cartReview)

        XCTAssertEqual(model.cartProposal?.proposedCart, model.cartProposal?.originalCart.map {
            $0.productID == ProductID("whole-wheat-pasta")
                ? CartItem(productID: $0.productID, quantity: $0.quantity + 1)
                : $0
        })
    }

    func testHouseholdComparisonPreservesAHouseholdChosenBetweenRuns() async {
        let model = ReferenceAppViewModel.makeDemo()

        await model.load()
        await model.runScenario(.householdComparison)
        model.selectHousehold(.lowWasteSoloShopper)
        await model.runScenario(.householdComparison)

        XCTAssertEqual(model.selectedHouseholdID, .lowWasteSoloShopper)
        XCTAssertEqual(model.modelRun?.trace.householdID, .lowWasteSoloShopper)
    }

    func testPhoneAFriendScenarioExposesItsIsolatedTraceWithAConfiguredFake() async {
        let dependencies = GroceryAppComposition.makeAppDependencies(
            useOnDeviceModel: false,
            claudeCredentialStore: ConfiguredClaudeCredentialStore(),
            claudeResponder: ScriptedClaudeResponder()
        )
        let model = ReferenceAppViewModel(dependencies: dependencies)

        await model.load()
        await model.runScenario(.phoneAFriend)

        XCTAssertEqual(model.modelRun?.trace.orchestrationPattern, .phoneAFriend)
        XCTAssertEqual(model.modelRun?.trace.finalAnswerProfile, .localGrocery)
        XCTAssertTrue(model.modelRun?.trace.remoteContextView?.contains("Session ownership: isolated-child-session") == true)
        XCTAssertTrue(model.modelRun?.trace.remoteContextView?.contains("Remote task:") == true)
        XCTAssertNotNil(model.modelRun?.trace.remoteSessionID)
        XCTAssertNotNil(model.modelRun?.trace.parentRemoteSessionID)
    }

}

private struct ConfiguredClaudeCredentialStore: ClaudeCredentialStore {
    func hasCredential() async -> Bool { true }
    func credential() async -> String? { "test-only-key" }
    func save(apiKey: String) async throws {}
    func remove() async throws {}
}

private struct ScriptedClaudeResponder: ClaudeResponder {
    func availability() async -> RemoteProviderState { .ready }

    func respond(
        to invocation: RemoteGroceryInvocation,
        apiKey: String
    ) async throws -> RemoteProviderResponse {
        RemoteProviderResponse(
            answer: GroceryAnswer(text: "The public catalog has a suitable match."),
            events: [
                ModelRunEvent(
                    kind: .toolOutput,
                    label: "public-catalog",
                    content: "Green lentils"
                )
            ],
            tools: ["public-catalog"]
        )
    }
}
