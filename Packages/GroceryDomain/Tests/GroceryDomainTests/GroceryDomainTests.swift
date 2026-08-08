import Testing
@testable import GroceryDomain

struct GroceryDomainTests {
    @Test func requestAndRunPreserveTheUserRequest() async {
        let request = GroceryRequest(text: "What can I make with lentils?")
        let answer = GroceryAnswer(text: "Try a lentil soup.")
        let run = ModelRun(request: request, answer: answer)

        #expect(run.request == request)
        #expect(run.answer == answer)
    }

    @Test func modelRunKeepsObservableEventsAndLocalTraceFactsInOrder() {
        let request = GroceryRequest(text: "What can I make with lentils?")
        let events = [
            ModelRunEvent(kind: .toolCall, label: "search-catalog", content: "lentils"),
            ModelRunEvent(kind: .toolOutput, label: "search-catalog", content: "Green lentils"),
            ModelRunEvent(kind: .finalAnswer, label: "answer", content: "Try a lentil soup.")
        ]
        let trace = ModelTrace(
            strategy: .localOnly,
            provider: .appleOnDevice,
            householdID: .budgetFamily,
            intentID: "catalog-and-household",
            tools: ["search-catalog", "household-context"],
            toolEvents: events,
            durationMilliseconds: 42
        )
        let run = ModelRun(request: request, answer: GroceryAnswer(text: "Try a lentil soup."), events: events, trace: trace)

        #expect(run.events.map(\.kind) == [.toolCall, .toolOutput, .finalAnswer])
        #expect(run.trace.strategy == .localOnly)
        #expect(run.trace.householdID == .budgetFamily)
        #expect(run.trace.tools == ["search-catalog", "household-context"])
        #expect(run.trace.toolEvents.map(\.kind) == [.toolCall, .toolOutput])
        #expect(run.trace.remoteContextView == nil)
    }

    @Test func demoHouseholdCarriesFictionalGroceryContext() {
        let lentils = ProductID("lentils")
        let household = DemoHousehold(
            id: .budgetFamily,
            name: "Budget Family",
            members: [HouseholdMember(name: "Alex", role: .adult)],
            weeklySpendingTargetCents: 12_500,
            restrictions: [.peanutAllergy],
            priorities: [.budget],
            purchaseHistory: [PurchaseRecord(productID: lentils, quantity: 2, sequence: 1)],
            pantry: [PantryItem(productID: lentils, quantity: 1)],
            cart: [CartItem(productID: lentils, quantity: 1)]
        )

        #expect(household.id == .budgetFamily)
        #expect(household.purchaseHistory[0].productID == lentils)
        #expect(household.pantry[0].quantity == 1)
        #expect(household.cart[0].quantity == 1)
    }

    @Test func cartProposalDescribesAChangeWithoutChangingTheCart() {
        let lentils = ProductID("lentils")
        let originalCart = [CartItem(productID: lentils, quantity: 1)]
        let proposedCart = [CartItem(productID: lentils, quantity: 2)]
        let proposal = CartProposal(
            householdID: .budgetFamily,
            originalCart: originalCart,
            proposedCart: proposedCart,
            reason: "Add one more package of Green lentils."
        )

        #expect(proposal.householdID == .budgetFamily)
        #expect(proposal.originalCart == originalCart)
        #expect(proposal.proposedCart == proposedCart)
        #expect(proposal.reason == "Add one more package of Green lentils.")
        #expect(originalCart == [CartItem(productID: lentils, quantity: 1)])
    }

    @Test func remoteTaskIsCanonicalAndBoundedBeforeDisclosure() throws {
        let task = try RemoteTask(request: GroceryRequest(text: "  Find lower-sugar cereal  "))

        #expect(task.instructionText == "Use only public catalog evidence to help the parent answer: Find lower-sugar cereal")
        #expect(task.requestText == "Find lower-sugar cereal")
        #expect(task.instructionText.count <= RemoteTask.maximumRequestLength + RemoteTask.instructionPrefix.count)
    }

    @Test func remoteTaskRejectsEmptyAndOverlongRequestsDeterministically() {
        #expect(throws: RemoteTaskValidationError.emptyRequest) {
            try RemoteTask(request: GroceryRequest(text: " \n\t "))
        }

        let overlongRequest = String(repeating: "a", count: RemoteTask.maximumRequestLength + 1)
        #expect(throws: RemoteTaskValidationError.requestTooLong(maximum: RemoteTask.maximumRequestLength)) {
            try RemoteTask(request: GroceryRequest(text: overlongRequest))
        }
    }
}
