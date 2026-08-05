import Foundation
import GRDB

private let bold = "\u{001B}[1m"
private let dim = "\u{001B}[2m"
private let reset = "\u{001B}[0m"

struct Household: Identifiable {
    let id: String
    let name: String
    let description: String
}

struct CatalogItem {
    let code: String
    let name: String
    let brand: String
    let category: String
    let quantity: String
    let price: Double
    let sugars: Double?
    let sodium: Double?
    let vegetarianStatus: String
    let allergens: String
}

struct PurchaseSummary {
    let date: String
    let total: Double
    let items: String
}

struct StockItem {
    let name: String
    let quantity: Double
    let detail: String
}

/// The small interface under test. The TUI and model tools would call the same methods.
final class CatalogStore {
    private let queue: DatabaseQueue

    init(path: String) throws {
        var configuration = Configuration()
        configuration.readonly = true
        queue = try DatabaseQueue(path: path, configuration: configuration)
    }

    func households() throws -> [Household] {
        try queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT id,name,description FROM households
                ORDER BY CASE id
                    WHEN 'budget-family' THEN 1
                    WHEN 'nutrition-couple' THEN 2
                    ELSE 3
                END
                """
            ).map {
                Household(id: $0["id"], name: $0["name"], description: $0["description"])
            }
        }
    }

    func search(_ term: String, limit: Int = 8) throws -> [CatalogItem] {
        let tokens = term
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { "\($0)*" }
            .joined(separator: " ")
        guard !tokens.isEmpty else { return [] }
        return try queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT p.code,p.name,p.brand,p.primary_category,p.quantity,p.median_price,
                       p.sugars_100g,p.sodium_100g,p.vegetarian_status,
                       coalesce(group_concat(DISTINCT pa.allergen_tag),'') allergens
                FROM product_fts f
                JOIN products p ON p.code=f.code
                LEFT JOIN product_allergens pa ON pa.product_code=p.code AND pa.evidence_kind='contains'
                WHERE product_fts MATCH ? AND p.is_scale_copy=0
                GROUP BY p.code
                ORDER BY bm25(product_fts),p.name
                LIMIT ?
                """,
                arguments: [tokens, limit]
            ).map(Self.item)
        }
    }

    func product(code: String) throws -> CatalogItem? {
        try queue.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT p.code,p.name,p.brand,p.primary_category,p.quantity,p.median_price,
                       p.sugars_100g,p.sodium_100g,p.vegetarian_status,
                       coalesce(group_concat(DISTINCT pa.allergen_tag),'') allergens
                FROM products p
                LEFT JOIN product_allergens pa ON pa.product_code=p.code AND pa.evidence_kind='contains'
                WHERE p.code=?
                GROUP BY p.code
                """,
                arguments: [code]
            ).map(Self.item)
        }
    }

    func alternatives(for code: String, householdID: String, limit: Int = 8) throws -> [CatalogItem] {
        try queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                WITH target AS (SELECT primary_category FROM products WHERE code=?),
                vegetarian_gate AS (
                    SELECT EXISTS(
                        SELECT 1 FROM household_restrictions
                        WHERE household_id=? AND kind='diet' AND tag='vegetarian'
                    ) required
                ),
                ranked AS (
                    SELECT p.*,
                           CASE WHEN EXISTS(
                               SELECT 1 FROM household_preferences hp
                               WHERE hp.household_id=? AND hp.preference='lower_sugar'
                           ) THEN coalesce(p.sugars_100g,999) ELSE 0 END sugar_rank,
                           CASE WHEN EXISTS(
                               SELECT 1 FROM household_preferences hp
                               WHERE hp.household_id=? AND hp.preference='lower_sodium'
                           ) THEN coalesce(p.sodium_100g,999) ELSE 0 END sodium_rank
                    FROM products p,target,vegetarian_gate
                    WHERE p.primary_category=target.primary_category
                      AND p.code<>? AND p.is_scale_copy=0
                      AND (NOT vegetarian_gate.required OR p.vegetarian_status='yes')
                      AND NOT EXISTS(
                          SELECT 1
                          FROM product_allergens pa
                          JOIN household_restrictions hr
                            ON hr.household_id=? AND hr.kind='allergen' AND hr.tag=pa.allergen_tag
                          WHERE pa.product_code=p.code AND pa.evidence_kind='contains'
                      )
                )
                SELECT r.code,r.name,r.brand,r.primary_category,r.quantity,r.median_price,
                       r.sugars_100g,r.sodium_100g,r.vegetarian_status,
                       coalesce(group_concat(DISTINCT pa.allergen_tag),'') allergens
                FROM ranked r
                LEFT JOIN product_allergens pa ON pa.product_code=r.code AND pa.evidence_kind='contains'
                GROUP BY r.code
                ORDER BY r.sugar_rank+r.sodium_rank,r.median_price,r.code
                LIMIT ?
                """,
                arguments: [code, householdID, householdID, householdID, code, householdID, limit]
            ).map(Self.item)
        }
    }

    func recentPurchases(householdID: String, limit: Int = 6) throws -> [PurchaseSummary] {
        try queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT p.purchased_on,p.total,
                       group_concat(pr.name || ' ×' || pi.quantity, ' · ') items
                FROM purchases p
                JOIN purchase_items pi ON pi.purchase_id=p.id
                JOIN products pr ON pr.code=pi.product_code
                WHERE p.household_id=?
                GROUP BY p.id
                ORDER BY p.purchased_on DESC,p.id DESC
                LIMIT ?
                """,
                arguments: [householdID, limit]
            ).map {
                PurchaseSummary(date: $0["purchased_on"], total: $0["total"], items: $0["items"])
            }
        }
    }

    func pantry(householdID: String) throws -> [StockItem] {
        try queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT p.name,i.quantity,'best before ' || i.best_before detail
                FROM pantry_items i JOIN products p ON p.code=i.product_code
                WHERE i.household_id=? ORDER BY i.best_before,p.name
                """,
                arguments: [householdID]
            ).map { StockItem(name: $0["name"], quantity: $0["quantity"], detail: $0["detail"]) }
        }
    }

    func cart(householdID: String) throws -> [StockItem] {
        try queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT p.name,i.quantity,printf('€%.2f each',p.median_price) detail
                FROM cart_items i JOIN products p ON p.code=i.product_code
                WHERE i.household_id=? ORDER BY p.name
                """,
                arguments: [householdID]
            ).map { StockItem(name: $0["name"], quantity: $0["quantity"], detail: $0["detail"] as String) }
        }
    }

    func scalar(_ sql: String, arguments: StatementArguments = []) throws -> Int {
        try queue.read { db in try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0 }
    }

    func benchmark(_ sql: String, arguments: StatementArguments, iterations: Int = 300) throws -> (Double, Double) {
        var durations: [Double] = []
        durations.reserveCapacity(iterations)
        try queue.read { db in
            for _ in 0..<iterations {
                let start = ContinuousClock.now
                _ = try Row.fetchAll(db, sql: sql, arguments: arguments)
                durations.append(Double(start.duration(to: .now).components.attoseconds) / 1_000_000_000_000_000)
            }
        }
        durations.sort()
        return (durations[durations.count / 2], durations[Int(Double(durations.count - 1) * 0.95)])
    }

    private static func item(_ row: Row) -> CatalogItem {
        CatalogItem(
            code: row["code"], name: row["name"], brand: row["brand"],
            category: row["primary_category"], quantity: row["quantity"],
            price: row["median_price"], sugars: row["sugars_100g"],
            sodium: row["sodium_100g"], vegetarianStatus: row["vegetarian_status"],
            allergens: row["allergens"]
        )
    }
}

func format(_ item: CatalogItem) -> String {
    let sugar = item.sugars.map { String(format: "%.1fg sugar", $0) } ?? "sugar unknown"
    let sodium = item.sodium.map { String(format: "%.3fg sodium", $0) } ?? "sodium unknown"
    let allergens = item.allergens.isEmpty ? "allergens unknown/none recorded" : item.allergens
    return "\(item.name) — €\(String(format: "%.2f", item.price)), \(sugar), \(sodium), vegetarian \(item.vegetarianStatus), \(allergens) \(dim)[\(item.code)]\(reset)"
}

func benchmarkReport(root: URL) throws -> [String] {
    var lines = ["Scale-only SQLite + FTS5 measurements (300 warm queries each):"]
    for size in [1_000, 3_000, 10_000] {
        let url = root.appending(path: "Generated/benchmark-\(size).sqlite")
        let store = try CatalogStore(path: url.path)
        let fts = try store.benchmark(
            """
            SELECT p.code,p.name FROM product_fts f JOIN products p ON p.code=f.code
            WHERE product_fts MATCH 'chocolat*' ORDER BY bm25(product_fts) LIMIT 10
            """,
            arguments: []
        )
        let indexed = try store.benchmark(
            "SELECT code,name FROM products WHERE primary_category=? ORDER BY median_price,code LIMIT 10",
            arguments: ["breakfast"]
        )
        let bytes = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        lines.append(
            String(format: "%5d rows  %5.1f MB  FTS p50/p95 %.3f/%.3f ms  indexed %.3f/%.3f ms",
                   size, Double(bytes) / 1_048_576, fts.0, fts.1, indexed.0, indexed.1)
        )
    }
    return lines
}

func report(root: URL) throws {
    let store = try CatalogStore(path: root.appending(path: "Generated/catalog.sqlite").path)
    let productCount = try store.scalar("SELECT count(*) FROM products")
    let priceCount = try store.scalar("SELECT count(*) FROM price_observations")
    let purchaseCount = try store.scalar("SELECT count(*) FROM purchases")
    print("Catalog calibration report")
    print("Real quality-gated products: \(productCount); price observations: \(priceCount); generated purchases: \(purchaseCount)")
    for household in try store.households() {
        print("\n\(household.name) — \(household.description)")
        for purchase in try store.recentPurchases(householdID: household.id, limit: 3) {
            print("  \(purchase.date)  €\(String(format: "%.2f", purchase.total))  \(purchase.items)")
        }
        print("  pantry: \(try store.pantry(householdID: household.id).count) items; cart: \(try store.cart(householdID: household.id).count) items")
    }
    print("")
    for line in try benchmarkReport(root: root) { print(line) }

    let privateHistory = try store.benchmark(
        "SELECT p.id FROM purchases p WHERE p.household_id=? ORDER BY p.purchased_on DESC LIMIT 12",
        arguments: ["budget-family"]
    )
    let privateAlternatives = try store.benchmark(
        """
        SELECT p.code FROM products p
        WHERE p.primary_category='breakfast'
          AND NOT EXISTS (
            SELECT 1 FROM product_allergens pa
            WHERE pa.product_code=p.code AND pa.allergen_tag='en:peanuts' AND pa.evidence_kind='contains'
          )
        ORDER BY p.median_price LIMIT 10
        """,
        arguments: []
    )
    print(String(format: "Base private-history p50/p95 %.3f/%.3f ms; restriction-aware alternatives %.3f/%.3f ms",
                 privateHistory.0, privateHistory.1, privateAlternatives.0, privateAlternatives.1))
}

func interactive(root: URL) throws {
    let store = try CatalogStore(path: root.appending(path: "Generated/catalog.sqlite").path)
    let households = try store.households()
    var householdIndex = 0
    var title = "Latest generated purchase history"
    var lines = try store.recentPurchases(householdID: households[0].id).map {
        "\($0.date)  €\(String(format: "%.2f", $0.total))  \($0.items)"
    }
    var selectedCode: String?

    while true {
        print("\u{001B}[2J\u{001B}[H", terminator: "")
        let household = households[householdIndex]
        print("\(bold)PROTOTYPE — Catalog and Demo Household calibration\(reset)")
        print("\(bold)Demo Household\(reset): \(household.name)")
        print("\(dim)\(household.description)\(reset)\n")
        print("\(bold)\(title)\(reset)")
        for line in lines.prefix(12) { print("  \(line)") }
        print("\n\(bold)[h]\(reset) household  \(bold)[s]\(reset) search  \(bold)[d]\(reset) detail  \(bold)[a]\(reset) alternatives  \(bold)[r]\(reset) history  \(bold)[p]\(reset) pantry  \(bold)[c]\(reset) cart  \(bold)[b]\(reset) benchmarks  \(bold)[q]\(reset) quit")
        print("\(dim)command>\(reset) ", terminator: "")
        guard let command = readLine()?.lowercased() else { return }
        switch command {
        case "q": return
        case "h":
            householdIndex = (householdIndex + 1) % households.count
            title = "Latest generated purchase history"
            lines = try store.recentPurchases(householdID: households[householdIndex].id).map {
                "\($0.date)  €\(String(format: "%.2f", $0.total))  \($0.items)"
            }
        case "s":
            print("search> ", terminator: "")
            let term = readLine() ?? ""
            let results = try store.search(term)
            selectedCode = results.first?.code
            title = "Public catalog search: \(term)"
            lines = results.map(format)
        case "d":
            print("barcode [\(selectedCode ?? "none")]> ", terminator: "")
            let entered = readLine() ?? ""
            let code = entered.isEmpty ? selectedCode : entered
            title = "Public product detail"
            lines = try code.flatMap { try store.product(code: $0) }.map { [format($0)] } ?? ["No selected product"]
        case "a":
            print("barcode [\(selectedCode ?? "none")]> ", terminator: "")
            let entered = readLine() ?? ""
            let code = entered.isEmpty ? selectedCode : entered
            title = "Restriction-aware alternatives for \(households[householdIndex].name)"
            lines = try code.map { try store.alternatives(for: $0, householdID: households[householdIndex].id).map(format) } ?? ["Search or enter a barcode first"]
        case "r":
            title = "Private recent-purchase query"
            lines = try store.recentPurchases(householdID: households[householdIndex].id).map {
                "\($0.date)  €\(String(format: "%.2f", $0.total))  \($0.items)"
            }
        case "p":
            title = "Private pantry query"
            lines = try store.pantry(householdID: households[householdIndex].id).map { "\($0.name) ×\($0.quantity) — \($0.detail)" }
        case "c":
            title = "Private cart query"
            lines = try store.cart(householdID: households[householdIndex].id).map { "\($0.name) ×\(Int($0.quantity)) — \($0.detail)" }
        case "b":
            title = "Measured scale behavior"
            lines = try benchmarkReport(root: root)
        default:
            title = "Unknown command"
            lines = ["Use one of the keys shown below."]
        }
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
do {
    if CommandLine.arguments.contains("--report") {
        try report(root: root)
    } else {
        try interactive(root: root)
    }
} catch {
    FileHandle.standardError.write(Data("Catalog probe failed: \(error)\n".utf8))
    exit(1)
}
