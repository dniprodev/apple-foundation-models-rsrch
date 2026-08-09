import Foundation
import CryptoKit
import GRDB
import Testing
import GroceryDomain
@testable import GroceryData

struct GroceryDataTests {
    @Test func laterLaunchPreservesHouseholdStateInTheInstalledDatabase() async throws {
        let fixture = try ReferenceDatasetFixture()
        defer { fixture.remove() }
        let installer = ReferenceDatasetInstaller(
            applicationSupportDirectory: fixture.root.appendingPathComponent("Application Support")
        )
        let installedURL = try installer.install(
            database: fixture.databaseURL,
            manifest: fixture.manifestURL
        )
        let catalog = try GRDBProductCatalog(databaseURL: installedURL)
        let product = try #require(catalog.product(for: ProductID("3017620422003")))
        let store = try GRDBDemoHouseholdStore(
            databaseURL: installedURL,
            catalogProducts: [product],
            seed: 42
        )
        let original = try #require(await store.household(for: .budgetFamily))
        let changedCart = [CartItem(productID: product.id, quantity: 7)]
        #expect(await store.apply(CartProposal(
            householdID: .budgetFamily,
            originalCart: original.cart,
            proposedCart: changedCart,
            reason: "Persist across launch."
        )))

        _ = try installer.install(database: fixture.databaseURL, manifest: fixture.manifestURL)
        let reopened = try GRDBDemoHouseholdStore(
            databaseURL: installedURL,
            catalogProducts: [product],
            seed: 42
        )

        #expect(await reopened.household(for: .budgetFamily)?.cart == changedCart)
    }

    @Test func referenceDatasetInstallerRejectsAManifestProductCountMismatch() throws {
        let fixture = try ReferenceDatasetFixture(retainedProducts: 2)
        defer { fixture.remove() }
        let installer = ReferenceDatasetInstaller(
            applicationSupportDirectory: fixture.root.appendingPathComponent("Application Support")
        )

        #expect(throws: ReferenceDatasetError.productCountMismatch) {
            try installer.install(database: fixture.databaseURL, manifest: fixture.manifestURL)
        }
    }

    @Test func referenceDatasetInstallerRejectsAnUnpopulatedFullTextIndex() throws {
        let fixture = try ReferenceDatasetFixture(fullTextCode: nil)
        defer { fixture.remove() }
        let installer = ReferenceDatasetInstaller(
            applicationSupportDirectory: fixture.root.appendingPathComponent("Application Support")
        )

        #expect(throws: ReferenceDatasetError.invalidDatabase) {
            try installer.install(database: fixture.databaseURL, manifest: fixture.manifestURL)
        }
    }

    @Test func referenceDatasetInstallerRejectsStaleFullTextReferences() throws {
        let fixture = try ReferenceDatasetFixture(fullTextCode: "stale-product")
        defer { fixture.remove() }
        let installer = ReferenceDatasetInstaller(
            applicationSupportDirectory: fixture.root.appendingPathComponent("Application Support")
        )

        #expect(throws: ReferenceDatasetError.invalidDatabase) {
            try installer.install(database: fixture.databaseURL, manifest: fixture.manifestURL)
        }
    }

    @Test func localDataStorePersistsHouseholdsAndResetLeavesTheCatalogUnchanged() async throws {
        let fixture = try ReferenceDatasetFixture()
        defer { fixture.remove() }
        let catalog = try GRDBProductCatalog(databaseURL: fixture.databaseURL)
        let product = try #require(catalog.product(for: ProductID("3017620422003")))
        let store = try GRDBDemoHouseholdStore(
            databaseURL: fixture.databaseURL,
            catalogProducts: [product],
            seed: 42
        )
        let original = try #require(await store.household(for: .budgetFamily))
        let changedCart = [CartItem(productID: product.id, quantity: 7)]

        #expect(await store.apply(CartProposal(
            householdID: .budgetFamily,
            originalCart: original.cart,
            proposedCart: changedCart,
            reason: "Persist a cart change."
        )))
        let reopened = try GRDBDemoHouseholdStore(
            databaseURL: fixture.databaseURL,
            catalogProducts: [product],
            seed: 42
        )
        #expect(await reopened.household(for: .budgetFamily)?.cart == changedCart)

        await reopened.reset(.budgetFamily)
        let reset = try #require(await reopened.household(for: .budgetFamily))
        let referencedIDs = reset.purchaseHistory.map(\.productID)
            + reset.pantry.map(\.productID)
            + reset.cart.map(\.productID)

        #expect(reset == original)
        #expect(referencedIDs.allSatisfy { catalog.product(for: $0) != nil })
        #expect(catalog.search(matching: "Nutella").map(\.id) == [product.id])
    }

    @Test func grdbCatalogFindsAReferenceDatasetProductThroughIndexedSearch() throws {
        let fixture = try ReferenceDatasetFixture()
        defer { fixture.remove() }
        let catalog = try GRDBProductCatalog(databaseURL: fixture.databaseURL)

        let results = catalog.search(matching: "Find Nutella for breakfast")

        #expect(results.map(\.id) == [ProductID("3017620422003")])
        #expect(results.first?.name == "Nutella")
        #expect(results.first?.detail == "Ferrero · 400 g · EUR 3.65 per UNIT")
        #expect(catalog.product(for: ProductID("3017620422003")) == results.first)
    }

    @Test func firstLaunchInstallsTheValidatedReferenceDatasetAndLaterLaunchesReuseIt() throws {
        let fixture = try ReferenceDatasetFixture()
        defer { fixture.remove() }
        let installer = ReferenceDatasetInstaller(
            applicationSupportDirectory: fixture.root.appendingPathComponent("Application Support")
        )

        let firstURL = try installer.install(
            database: fixture.databaseURL,
            manifest: fixture.manifestURL
        )
        let preservedDate = Date(timeIntervalSince1970: 978_307_200)
        try FileManager.default.setAttributes(
            [.modificationDate: preservedDate],
            ofItemAtPath: firstURL.path
        )

        let secondURL = try installer.install(
            database: fixture.databaseURL,
            manifest: fixture.manifestURL
        )

        #expect(secondURL == firstURL)
        let installedDate = try #require(
            FileManager.default.attributesOfItem(atPath: secondURL.path)[.modificationDate] as? Date
        )
        #expect(installedDate == preservedDate)
    }

    @Test func referenceDatasetInstallerRejectsAnArtifactChecksumMismatch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GroceryDataTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("catalog.sqlite")
        let manifestURL = root.appendingPathComponent("catalog-manifest.json")
        try Data("not-the-published-artifact".utf8).write(to: databaseURL)
        try Data(
            """
            {
              "builder_version": "1",
              "selection": { "retained_products": 3000 },
              "artifact": { "sha256": "\(String(repeating: "0", count: 64))" }
            }
            """.utf8
        ).write(to: manifestURL)

        let installer = ReferenceDatasetInstaller(
            applicationSupportDirectory: root.appendingPathComponent("Application Support")
        )

        #expect(throws: ReferenceDatasetError.artifactChecksumMismatch) {
            try installer.install(database: databaseURL, manifest: manifestURL)
        }
        #expect(!FileManager.default.fileExists(
            atPath: installer.installedDatabaseURL.path
        ))
    }

    @Test func demoCatalogFindsProductsByNameOrDetail() {
        let catalog = DemoCatalog()

        #expect(catalog.search(matching: "lentil").map(\.name) == ["Green lentils"])
        #expect(catalog.search(matching: "weeknight").map(\.name) == ["Whole-wheat pasta"])
    }

    @Test func demoCatalogFindsEvidenceInsideNaturalLanguageRequests() {
        let catalog = DemoCatalog()

        #expect(catalog.search(matching: "What can I make with lentils?").map(\.name) == ["Green lentils"])
    }

    @Test func householdGenerationIsDeterministicAndUsesCatalogProducts() {
        let products = [
            CatalogProduct(id: ProductID("lentils"), name: "Green lentils", detail: "Pantry staple"),
            CatalogProduct(id: ProductID("pasta"), name: "Whole-wheat pasta", detail: "Weeknight base"),
            CatalogProduct(id: ProductID("tomatoes"), name: "Canned tomatoes", detail: "For sauces")
        ]
        let generator = DemoHouseholdGenerator(catalogProducts: products, seed: 42)

        let first = generator.generate()
        let second = generator.generate()
        let productIDs = Set(products.map(\.id))
        let referencedIDs = Set(first.flatMap { household in
            household.purchaseHistory.map(\.productID)
                + household.pantry.map(\.productID)
                + household.cart.map(\.productID)
        })

        #expect(first == second)
        #expect(first.map(\.id) == DemoHouseholdID.allCases)
        #expect(first.allSatisfy { !$0.purchaseHistory.isEmpty && !$0.pantry.isEmpty })
        #expect(referencedIDs.isSubset(of: productIDs))
    }

    @Test func generatedHouseholdsHaveTheThreeInitialFixtureProfiles() {
        let products = [CatalogProduct(id: ProductID("lentils"), name: "Green lentils", detail: "Pantry staple")]
        let households = DemoHouseholdGenerator(catalogProducts: products, seed: 42).generate()

        let budgetFamily = households[0]
        #expect(budgetFamily.id == .budgetFamily)
        #expect(budgetFamily.members.filter { $0.role == .adult }.count == 2)
        #expect(budgetFamily.members.filter { $0.role == .child }.count == 2)
        #expect(budgetFamily.weeklySpendingTargetCents == 8_500)
        #expect(budgetFamily.restrictions == [.peanutAllergy])

        let nutritionFocusedCouple = households[1]
        #expect(nutritionFocusedCouple.members.count == 2)
        #expect(nutritionFocusedCouple.restrictions == [.lactoseIntolerance])
        #expect(nutritionFocusedCouple.priorities == [.lowerSugar, .lowerSodium])

        let lowWasteSoloShopper = households[2]
        #expect(lowWasteSoloShopper.members.count == 1)
        #expect(lowWasteSoloShopper.restrictions == [.vegetarian])
        #expect(lowWasteSoloShopper.priorities == [.smallPortions, .usePantryFirst])
    }

    @Test func householdStoreResetRestoresGeneratedState() async {
        let products = [CatalogProduct(id: ProductID("lentils"), name: "Green lentils", detail: "Pantry staple")]
        let store = DemoHouseholdStore(catalogProducts: products, seed: 42)
        let original = await store.household(for: .budgetFamily)
        let originalCart = original?.cart ?? []
        let changedCart = [CartItem(productID: ProductID("lentils"), quantity: 7)]
        let proposal = CartProposal(
            householdID: .budgetFamily,
            originalCart: originalCart,
            proposedCart: changedCart,
            reason: "Test cart change."
        )

        #expect(await store.apply(proposal))
        await store.reset(.budgetFamily)

        #expect(await store.household(for: .budgetFamily) == original)
    }

    @Test func applyingAProposalRequiresAnUnchangedOriginalCart() async {
        let catalog = [CatalogProduct(name: "Green lentils", detail: "A pantry staple.")]
        let store = DemoHouseholdStore(catalogProducts: catalog)
        let originalCart = await store.household(for: .budgetFamily)?.cart ?? []
        let proposedCart = originalCart + [CartItem(productID: catalog[0].id, quantity: 1)]
        let proposal = CartProposal(
            householdID: .budgetFamily,
            originalCart: originalCart,
            proposedCart: proposedCart,
            reason: "Add green lentils."
        )

        #expect(await store.apply(proposal))
        #expect(await store.household(for: .budgetFamily)?.cart == proposedCart)
    }

    @Test func staleCartProposalDoesNotMutateTheHousehold() async {
        let catalog = [CatalogProduct(name: "Green lentils", detail: "A pantry staple.")]
        let store = DemoHouseholdStore(catalogProducts: catalog)
        let originalCart = await store.household(for: .budgetFamily)?.cart ?? []
        let proposal = CartProposal(
            householdID: .budgetFamily,
            originalCart: [],
            proposedCart: originalCart + [CartItem(productID: catalog[0].id, quantity: 1)],
            reason: "Add green lentils."
        )

        #expect(!(await store.apply(proposal)))
        #expect(await store.household(for: .budgetFamily)?.cart == originalCart)
    }

    @Test func keychainCredentialStorePersistsOnlyCredentialPresence() async throws {
        let store = KeychainClaudeCredentialStore(
            service: "GroceryDataTests",
            account: "claude-\(UUID().uuidString)"
        )

        #expect(await store.hasCredential() == false)
        try await store.save(apiKey: "test-key")
        #expect(await store.hasCredential())
        try await store.remove()
        #expect(await store.hasCredential() == false)
    }

    @Test func keychainCredentialStoreRejectsBlankCredentials() async {
        let store = KeychainClaudeCredentialStore(
            service: "GroceryDataTests",
            account: "blank-\(UUID().uuidString)"
        )

        await #expect(throws: ClaudeCredentialStoreError.invalidCredential) {
            try await store.save(apiKey: " \n\t")
        }
    }
}

