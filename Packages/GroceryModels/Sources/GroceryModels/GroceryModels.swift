import GroceryDomain

public struct LocalGroceryAssistant: GroceryAssistant, Sendable {
    private let catalog: any ProductCatalog

    public init(catalog: any ProductCatalog) {
        self.catalog = catalog
    }

    public func answer(for request: GroceryRequest, household: DemoHousehold?) async -> ModelRun {
        let plan = LocalGroceryPolicy.plan(for: request)
        let matches = catalog.search(matching: request.text)
        var events: [ModelRunEvent] = []
        if plan.tools.contains(.householdContext) {
            events.append(ModelRunEvent(
                kind: .toolCall,
                label: LocalGroceryToolID.householdContext.rawValue,
                content: household?.id.rawValue ?? "none"
            ))
            events.append(ModelRunEvent(
                kind: .toolOutput,
                label: LocalGroceryToolID.householdContext.rawValue,
                content: LocalHouseholdEvidence.render(household)
            ))
        }
        if plan.tools.contains(.catalogSearch) {
            events.append(ModelRunEvent(
                kind: .toolCall,
                label: LocalGroceryToolID.catalogSearch.rawValue,
                content: request.text
            ))
            events.append(ModelRunEvent(
                kind: .toolOutput,
                label: LocalGroceryToolID.catalogSearch.rawValue,
                content: matches.map(\.name).joined(separator: ", ")
            ))
        }
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
                intentID: plan.intent.rawValue,
                tools: plan.toolNames,
                toolEvents: events,
                activeProfiles: [plan.profile],
                profileActivations: [plan.activation(
                    selectedModel: .deterministicTestAssistant,
                    ownsFinalAnswer: false
                )],
                finalAnswerProfile: nil
            )
        )
    }

}
