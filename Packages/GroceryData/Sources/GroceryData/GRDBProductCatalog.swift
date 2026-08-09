import Foundation
import GRDB
import GroceryDomain

public struct GRDBProductCatalog: ProductCatalog, Sendable {
    private let database: DatabaseQueue
    private let currency: String

    public init(databaseURL: URL, currency: String = "EUR") throws {
        database = try DatabaseQueue(path: databaseURL.path)
        self.currency = currency
    }

    public func search(matching text: String) -> [CatalogProduct] {
        let terms = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
        guard !terms.isEmpty else { return [] }
        let match = terms.map { "\"\($0)\"*" }.joined(separator: " OR ")

        return (try? database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT p.code, p.name, p.brand, p.quantity, p.median_price, p.price_basis
                    FROM product_fts
                    JOIN products p ON p.code = product_fts.code
                    WHERE product_fts MATCH ?
                    ORDER BY bm25(product_fts), p.code
                    LIMIT 25
                    """,
                arguments: [match]
            ).map(makeProduct)
        }) ?? []
    }

    public func product(for id: ProductID) -> CatalogProduct? {
        try? database.read { db in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT code, name, brand, quantity, median_price, price_basis
                    FROM products
                    WHERE code = ?
                    """,
                arguments: [id.rawValue]
            ).map(makeProduct)
        }
    }

    public func householdSeedProducts(limit: Int = 32) throws -> [CatalogProduct] {
        precondition(limit > 0, "A household seed requires at least one product.")
        return try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT code, name, brand, quantity, median_price, price_basis
                    FROM (
                        SELECT code, name, brand, quantity, median_price, price_basis,
                               primary_category,
                               row_number() OVER (
                                   PARTITION BY primary_category
                                   ORDER BY price_observation_count DESC, code
                               ) AS category_rank
                        FROM products
                    )
                    ORDER BY category_rank, primary_category, code
                    LIMIT ?
                    """,
                arguments: [limit]
            ).map(makeProduct)
        }
    }

    public func allProductIDs() throws -> Set<ProductID> {
        try database.read { db in
            Set(try String.fetchAll(db, sql: "SELECT code FROM products").map(ProductID.init))
        }
    }

    private func makeProduct(row: Row) -> CatalogProduct {
        let brand: String = row["brand"]
        let quantity: String = row["quantity"]
        let price: Double = row["median_price"]
        let priceBasis: String = row["price_basis"]
        return CatalogProduct(
            id: ProductID(row["code"]),
            name: row["name"],
            detail: "\(brand) · \(quantity) · \(currency) \(String(format: "%.2f", price)) per \(priceBasis)"
        )
    }
}
