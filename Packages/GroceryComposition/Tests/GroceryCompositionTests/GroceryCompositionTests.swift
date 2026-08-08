import Testing
import GroceryDomain
@testable import GroceryComposition

struct GroceryCompositionTests {
    @Test func compositionBuildsAWorkingDomainGraph() async {
        let dependencies = GroceryAppComposition.makeAppDependencies()
        let run = await dependencies.assistant.answer(for: GroceryRequest(text: "lentils"))

        #expect(run.answer.evidence == ["Green lentils"])
    }
}
