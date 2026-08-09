import Foundation

public struct GroceryRequest: Sendable, Codable, Equatable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public enum RemoteTaskValidationError: Error, Sendable, Equatable {
    case emptyRequest
    case requestTooLong(maximum: Int)
}

/// A deliberately small, app-owned unit of work that may cross the remote
/// model boundary during a phone-a-friend run.
public struct RemoteTask: Sendable, Codable, Equatable {
    public static let maximumRequestLength = 160
    public static let instructionPrefix = "Use only public catalog evidence to help the parent answer: "

    public let requestText: String
    public let instructionText: String

    public init(request: GroceryRequest) throws {
        let normalizedRequest = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRequest.isEmpty else {
            throw RemoteTaskValidationError.emptyRequest
        }
        guard normalizedRequest.count <= Self.maximumRequestLength else {
            throw RemoteTaskValidationError.requestTooLong(maximum: Self.maximumRequestLength)
        }

        requestText = normalizedRequest
        instructionText = Self.instructionPrefix + normalizedRequest
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

public struct CartProposal: Sendable, Codable, Equatable, Identifiable {
    public let householdID: DemoHouseholdID
    public let originalCart: [CartItem]
    public let proposedCart: [CartItem]
    public let reason: String

    public var id: String {
        "\(householdID.rawValue):\(proposedCart.map { "\($0.productID.rawValue)=\($0.quantity)" }.joined(separator: ","))"
    }

    public init(
        householdID: DemoHouseholdID,
        originalCart: [CartItem],
        proposedCart: [CartItem],
        reason: String
    ) {
        precondition(!reason.isEmpty, "Cart proposals require a reason.")
        self.householdID = householdID
        self.originalCart = originalCart
        self.proposedCart = proposedCart
        self.reason = reason
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
    func apply(_ proposal: CartProposal) async -> Bool
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

public enum ModelStrategy: String, Sendable, Codable, Equatable {
    case localOnly = "local-only"
    case hybrid
}

public enum ModelProvider: String, Sendable, Codable, Equatable {
    case appleOnDevice = "apple-on-device"
    case claude
}

public enum RemoteProviderState: String, Sendable, Codable, Equatable {
    case ready
    case notConfigured = "not-configured"
    case unavailable
}

public enum OrchestrationPattern: String, Sendable, Codable, Equatable {
    case batonPass = "baton-pass"
    case phoneAFriend = "phone-a-friend"
}

public enum ModelProfileID: String, Sendable, Codable, Equatable {
    case localProductDiscovery = "local-product-discovery"
    case localHouseholdPlanning = "local-household-planning"
    case localCartReview = "local-cart-review"
    case localCartRecommendation = "local-cart-recommendation"
    case localGrocery = "local-grocery"
    case claudeGrocery = "claude-grocery"
    case claudeChildGrocery = "claude-child-grocery"
}

public struct ModelProfileActivation: Sendable, Codable, Equatable {
    public let profile: ModelProfileID
    public let trigger: String
    public let effectiveInstructions: [String]
    public let tools: [String]
    public let selectedModel: String
    public let ownsFinalAnswer: Bool

    public init(
        profile: ModelProfileID,
        trigger: String,
        effectiveInstructions: [String],
        tools: [String],
        selectedModel: String,
        ownsFinalAnswer: Bool
    ) {
        self.profile = profile
        self.trigger = trigger
        self.effectiveInstructions = effectiveInstructions
        self.tools = tools
        self.selectedModel = selectedModel
        self.ownsFinalAnswer = ownsFinalAnswer
    }
}

public struct ModelProfileTransition: Sendable, Codable, Equatable {
    public let from: ModelProfileID
    public let to: ModelProfileID

    public init(from: ModelProfileID, to: ModelProfileID) {
        self.from = from
        self.to = to
    }
}

public struct RemoteHistoryEntry: Sendable, Codable, Equatable {
    public enum Role: String, Sendable, Codable, Equatable {
        case toolCall = "tool-call"
        case toolOutput = "tool-output"
        case assistant
    }

    public let role: Role
    public let label: String
    public let content: String

    public init(role: Role, label: String, content: String) {
        self.role = role
        self.label = label
        self.content = content
    }
}

public enum RemoteSessionOwnership: String, Sendable, Codable, Equatable {
    case sharedParent = "shared-parent-session"
    case isolatedChild = "isolated-child-session"
}

public struct RemoteSession: Sendable, Codable, Equatable {
    public let id: String
    public let parentID: String?
    public let ownership: RemoteSessionOwnership

    public init(
        ownership: RemoteSessionOwnership,
        id: String = UUID().uuidString,
        parentID: String? = nil
    ) {
        precondition(!id.isEmpty, "Remote session IDs must not be empty.")
        if ownership == .isolatedChild {
            precondition(parentID != nil && parentID != id, "Isolated child sessions require a distinct parent session.")
        }
        self.id = id
        self.parentID = parentID
        self.ownership = ownership
    }
}

/// The exact semantic context the app intends to disclose to a remote model.
/// Rendering is deterministic so the trace can be compared with the provider
/// invocation captured by a test transport.
public struct RemoteContextView: Sendable, Codable, Equatable {
    public let pattern: OrchestrationPattern
    public let sessionOwnership: RemoteSessionOwnership
    public let instructions: String
    public let prompt: String
    public let sharedHistory: [RemoteHistoryEntry]
    public let toolDefinitions: [String]
    public let toolOutputs: [RemoteHistoryEntry]
    public let selectedOptions: [String]
    public let attachments: [String]
    public let remoteTask: RemoteTask?
    public let disclosureFacts: [String]
    public let privacyConcerns: [String]

    public init(
        pattern: OrchestrationPattern,
        sessionOwnership: RemoteSessionOwnership = .sharedParent,
        instructions: String,
        prompt: String,
        sharedHistory: [RemoteHistoryEntry],
        toolDefinitions: [String],
        toolOutputs: [RemoteHistoryEntry] = [],
        selectedOptions: [String] = [],
        attachments: [String] = [],
        remoteTask: RemoteTask? = nil,
        disclosureFacts: [String] = [],
        privacyConcerns: [String]
    ) {
        self.pattern = pattern
        self.sessionOwnership = sessionOwnership
        self.instructions = instructions
        self.prompt = prompt
        self.sharedHistory = sharedHistory
        self.toolDefinitions = toolDefinitions
        self.toolOutputs = toolOutputs
        self.selectedOptions = selectedOptions
        self.attachments = attachments
        self.remoteTask = remoteTask
        self.disclosureFacts = disclosureFacts
        self.privacyConcerns = privacyConcerns
    }

    public var rendered: String {
        var lines = [
            "Pattern: \(pattern.rawValue)",
            "Session ownership: \(sessionOwnership.rawValue)",
            "Instructions: \(instructions)",
            "Prompt: \(prompt)",
            "Shared history:"
        ]
        lines += sharedHistory.map { "- [\($0.role.rawValue)] \($0.label): \($0.content)" }
        lines.append("Tool definitions: \(toolDefinitions.joined(separator: ", "))")
        lines.append("Tool outputs:")
        lines += toolOutputs.map { "- \($0.label): \($0.content)" }
        lines.append("Remote task: \(remoteTask?.instructionText ?? "none")")
        lines.append("Selected options: \(selectedOptions.joined(separator: ", "))")
        lines.append("Attachments: \(attachments.isEmpty ? "none" : attachments.joined(separator: ", "))")
        lines.append("Disclosure facts:")
        lines += disclosureFacts.map { "- \($0)" }
        lines.append("Privacy concerns:")
        lines += privacyConcerns.map { "- \($0)" }
        return lines.joined(separator: "\n")
    }
}

public struct RemoteGroceryInvocation: Sendable, Codable, Equatable {
    public let contextView: RemoteContextView
    public let correlationID: String
    public let remoteContextID: String
    public let session: RemoteSession

    public var sessionID: String { session.id }
    public var parentSessionID: String? { session.parentID }

    public init(
        contextView: RemoteContextView,
        correlationID: String = UUID().uuidString,
        remoteContextID: String = UUID().uuidString,
        session: RemoteSession = RemoteSession(ownership: .sharedParent)
    ) {
        self.contextView = contextView
        self.correlationID = correlationID
        self.remoteContextID = remoteContextID
        self.session = session
    }
}

public struct RemoteProviderResponse: Sendable, Equatable {
    public let answer: GroceryAnswer
    public let events: [ModelRunEvent]
    public let tools: [String]

    public init(
        answer: GroceryAnswer,
        events: [ModelRunEvent] = [],
        tools: [String] = []
    ) {
        self.answer = answer
        self.events = events
        self.tools = tools
    }
}

public enum RemoteProviderFailure: Error, Sendable, Equatable {
    case incomplete(events: [ModelRunEvent])
    case cancelled(events: [ModelRunEvent])
    case failed
}

public protocol RemoteGroceryProvider: Sendable {
    var provider: ModelProvider { get }
    func availability() async -> RemoteProviderState
    func respond(
        to invocation: RemoteGroceryInvocation
    ) async throws -> RemoteProviderResponse
}

public protocol ClaudeCredentialStore: Sendable {
    func hasCredential() async -> Bool
    /// Reads the secret only for immediate provider authentication. Callers
    /// must never persist, display, or include this value in trace data.
    func credential() async -> String?
    func save(apiKey: String) async throws
    func remove() async throws
}

public enum ClaudeCredentialStoreError: Error, Sendable, Equatable {
    case invalidCredential
    case keychainFailure(status: Int32)
}

public enum ModelRunEventKind: String, Sendable, Codable, Equatable {
    case toolCall = "tool-call"
    case toolOutput = "tool-output"
    case modelOutput = "model-output"
    case finalAnswer = "final-answer"
    case error
}

public struct ModelRunEvent: Sendable, Codable, Equatable {
    public let kind: ModelRunEventKind
    public let label: String
    public let content: String

    public init(kind: ModelRunEventKind, label: String, content: String) {
        self.kind = kind
        self.label = label
        self.content = content
    }
}

public struct ModelTrace: Sendable, Codable, Equatable {
    public let strategy: ModelStrategy
    public let provider: ModelProvider
    public let householdID: DemoHouseholdID?
    public let intentID: String
    public let tools: [String]
    public let toolEvents: [ModelRunEvent]
    public let durationMilliseconds: Int?
    public let error: String?
    public let remoteContextView: String?
    public let correlationID: String?
    public let remoteContextID: String?
    public let remoteSessionID: String?
    public let parentRemoteSessionID: String?
    public let orchestrationPattern: OrchestrationPattern?
    public let activeProfiles: [ModelProfileID]
    public let profileTransitions: [ModelProfileTransition]
    public let profileActivations: [ModelProfileActivation]
    public let finalAnswerProfile: ModelProfileID?
    public let privacyConcerns: [String]

    public init(
        strategy: ModelStrategy,
        provider: ModelProvider,
        householdID: DemoHouseholdID?,
        intentID: String,
        tools: [String],
        toolEvents: [ModelRunEvent] = [],
        durationMilliseconds: Int? = nil,
        error: String? = nil,
        remoteContextView: String? = nil,
        correlationID: String? = nil,
        remoteContextID: String? = nil,
        remoteSessionID: String? = nil,
        parentRemoteSessionID: String? = nil,
        orchestrationPattern: OrchestrationPattern? = nil,
        activeProfiles: [ModelProfileID] = [],
        profileTransitions: [ModelProfileTransition] = [],
        profileActivations: [ModelProfileActivation] = [],
        finalAnswerProfile: ModelProfileID? = nil,
        privacyConcerns: [String] = []
    ) {
        self.strategy = strategy
        self.provider = provider
        self.householdID = householdID
        self.intentID = intentID
        self.tools = tools
        self.toolEvents = toolEvents.filter { $0.kind == .toolCall || $0.kind == .toolOutput }
        self.durationMilliseconds = durationMilliseconds
        self.error = error
        self.remoteContextView = remoteContextView
        self.correlationID = correlationID
        self.remoteContextID = remoteContextID
        self.remoteSessionID = remoteSessionID
        self.parentRemoteSessionID = parentRemoteSessionID
        self.orchestrationPattern = orchestrationPattern
        self.activeProfiles = activeProfiles
        self.profileTransitions = profileTransitions
        self.profileActivations = profileActivations
        self.finalAnswerProfile = finalAnswerProfile
        self.privacyConcerns = privacyConcerns
    }
}

public struct ModelRun: Sendable, Equatable {
    public let request: GroceryRequest
    public let answer: GroceryAnswer
    public let events: [ModelRunEvent]
    public let trace: ModelTrace

    public init(
        request: GroceryRequest,
        answer: GroceryAnswer,
        events: [ModelRunEvent] = [],
        trace: ModelTrace = ModelTrace(
            strategy: .localOnly,
            provider: .appleOnDevice,
            householdID: nil,
            intentID: "unknown",
            tools: []
        )
    ) {
        self.request = request
        self.answer = answer
        self.events = events
        self.trace = trace
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
    func product(for id: ProductID) -> CatalogProduct?
}

public protocol GroceryAssistant: Sendable {
    func answer(for request: GroceryRequest, household: DemoHousehold?) async -> ModelRun
}

public extension GroceryAssistant {
    func answer(for request: GroceryRequest) async -> ModelRun {
        await answer(for: request, household: nil)
    }
}

public struct AppDependencies: Sendable {
    public let assistant: any GroceryAssistant
    public let hybridAssistant: (any GroceryAssistant)?
    public let phoneAFriendAssistant: (any GroceryAssistant)?
    public let catalog: any ProductCatalog
    public let householdStore: any DemoHouseholdRepository
    public let claudeCredentialStore: (any ClaudeCredentialStore)?

    public init(
        assistant: any GroceryAssistant,
        catalog: any ProductCatalog,
        householdStore: any DemoHouseholdRepository,
        hybridAssistant: (any GroceryAssistant)? = nil,
        phoneAFriendAssistant: (any GroceryAssistant)? = nil,
        claudeCredentialStore: (any ClaudeCredentialStore)? = nil
    ) {
        self.assistant = assistant
        self.hybridAssistant = hybridAssistant
        self.phoneAFriendAssistant = phoneAFriendAssistant
        self.catalog = catalog
        self.householdStore = householdStore
        self.claudeCredentialStore = claudeCredentialStore
    }
}
