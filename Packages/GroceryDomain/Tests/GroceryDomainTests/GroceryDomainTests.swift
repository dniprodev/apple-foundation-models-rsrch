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
}
