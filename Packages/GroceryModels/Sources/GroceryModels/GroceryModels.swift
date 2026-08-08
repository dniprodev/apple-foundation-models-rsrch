import GroceryDomain

public struct LocalGroceryAssistant: GroceryAssistant, Sendable {
    private let catalog: any ProductCatalog

    public init(catalog: any ProductCatalog) {
        self.catalog = catalog
    }

    public func answer(for request: GroceryRequest, household: DemoHousehold?) async -> ModelRun {
        let matches = catalog.search(matching: request.text)
        let events = [
            ModelRunEvent(kind: .toolCall, label: "search-catalog", content: request.text),
            ModelRunEvent(
                kind: .toolOutput,
                label: "search-catalog",
                content: matches.map(\.name).joined(separator: ", ")
            )
        ]
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
        return ModelRun(
            request: request,
            answer: answer,
            events: events + [ModelRunEvent(kind: .finalAnswer, label: "answer", content: answer.text)],
            trace: ModelTrace(
                strategy: .localOnly,
                provider: .appleOnDevice,
                householdID: household?.id,
                intentID: "catalog-and-household",
                tools: ["search-catalog", "household-context"],
                toolEvents: events
            )
        )
    }
}
