import GroceryComposition
import SwiftUI

@main
struct GroceryApp: App {
    @StateObject private var model: GroceryAppModel

    init() {
        _model = StateObject(
            wrappedValue: GroceryAppModel(
                dependencies: GroceryAppComposition.makeAppDependencies()
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
