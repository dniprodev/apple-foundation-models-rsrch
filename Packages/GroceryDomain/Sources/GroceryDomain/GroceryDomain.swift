public struct GroceryRequest: Sendable, Equatable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct ProductID: Hashable, Sendable, Codable, Equatable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        precondition(!rawValue.isEmpty, "Product IDs must not be empty.")
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public enum DemoHouseholdID: String, CaseIterable, Codable, Sendable, Equatable {
    case budgetFamily = "budget-family"
    case nutritionFocusedCouple = "nutrition-focused-couple"
    case lowWasteSoloShopper = "low-waste-solo-shopper"
}

public enum HouseholdMemberRole: String, Codable, Sendable, Equatable {
    case adult
    case child
}

public struct HouseholdMember: Sendable, Codable, Equatable {
    public let name: String
    public let role: HouseholdMemberRole

    public init(name: String, role: HouseholdMemberRole) {
        self.name = name
        self.role = role
    }
}

public enum HouseholdRestriction: String, Codable, Sendable, Equatable {
    case peanutAllergy = "peanut-allergy"
    case lactoseIntolerance = "lactose-intolerance"
    case vegetarian
}

public enum HouseholdPriority: String, Codable, Sendable, Equatable {
    case budget
    case lowerSugar = "lower-sugar"
    case lowerSodium = "lower-sodium"
    case smallPortions = "small-portions"
    case usePantryFirst = "use-pantry-first"
}

public struct PurchaseRecord: Sendable, Codable, Equatable {
    public let productID: ProductID
    public let quantity: Int
    public let sequence: Int

    public init(productID: ProductID, quantity: Int, sequence: Int) {
        precondition(quantity > 0, "Purchase quantities must be positive.")
        precondition(sequence > 0, "Purchase sequence numbers must be positive.")
        self.productID = productID
        self.quantity = quantity
        self.sequence = sequence
    }
}

public struct PantryItem: Sendable, Codable, Equatable {
    public let productID: ProductID
    public let quantity: Int

    public init(productID: ProductID, quantity: Int) {
        precondition(quantity > 0, "Pantry quantities must be positive.")
        self.productID = productID
        self.quantity = quantity
    }
}

public struct CartItem: Sendable, Codable, Equatable {
    public let productID: ProductID
    public let quantity: Int

    public init(productID: ProductID, quantity: Int) {
        precondition(quantity > 0, "Cart quantities must be positive.")
        self.productID = productID
        self.quantity = quantity
    }
}

public struct DemoHousehold: Identifiable, Sendable, Codable, Equatable {
    public let id: DemoHouseholdID
    public let name: String
    public let members: [HouseholdMember]
    public let weeklySpendingTargetCents: Int?
    public let restrictions: [HouseholdRestriction]
    public let priorities: [HouseholdPriority]
    public let purchaseHistory: [PurchaseRecord]
    public let pantry: [PantryItem]
    public var cart: [CartItem]

    public init(
        id: DemoHouseholdID,
        name: String,
        members: [HouseholdMember],
        weeklySpendingTargetCents: Int?,
        restrictions: [HouseholdRestriction],
        priorities: [HouseholdPriority],
        purchaseHistory: [PurchaseRecord],
        pantry: [PantryItem],
        cart: [CartItem]
    ) {
        self.id = id
        self.name = name
        self.members = members
        self.weeklySpendingTargetCents = weeklySpendingTargetCents
        self.restrictions = restrictions
        self.priorities = priorities
        self.purchaseHistory = purchaseHistory
        self.pantry = pantry
        self.cart = cart
    }
}

public protocol DemoHouseholdRepository: Sendable {
    func households() async -> [DemoHousehold]
    func household(for id: DemoHouseholdID) async -> DemoHousehold?
    func replaceCart(for id: DemoHouseholdID, with cart: [CartItem]) async
    func reset(_ id: DemoHouseholdID) async
    func resetAll() async
}

public struct GroceryAnswer: Sendable, Equatable {
    public let text: String
    public let evidence: [String]

    public init(text: String, evidence: [String] = []) {
        self.text = text
        self.evidence = evidence
    }
}

public struct ModelRun: Sendable, Equatable {
    public let request: GroceryRequest
    public let answer: GroceryAnswer

    public init(request: GroceryRequest, answer: GroceryAnswer) {
        self.request = request
        self.answer = answer
    }
}

public struct CatalogProduct: Sendable, Equatable {
    public let id: ProductID
    public let name: String
    public let detail: String

    public init(id: ProductID, name: String, detail: String) {
        self.id = id
        self.name = name
        self.detail = detail
    }

    public init(name: String, detail: String) {
        let generatedID = name.lowercased().split(separator: " ").joined(separator: "-")
        self.init(id: ProductID(generatedID), name: name, detail: detail)
    }
}

public protocol ProductCatalog: Sendable {
    func search(matching text: String) -> [CatalogProduct]
}

public protocol GroceryAssistant: Sendable {
    func answer(for request: GroceryRequest) async -> ModelRun
}

public struct AppDependencies: Sendable {
    public let assistant: any GroceryAssistant
    public let householdStore: any DemoHouseholdRepository

    public init(assistant: any GroceryAssistant, householdStore: any DemoHouseholdRepository) {
        self.assistant = assistant
        self.householdStore = householdStore
    }
}
