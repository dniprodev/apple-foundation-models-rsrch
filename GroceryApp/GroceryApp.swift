import GroceryComposition
import SwiftUI

@main
struct GroceryApp: App {
    @StateObject private var model: ReferenceAppViewModel

    init() {
        _model = StateObject(
            wrappedValue: ReferenceAppViewModel(
                dependencies: GroceryAppComposition.makeAppDependencies()
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ReferenceAppView(model: model)
        }
    }
}
