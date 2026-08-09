import Foundation
import GRDB
import GroceryDomain

public actor GRDBDemoHouseholdStore: DemoHouseholdRepository {
    private let database: DatabaseQueue
    private let catalogProductIDs: Set<ProductID>
    private let initialHouseholds: [DemoHouseholdID: DemoHousehold]

    public init(
        databaseURL: URL,
        catalogProducts: [CatalogProduct],
        catalogProductIDs: Set<ProductID>? = nil,
        seed: UInt64 = DemoHouseholdGenerator.defaultSeed
    ) throws {
        let productIDs = Set(catalogProducts.map(\.id))
        precondition(productIDs.count == catalogProducts.count, "Catalog product IDs must be unique.")
        let generated = DemoHouseholdGenerator(
            catalogProducts: catalogProducts,
            seed: seed
        ).generate()
        let initial = Dictionary(uniqueKeysWithValues: generated.map { ($0.id, $0) })
        let database = try DatabaseQueue(path: databaseURL.path)

        try database.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS demo_households (
                    id TEXT PRIMARY KEY,
                    state_json BLOB NOT NULL
                ) WITHOUT ROWID
                """)
            let existingCount = try Int.fetchOne(db, sql: "SELECT count(*) FROM demo_households") ?? 0
            if existingCount == 0 {
                for household in generated {
                    try db.execute(
                        sql: "INSERT INTO demo_households (id, state_json) VALUES (?, ?)",
                        arguments: [household.id.rawValue, try JSONEncoder().encode(household)]
                    )
                }
            }
        }

        self.database = database
        self.catalogProductIDs = catalogProductIDs ?? productIDs
        initialHouseholds = initial
    }

    public func households() -> [DemoHousehold] {
        DemoHouseholdID.allCases.compactMap(load)
    }

    public func household(for id: DemoHouseholdID) -> DemoHousehold? {
        load(id)
    }

    public func apply(_ proposal: CartProposal) -> Bool {
        guard var household = load(proposal.householdID),
              household.cart == proposal.originalCart,
              proposal.proposedCart.allSatisfy({ catalogProductIDs.contains($0.productID) })
        else {
            return false
        }
        household.cart = proposal.proposedCart
        return save(household)
    }

    public func reset(_ id: DemoHouseholdID) {
        guard let household = initialHouseholds[id] else { return }
        _ = save(household)
    }

    public func resetAll() {
        for id in DemoHouseholdID.allCases {
            reset(id)
        }
    }

    private func load(_ id: DemoHouseholdID) -> DemoHousehold? {
        try? database.read { db in
            guard let data = try Data.fetchOne(
                db,
                sql: "SELECT state_json FROM demo_households WHERE id = ?",
                arguments: [id.rawValue]
            ) else {
                return nil
            }
            return try JSONDecoder().decode(DemoHousehold.self, from: data)
        }
    }

    private func save(_ household: DemoHousehold) -> Bool {
        do {
            let data = try JSONEncoder().encode(household)
            try database.write { db in
                try db.execute(
                    sql: "UPDATE demo_households SET state_json = ? WHERE id = ?",
                    arguments: [data, household.id.rawValue]
                )
            }
            return true
        } catch {
            return false
        }
    }
}
