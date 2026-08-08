import Testing
import GroceryDomain
@testable import GroceryComposition

struct GroceryCompositionTests {
    @Test func compositionBuildsAWorkingDomainGraph() async {
        let dependencies = GroceryAppComposition.makeAppDependencies(useOnDeviceModel: false)
        let run = await dependencies.assistant.answer(for: GroceryRequest(text: "lentils"))

        #expect(run.answer.evidence == ["Green lentils"])
    }

    @Test func compositionProvidesAllInitialDemoHouseholds() async {
        let dependencies = GroceryAppComposition.makeAppDependencies(useOnDeviceModel: false)

        #expect(await dependencies.householdStore.households().map(\.id) == DemoHouseholdID.allCases)
    }
}
