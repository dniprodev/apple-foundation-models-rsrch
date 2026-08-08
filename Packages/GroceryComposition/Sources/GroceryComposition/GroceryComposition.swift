import GroceryData
import GroceryDomain
import GroceryModels

public enum GroceryAppComposition {
    public static func makeAppDependencies() -> AppDependencies {
        let catalog = DemoCatalog()
        let assistant = LocalGroceryAssistant(catalog: catalog)
        let householdStore = DemoHouseholdStore(catalogProducts: catalog.products)
        return AppDependencies(assistant: assistant, catalog: catalog, householdStore: householdStore)
    }
}
