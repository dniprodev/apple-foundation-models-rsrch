import Foundation
import GroceryData
import GroceryDomain
import GroceryModels

public enum GroceryAppComposition {
    public static func makeAppDependencies(
        useOnDeviceModel: Bool = true,
        claudeCredentialStore: any ClaudeCredentialStore = KeychainClaudeCredentialStore(),
        claudeResponder: any ClaudeResponder = UnavailableClaudeResponder(),
        referenceDataset: ReferenceDatasetResources? = nil,
        applicationSupportDirectory: URL? = nil
    ) throws -> AppDependencies {
        let resources: ReferenceDatasetResources
        if let referenceDataset {
            resources = referenceDataset
        } else {
            resources = try BundledReferenceDataset.resources()
        }
        let supportDirectory = applicationSupportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let databaseURL = try ReferenceDatasetInstaller(
            applicationSupportDirectory: supportDirectory
        ).install(database: resources.databaseURL, manifest: resources.manifestURL)
        let catalog = try GRDBProductCatalog(databaseURL: databaseURL)
        let householdStore = try GRDBDemoHouseholdStore(
            databaseURL: databaseURL,
            catalogProducts: catalog.householdSeedProducts()
        )
        return makeDependencies(
            catalog: catalog,
            householdStore: householdStore,
            useOnDeviceModel: useOnDeviceModel,
            claudeCredentialStore: claudeCredentialStore,
            claudeResponder: claudeResponder
        )
    }

    public static func makeDemoDependencies(
        useOnDeviceModel: Bool = true,
        claudeCredentialStore: any ClaudeCredentialStore = KeychainClaudeCredentialStore(),
        claudeResponder: any ClaudeResponder = UnavailableClaudeResponder()
    ) -> AppDependencies {
        let catalog = DemoCatalog()
        let householdStore = DemoHouseholdStore(catalogProducts: catalog.products)
        return makeDependencies(
            catalog: catalog,
            householdStore: householdStore,
            useOnDeviceModel: useOnDeviceModel,
            claudeCredentialStore: claudeCredentialStore,
            claudeResponder: claudeResponder
        )
    }

    private static func makeDependencies(
        catalog: any ProductCatalog,
        householdStore: any DemoHouseholdRepository,
        useOnDeviceModel: Bool,
        claudeCredentialStore: any ClaudeCredentialStore,
        claudeResponder: any ClaudeResponder
    ) -> AppDependencies {
        let localAssistant: any GroceryAssistant = useOnDeviceModel
            ? OnDeviceGroceryAssistant(catalog: catalog)
            : LocalGroceryAssistant(catalog: catalog)
        let claudeProvider = ClaudeRemoteProvider(
            credentialStore: claudeCredentialStore,
            responder: claudeResponder
        )
        let hybridAssistant = HybridGroceryAssistant(
            localAssistant: localAssistant,
            provider: claudeProvider
        )
        let phoneAFriendAssistant = HybridGroceryAssistant(
            localAssistant: localAssistant,
            provider: claudeProvider,
            pattern: .phoneAFriend
        )
        return AppDependencies(
            assistant: localAssistant,
            catalog: catalog,
            householdStore: householdStore,
            hybridAssistant: hybridAssistant,
            phoneAFriendAssistant: phoneAFriendAssistant,
            claudeCredentialStore: claudeCredentialStore
        )
    }
}
