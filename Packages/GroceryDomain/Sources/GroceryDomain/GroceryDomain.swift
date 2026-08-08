public struct GroceryRequest: Sendable, Equatable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
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
    public let name: String
    public let detail: String

    public init(name: String, detail: String) {
        self.name = name
        self.detail = detail
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

    public init(assistant: any GroceryAssistant) {
        self.assistant = assistant
    }
}
