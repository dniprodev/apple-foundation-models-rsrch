import GroceryDomain

public struct LocalGroceryAssistant: GroceryAssistant, Sendable {
    private let catalog: any ProductCatalog

    public init(catalog: any ProductCatalog) {
        self.catalog = catalog
    }

    public func answer(for request: GroceryRequest) async -> ModelRun {
        let matches = catalog.search(matching: request.text)
        let answer: GroceryAnswer
        if matches.isEmpty {
            answer = GroceryAnswer(
                text: "I could not find a matching product in the bundled catalog.",
                evidence: []
            )
        } else {
            answer = GroceryAnswer(
                text: "I found \(matches[0].name): \(matches[0].detail)",
                evidence: matches.map(\.name)
            )
        }
        return ModelRun(request: request, answer: answer)
    }
}
