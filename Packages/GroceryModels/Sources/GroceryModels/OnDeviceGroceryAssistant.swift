import GroceryDomain

public struct OnDeviceGroceryAssistant: GroceryAssistant, Sendable {
    private let catalog: any ProductCatalog

    public init(catalog: any ProductCatalog) {
        self.catalog = catalog
    }

    public func answer(for request: GroceryRequest, household: DemoHousehold?) async -> ModelRun {
        await DynamicOnDeviceGroceryAssistant(catalog: catalog).answer(
            for: request,
            household: household
        )
    }
}
