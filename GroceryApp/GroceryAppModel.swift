import Combine
import GroceryComposition
import GroceryDomain

@MainActor
final class GroceryAppModel: ObservableObject {
    @Published private(set) var modelRun: ModelRun?
    @Published var requestText = ""

    private let assistant: any GroceryAssistant

    init(dependencies: AppDependencies) {
        assistant = dependencies.assistant
    }

    static func makeDemo() -> GroceryAppModel {
        GroceryAppModel(dependencies: GroceryAppComposition.makeAppDependencies())
    }

    func submit(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        requestText = trimmed
        modelRun = await assistant.answer(for: GroceryRequest(text: trimmed))
    }
}
