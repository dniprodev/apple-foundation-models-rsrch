import GroceryComposition
import GroceryDomain
import SwiftUI

@main
struct GroceryApp: App {
    private let startup: Startup

    init() {
        do {
            startup = .ready(try GroceryAppComposition.makeAppDependencies())
        } catch {
            startup = .failed(error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            switch startup {
            case let .ready(dependencies):
                GroceryAppRootView(dependencies: dependencies)
            case let .failed(message):
                ContentUnavailableView(
                    "Reference Dataset Unavailable",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(message)
                )
            }
        }
    }

    private enum Startup {
        case ready(AppDependencies)
        case failed(String)
    }
}

private struct GroceryAppRootView: View {
    @StateObject private var model: ReferenceAppViewModel

    init(dependencies: AppDependencies) {
        _model = StateObject(
            wrappedValue: ReferenceAppViewModel(dependencies: dependencies)
        )
    }

    var body: some View {
        ReferenceAppView(model: model)
    }
}
