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
}
