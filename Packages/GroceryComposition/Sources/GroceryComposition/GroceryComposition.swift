import GroceryData
import GroceryDomain
import GroceryModels

public enum GroceryAppComposition {
    public static func makeAppDependencies() -> AppDependencies {
        let catalog = DemoCatalog()
        let assistant = LocalGroceryAssistant(catalog: catalog)
        return AppDependencies(assistant: assistant)
    }
}
