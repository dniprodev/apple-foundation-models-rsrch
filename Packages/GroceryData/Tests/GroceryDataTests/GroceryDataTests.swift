import Testing
import GroceryDomain
@testable import GroceryData

struct GroceryDataTests {
    @Test func demoCatalogFindsProductsByNameOrDetail() {
        let catalog = DemoCatalog()

        #expect(catalog.search(matching: "lentil").map(\.name) == ["Green lentils"])
        #expect(catalog.search(matching: "weeknight").map(\.name) == ["Whole-wheat pasta"])
    }
}
