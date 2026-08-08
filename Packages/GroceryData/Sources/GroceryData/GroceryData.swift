import Foundation
import GroceryDomain

public struct DemoCatalog: ProductCatalog, Sendable {
    public let products: [CatalogProduct]

    public init(products: [CatalogProduct] = DemoCatalog.defaultProducts) {
        self.products = products
    }

    public func search(matching text: String) -> [CatalogProduct] {
        let query = text.lowercased()
        let terms = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }

        guard !terms.isEmpty else { return [] }

        return products.filter {
            let searchableText = "\($0.name) \($0.detail)".lowercased()
            return terms.contains(where: searchableText.contains)
        }
    }

    public func product(for id: ProductID) -> CatalogProduct? {
        products.first { $0.id == id }
    }

    public static let defaultProducts = [
        CatalogProduct(id: ProductID("green-lentils"), name: "Green lentils", detail: "A pantry staple for soups and salads."),
        CatalogProduct(id: ProductID("whole-wheat-pasta"), name: "Whole-wheat pasta", detail: "A quick base for a weeknight meal."),
        CatalogProduct(id: ProductID("canned-tomatoes"), name: "Canned tomatoes", detail: "Useful for sauces, soups, and stews.")
    ]
}

public struct DemoHouseholdGenerator: Sendable {
    public static let defaultSeed: UInt64 = 0x4752_4f43_4552_59

    private let catalogProducts: [CatalogProduct]
    private let seed: UInt64

    public init(catalogProducts: [CatalogProduct], seed: UInt64 = Self.defaultSeed) {
        precondition(!catalogProducts.isEmpty, "Demo households require at least one catalog product.")
        self.catalogProducts = catalogProducts
        self.seed = seed
    }

    public func generate() -> [DemoHousehold] {
        DemoHouseholdID.allCases.map(generate(for:))
    }

    public func generate(for id: DemoHouseholdID) -> DemoHousehold {
        var random = StableNumberGenerator(seed: seed &+ stableHash(id.rawValue))
        let configuration = configuration(for: id)

        var purchaseHistory: [PurchaseRecord] = []
        for sequence in 1...configuration.historyCount {
            let product = catalogProducts[random.nextIndex(lessThan: catalogProducts.count)]
            purchaseHistory.append(
                PurchaseRecord(
                    productID: product.id,
                    quantity: random.nextIndex(lessThan: 3) + 1,
                    sequence: sequence
                )
            )
        }

        var pantry: [PantryItem] = []
        for _ in 0..<configuration.pantryCount {
            let product = catalogProducts[random.nextIndex(lessThan: catalogProducts.count)]
            pantry.append(PantryItem(productID: product.id, quantity: random.nextIndex(lessThan: 2) + 1))
        }

        let cartStartIndex = Int(stableHash(id.rawValue) % UInt64(catalogProducts.count))
        let cart = (0..<configuration.cartCount).map { offset in
            let product = catalogProducts[(cartStartIndex + offset) % catalogProducts.count]
            return CartItem(productID: product.id, quantity: 1)
        }

        return DemoHousehold(
            id: id,
            name: configuration.name,
            members: configuration.members,
            weeklySpendingTargetCents: configuration.weeklySpendingTargetCents,
            restrictions: configuration.restrictions,
            priorities: configuration.priorities,
            purchaseHistory: purchaseHistory,
            pantry: pantry,
            cart: cart
        )
    }

    private func configuration(for id: DemoHouseholdID) -> HouseholdConfiguration {
        switch id {
        case .budgetFamily:
            HouseholdConfiguration(
                name: "Budget Family",
                members: [
                    HouseholdMember(name: "Alex", role: .adult),
                    HouseholdMember(name: "Sam", role: .adult),
                    HouseholdMember(name: "Mia", role: .child),
                    HouseholdMember(name: "Leo", role: .child)
                ],
                weeklySpendingTargetCents: 8_500,
                restrictions: [.peanutAllergy],
                priorities: [.budget],
                historyCount: 8,
                pantryCount: 3,
                cartCount: 2
            )
        case .nutritionFocusedCouple:
            HouseholdConfiguration(
                name: "Nutrition-Focused Couple",
                members: [
                    HouseholdMember(name: "Jordan", role: .adult),
                    HouseholdMember(name: "Riley", role: .adult)
                ],
                weeklySpendingTargetCents: nil,
                restrictions: [.lactoseIntolerance],
                priorities: [.lowerSugar, .lowerSodium],
                historyCount: 6,
                pantryCount: 2,
                cartCount: 2
            )
        case .lowWasteSoloShopper:
            HouseholdConfiguration(
                name: "Low-Waste Solo Shopper",
                members: [HouseholdMember(name: "Casey", role: .adult)],
                weeklySpendingTargetCents: nil,
                restrictions: [.vegetarian],
                priorities: [.smallPortions, .usePantryFirst],
                historyCount: 4,
                pantryCount: 2,
                cartCount: 1
            )
        }
    }
}

public actor DemoHouseholdStore: DemoHouseholdRepository {
    public let catalogProductIDs: Set<ProductID>

    private let initialHouseholds: [DemoHouseholdID: DemoHousehold]
    private var currentHouseholds: [DemoHouseholdID: DemoHousehold]

    public init(catalogProducts: [CatalogProduct], seed: UInt64 = DemoHouseholdGenerator.defaultSeed) {
        let catalogProductIDs = Set(catalogProducts.map(\.id))
        precondition(catalogProductIDs.count == catalogProducts.count, "Catalog product IDs must be unique.")
        let generated = DemoHouseholdGenerator(catalogProducts: catalogProducts, seed: seed).generate()
        let initialHouseholds = Dictionary(uniqueKeysWithValues: generated.map { ($0.id, $0) })

        self.catalogProductIDs = catalogProductIDs
        self.initialHouseholds = initialHouseholds
        self.currentHouseholds = initialHouseholds
    }

    public func households() -> [DemoHousehold] {
        DemoHouseholdID.allCases.compactMap { currentHouseholds[$0] }
    }

    public func household(for id: DemoHouseholdID) -> DemoHousehold? {
        currentHouseholds[id]
    }

    public func apply(_ proposal: CartProposal) -> Bool {
        guard var household = currentHouseholds[proposal.householdID],
              household.cart == proposal.originalCart,
              proposal.proposedCart.allSatisfy({ catalogProductIDs.contains($0.productID) })
        else {
            return false
        }

        household.cart = proposal.proposedCart
        currentHouseholds[proposal.householdID] = household
        return true
    }

    public func reset(_ id: DemoHouseholdID) {
        currentHouseholds[id] = initialHouseholds[id]
    }

    public func resetAll() {
        currentHouseholds = initialHouseholds
    }
}

private struct HouseholdConfiguration: Sendable {
    let name: String
    let members: [HouseholdMember]
    let weeklySpendingTargetCents: Int?
    let restrictions: [HouseholdRestriction]
    let priorities: [HouseholdPriority]
    let historyCount: Int
    let pantryCount: Int
    let cartCount: Int
}

private struct StableNumberGenerator: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextIndex(lessThan upperBound: Int) -> Int {
        precondition(upperBound > 0)
        state &+= 0x9e37_79b9_7f4a_7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
        value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
        value ^= value >> 31
        return Int(value % UInt64(upperBound))
    }
}

private func stableHash(_ value: String) -> UInt64 {
    value.utf8.reduce(0xcbf2_9ce4_8422_2325) { hash, byte in
        (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
    }
}
