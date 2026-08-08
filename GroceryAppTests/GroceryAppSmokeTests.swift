import XCTest
@testable import GroceryApp

@MainActor
final class GroceryAppSmokeTests: XCTestCase {
    func testComposedShellRunsALocalRequest() async {
        let model = GroceryAppModel.makeDemo()

        await model.submit("lentils")

        XCTAssertEqual(model.modelRun?.answer.evidence, ["Green lentils"])
    }
}
