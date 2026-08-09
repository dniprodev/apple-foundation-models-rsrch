import GroceryDomain

enum LocalHouseholdEvidence {
    static func render(_ household: DemoHousehold?) -> String {
        guard let household else { return "No Demo Household is selected." }
        let restrictions = household.restrictions.map(\.rawValue).joined(separator: ", ")
        let priorities = household.priorities.map(\.rawValue).joined(separator: ", ")
        let pantry = household.pantry.map { "\($0.productID.rawValue) ×\($0.quantity)" }
            .joined(separator: ", ")
        let cart = household.cart.map { "\($0.productID.rawValue) ×\($0.quantity)" }
            .joined(separator: ", ")
        return """
        Household: \(household.name)
        Restrictions: \(restrictions.isEmpty ? "none" : restrictions)
        Priorities: \(priorities.isEmpty ? "none" : priorities)
        Pantry: \(pantry.isEmpty ? "empty" : pantry)
        Cart: \(cart.isEmpty ? "empty" : cart)
        """
    }
}
