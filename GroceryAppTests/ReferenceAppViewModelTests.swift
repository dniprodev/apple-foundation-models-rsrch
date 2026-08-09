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

    func testCartScenarioFindsABundledProductThroughProductionComposition() async throws {
        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        let dependencies = try GroceryAppComposition.makeAppDependencies(
            useOnDeviceModel: false,
            applicationSupportDirectory: supportDirectory
        )
        let model = ReferenceAppViewModel(dependencies: dependencies)

        await model.load()
        await model.runScenario(.cartReview)

        let product = try XCTUnwrap(model.catalogResults.first)
        XCTAssertTrue(product.id.rawValue.allSatisfy(\.isNumber))
        XCTAssertNotNil(dependencies.catalog.product(for: product.id))
        XCTAssertTrue(model.cartProposal?.proposedCart.contains {
            $0.productID == product.id
        } == true)
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
            $0.productID == ProductID("green-lentils")
        } == true)
        XCTAssertNotEqual(model.cartProposal?.proposedCart, originalCart)
    }

    func testCartScenarioResetsStateBeforeARepeatableReplay() async {
        let model = ReferenceAppViewModel.makeDemo()

        await model.load()
        await model.runScenario(.cartReview)
        await model.approveCartProposal()
        await model.runScenario(.cartReview)

        var expectedCart = model.cartProposal?.originalCart ?? []
        if let index = expectedCart.firstIndex(where: { $0.productID == ProductID("green-lentils") }) {
            expectedCart[index] = CartItem(
                productID: expectedCart[index].productID,
                quantity: expectedCart[index].quantity + 1
            )
        } else {
            expectedCart.append(CartItem(productID: ProductID("green-lentils"), quantity: 1))
        }
        XCTAssertEqual(model.cartProposal?.proposedCart, expectedCart)
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
        let dependencies = GroceryAppComposition.makeDemoDependencies(
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
