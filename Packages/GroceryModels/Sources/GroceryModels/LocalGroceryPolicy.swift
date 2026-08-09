import GroceryDomain

enum LocalGroceryIntent: String, Sendable {
    case productDiscovery = "product-discovery"
    case householdPlanning = "household-planning"
    case cartReview = "cart-review"
}

enum LocalGroceryToolID: String, Sendable {
    case catalogSearch = "search-catalog"
    case householdContext = "household-context"
}

enum LocalGroceryModelID: String, Sendable {
    case appleOnDeviceSystem = "apple-on-device-system"
    case deterministicTestAssistant = "deterministic-test-assistant"
}

struct LocalGroceryExecutionPlan: Sendable, Equatable {
    let intent: LocalGroceryIntent
    let profile: ModelProfileID
    let instructions: [String]
    let tools: [LocalGroceryToolID]

    var toolNames: [String] { tools.map(\.rawValue) }

    var activation: ModelProfileActivation { activation() }

    func activation(
        trigger: String? = nil,
        selectedModel: LocalGroceryModelID = .appleOnDeviceSystem,
        ownsFinalAnswer: Bool = true
    ) -> ModelProfileActivation {
        ModelProfileActivation(
            profile: profile,
            trigger: trigger ?? "application-state:\(intent.rawValue)",
            effectiveInstructions: instructions,
            tools: toolNames,
            selectedModel: selectedModel.rawValue,
            ownsFinalAnswer: ownsFinalAnswer
        )
    }
}

enum LocalGroceryPolicy {
    static func householdPlanningPlan() -> LocalGroceryExecutionPlan {
        LocalGroceryExecutionPlan(
            intent: .householdPlanning,
            profile: .localHouseholdPlanning,
            instructions: [
                "Use the selected Demo Household's restrictions, priorities, pantry, and purchase evidence.",
                "Use only bundled catalog evidence for product claims."
            ],
            tools: [.householdContext, .catalogSearch]
        )
    }

    static func cartRecommendationPlan() -> LocalGroceryExecutionPlan {
        LocalGroceryExecutionPlan(
            intent: .cartReview,
            profile: .localCartRecommendation,
            instructions: [
                "Recommend cart improvements using the retrieved Demo Household and bundled catalog evidence.",
                "Do not mutate the cart; any Cart Proposal requires explicit user approval."
            ],
            tools: [.catalogSearch]
        )
    }

    static func plan(for request: GroceryRequest) -> LocalGroceryExecutionPlan {
        let words = Set(
            request.text.lowercased().split { !$0.isLetter }.map(String.init)
        )
        if !words.isDisjoint(with: ["cart", "basket"]) {
            return LocalGroceryExecutionPlan(
                intent: .cartReview,
                profile: .localCartReview,
                instructions: [
                    "Call household-context before reviewing the selected Demo Household's cart.",
                    "Do not mutate the cart; any Cart Proposal requires explicit user approval."
                ],
                tools: [.householdContext]
            )
        }
        if !words.isDisjoint(with: [
            "household", "pantry", "meal", "meals", "plan", "planning", "purchase", "purchases"
        ]) {
            return householdPlanningPlan()
        }
        return LocalGroceryExecutionPlan(
            intent: .productDiscovery,
            profile: .localProductDiscovery,
            instructions: [
                "Use only bundled catalog evidence and say when no matching product is available."
            ],
            tools: [.catalogSearch]
        )
    }
}
