import GroceryData
import GroceryDomain
import GroceryModels

public enum GroceryAppComposition {
    public static func makeAppDependencies(useOnDeviceModel: Bool = true) -> AppDependencies {
        let catalog = DemoCatalog()
        let assistant: any GroceryAssistant = useOnDeviceModel
            ? OnDeviceGroceryAssistant(catalog: catalog)
            : LocalGroceryAssistant(catalog: catalog)
        let householdStore = DemoHouseholdStore(catalogProducts: catalog.products)
        return AppDependencies(assistant: assistant, catalog: catalog, householdStore: householdStore)
    }
}
