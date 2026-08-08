import GroceryData
import GroceryDomain
import GroceryModels

public enum GroceryAppComposition {
    public static func makeAppDependencies(
        useOnDeviceModel: Bool = true,
        claudeCredentialStore: any ClaudeCredentialStore = KeychainClaudeCredentialStore(),
        claudeResponder: any ClaudeResponder = UnavailableClaudeResponder()
    ) -> AppDependencies {
        let catalog = DemoCatalog()
        let localAssistant: any GroceryAssistant = useOnDeviceModel
            ? OnDeviceGroceryAssistant(catalog: catalog)
            : LocalGroceryAssistant(catalog: catalog)
        let claudeProvider = ClaudeRemoteProvider(
            credentialStore: claudeCredentialStore,
            responder: claudeResponder
        )
        let hybridAssistant = HybridGroceryAssistant(provider: claudeProvider)
        let householdStore = DemoHouseholdStore(catalogProducts: catalog.products)
        return AppDependencies(
            assistant: localAssistant,
            catalog: catalog,
            householdStore: householdStore,
            hybridAssistant: hybridAssistant,
            claudeCredentialStore: claudeCredentialStore
        )
    }
}