private struct ReferenceDatasetFixture {
    let root: URL
    let databaseURL: URL
    let manifestURL: URL

    init(
        retainedProducts: Int = 1,
        fullTextCode: String? = "3017620422003"
    ) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReferenceDatasetFixture-\(UUID().uuidString)", isDirectory: true)
        databaseURL = root.appendingPathComponent("catalog.sqlite")
        manifestURL = root.appendingPathComponent("catalog-manifest.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let database = try DatabaseQueue(path: databaseURL.path)
        try database.write { db in
            try db.execute(sql: """
                CREATE TABLE products (
                    code TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    brand TEXT NOT NULL,
                    quantity TEXT NOT NULL,
                    primary_category TEXT NOT NULL,
                    ingredients TEXT NOT NULL,
                    sugars_100g REAL NOT NULL,
                    sodium_100g REAL NOT NULL,
                    median_price REAL NOT NULL,
                    price_basis TEXT NOT NULL
                ) WITHOUT ROWID;
                INSERT INTO products VALUES (
                    '3017620422003', 'Nutella', 'Ferrero', '400 g', 'breakfast',
                    'Sugar, palm oil, hazelnuts', 56.3, 0.043, 3.65, 'UNIT'
                );
                CREATE VIRTUAL TABLE product_fts USING fts5(
                    code UNINDEXED, name, brand, ingredients, category
                );
                """)
            if let fullTextCode {
                try db.execute(sql: """
                    INSERT INTO product_fts VALUES (
                        ?, 'Nutella', 'Ferrero',
                        'Sugar, palm oil, hazelnuts', 'breakfast'
                    )
                    """, arguments: [fullTextCode])
            }
        }

        let digest = SHA256.hash(data: try Data(contentsOf: databaseURL))
            .map { String(format: "%02x", $0) }
            .joined()
        try Data(
            """
            {
              "builder_version": "1",
              "selection": { "retained_products": \(retainedProducts) },
              "artifact": { "sha256": "\(digest)" }
            }
            """.utf8
        ).write(to: manifestURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
