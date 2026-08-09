# Swift dependency-injection options for the Reference App

Research snapshot: 2026-08-06. Primary sources only.

## Recommendation

Use **manual constructor injection**, assembled in `GroceryComposition`. Do not add a DI library for this app.

The dependency direction should be:

```text
app target ────────────────> GroceryDomain
    └──> GroceryComposition ──> GroceryData ────> GroceryDomain
                           └──> GroceryModels ──> GroceryDomain
```

- `GroceryDomain`: domain models, repository and orchestration protocols, and use cases.
- `GroceryData`: concrete persistence repositories; depends on `GroceryDomain`.
- `GroceryModels`: concrete Foundation Models orchestration and tool adapters; depends on `GroceryDomain`.
- `GroceryComposition`: the only module that imports all three and constructs the live object graph. It exports a small domain-typed `AppDependencies`/root builder.
- App target: SwiftUI views, view models, navigation, and the call to the composition root. View and view-model source files import only `GroceryDomain`; the app entry point also imports `GroceryComposition`.

No DI technique can make the executable instantiate `GroceryData` and `GroceryModels` without some compiled code depending on those concrete modules. A container changes *how* the graph is assembled, not Swift's module dependency graph. Moving that knowledge to `GroceryComposition` is the useful boundary.

Manual injection fits this reference app because its graph is small, mostly static, and intentionally teaches Clean Architecture. Swift guarantees that stored properties are initialized before an instance becomes usable, so required constructor dependencies cannot be silently absent; tests and previews pass fakes through the same initializers. [Swift initialization](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/initialization/)

If the graph later becomes large enough that handwritten wiring is genuinely painful, re-evaluate **Factory** first. It is the best current library fit for SwiftUI and a composition-root style, but use its container only inside `GroceryComposition` and continue passing dependencies explicitly into view models and use cases. Factory itself demonstrates this composition-root pattern. [Factory resolution patterns](https://github.com/hmlongco/Factory#other-factory-resolution-methods)

## Dependency injection versus service location

The distinction matters more than the choice of library:

- **Dependency injection:** an object declares what it needs in its initializer; an outside composition root supplies those values. The dependency is visible in the type's construction API.
- **Service location:** an object reaches into an ambient/global/container value (`Container.shared`, `resolve`, `@Dependency`) to fetch what it needs. The construction API no longer shows the full dependency set.

Factory and Point-Free Dependencies support useful scoped override systems, but their common property-wrapper forms are service-location-style access: Factory's `@Injected` resolves through a key path when an object is created, while Point-Free's `@Dependency` reads a globally available, task-local `DependencyValues`. [Factory resolution](https://github.com/hmlongco/Factory#resolution) · [Point-Free `DependencyValues`](https://pointfreeco.github.io/swift-dependencies/main/documentation/dependencies/dependencyvalues/)

That does not make those libraries bad. It means using them throughout `GroceryDomain` would trade explicit Clean Architecture boundaries for ambient convenience. For this app, keep all lookup at the composition edge and inject normal Swift values thereafter.

## Comparison

| Option | Graph safety | Swift 6 concurrency | SwiftUI and tests | Generation / runtime machinery | Fit here |
| --- | --- | --- | --- | --- | --- |
| Manual constructor injection | Strong and local: missing/wrong constructor arguments fail to compile. Cycles are visible in wiring code. | No container state or property-wrapper isolation problem. Dependencies still need honest `Sendable`/actor annotations. | Plain initializers work in app, tests, and previews; SwiftUI can own an injected observable model as state. [Apple model-data guidance](https://developer.apple.com/documentation/SwiftUI/Managing-model-data-in-your-app) | None. | **Best.** Smallest operational and conceptual surface. |
| Factory 3.3.2 | Key-path factories are statically typed; missing factory members or wrong return types fail to compile. It is not whole-graph code generation. [Factory overview](https://github.com/hmlongco/Factory#factory-version-332) | Factory 3.x documents Xcode 26/27 strict-concurrency support and actor-isolated factories, but also documents a Swift 6.2 limitation for property wrappers in nonisolated classes. [Factory actors and migration](https://github.com/hmlongco/Factory#observation--actor-isolation) | Purpose-built SwiftUI/Observation wrappers, preview overrides, scopes, and isolated Swift Testing containers. [Factory previews/tests](https://github.com/hmlongco/Factory#mocking) | SPM-only in 3.x; no required build phase or released macros. `FactoryMacros` remains unreleased as of the snapshot. [Factory installation/macros](https://github.com/hmlongco/Factory#factory-macros) | Best fallback library, but unnecessary if restricted to the composition root. Property wrappers in domain objects would introduce service location and `FactoryKit` coupling. |
| Point-Free `swift-dependencies` 1.14.1 | Dependency keys and key paths are typed, but consumers read an ambient values collection rather than receiving constructor parameters. [Project overview](https://github.com/pointfreeco/swift-dependencies#overview) | Its scoped overrides use `@TaskLocal`, are inherited by structured/unstructured child tasks under documented rules, and are concurrency-safe at that layer. A maintainer documents that `@Dependency` property wrappers can conflict with `Sendable` classes because wrappers introduce mutable backing storage. [Dependency lifetimes](https://pointfreeco.github.io/swift-dependencies/main/documentation/dependencies/lifetimes/) · [Strict-concurrency discussion](https://github.com/pointfreeco/swift-dependencies/discussions/204) | Excellent live/preview/test values and scoped `withDependencies` overrides; current releases include SwiftUI Environment support. [Live, preview, and test dependencies](https://pointfreeco.github.io/swift-dependencies/main/documentation/dependencies/livepreviewtest/) · [releases](https://github.com/pointfreeco/swift-dependencies/releases) | SPM; current package has a Swift 6 manifest and optional macro product. [package files](https://github.com/pointfreeco/swift-dependencies) | Strong for applications already using Point-Free's environment-driven style/TCA. Here it would make `GroceryDomain` depend on a third-party ambient dependency system without solving a graph-size problem. |
| Swinject 2.10.0 | Registrations are typed, but resolution is runtime and returns an optional; the project's own example force-unwraps `resolve`. Missing/name-mismatched registrations therefore surface at runtime unless separately tested. [Swinject `Container`](https://github.com/Swinject/Swinject/blob/master/Sources/Container.swift) | The current stable release enabled Swift 6 language mode, and the container offers synchronized resolution/thread-safety features. This is not the same as compile-time validation that every resolved service is `Sendable` across the app's actor boundaries. [2.10.0 release](https://github.com/Swinject/Swinject/releases/tag/v2.10.0) · [features](https://github.com/Swinject/Swinject#features) | General-purpose container; no first-party SwiftUI/Observation injection API is part of the core README. Tests can replace registrations or build a test container. | SPM supported. Core uses runtime registration/resolution; optional extensions include separate code generation/autoregistration projects. [installation and extensions](https://github.com/Swinject/Swinject#installation) | Mature, but solves dynamic registration/scoping needs this app does not have and weakens fail-fast graph safety compared with constructors. |
| Needle 0.25.1 | Strongest whole-graph validation here: generated providers fail the build when an ancestor cannot satisfy a component dependency. [Needle generator safety](https://github.com/uber/needle/blob/master/GENERATOR.md#compile-time-safety) | The latest stable release was built with Swift 6.0/Xcode 16 beta, but the official material does not claim current Xcode 27 strict-concurrency validation. The component/dependency types still need appropriate isolation and `Sendable` design. [0.25.1 release](https://github.com/uber/needle/releases/tag/v0.25.1) | Architecture-neutral hierarchical components; mocks are supplied through dependency protocols. It has no special SwiftUI API. [Needle API](https://github.com/uber/needle/blob/master/API.md) | SPM installs `NeedleFoundation`, but the generator is a second tool integrated through Homebrew/Carthage plus an Xcode build phase and generated Swift file. [Needle installation](https://github.com/uber/needle#installation) · [generator integration](https://github.com/uber/needle/blob/master/GENERATOR.md#xcode-integration) | Appropriate for very large hierarchical graphs where generation cost earns its keep; excessive operational machinery for this small reference app. |

## Maintenance snapshot

- **Factory:** current README and releases identify 3.3.2; releases through July 2026 and explicit Xcode 27/strict-concurrency documentation show active maintenance. [Factory releases](https://github.com/hmlongco/Factory/releases) · [Factory migration notes](https://github.com/hmlongco/Factory#migration)
- **Point-Free Dependencies:** 1.14.1 is the current release, published in June 2026; 1.14 added cross-module `@DependencyEntry` work and a preview fix. [1.14.1 release](https://github.com/pointfreeco/swift-dependencies/releases/tag/1.14.1) · [1.14.0 notes](https://github.com/pointfreeco/swift-dependencies/releases/tag/1.14.0)
- **Swinject:** 2.10.0 is the current stable release; it enabled Swift 6 mode and updated CI to Xcode 16.4. The repository states that Faire's mobile platform team maintains it. [2.10.0 release](https://github.com/Swinject/Swinject/releases/tag/v2.10.0) · [repository README](https://github.com/Swinject/Swinject)
- **Needle:** the current stable release remains 0.25.1, a Swift 6 compatibility update built with an Xcode 16 beta toolchain; repository work continues, but its stable release cadence is materially older than Factory or Point-Free Dependencies. [Needle releases](https://github.com/uber/needle/releases) · [0.25.1 release](https://github.com/uber/needle/releases/tag/v0.25.1)

Maintenance is not a reason to reject any of the four outright. It does reinforce choosing no dependency when the app does not need a container, and choosing Factory rather than an older/heavier alternative if container features later become valuable.

## Concrete composition design

`GroceryDomain` should expose protocols, concrete use-case types whose dependencies are initializer arguments, and a small `AppDependencies` aggregate. `GroceryComposition` should expose one narrow factory that returns only domain-facing values, for example:

```swift
// GroceryComposition
public enum GroceryAppComposition {
    public static func makeAppDependencies() throws -> AppDependencies {
        let database = try GroceryDatabase.openBundledCatalogWithEphemeralDemoState()
        let catalog = GRDBProductCatalogRepository(database: database)
        let household = GRDBHouseholdRepository(database: database)
        let recorder = GRDBModelRunRecorder(database: database)
        let orchestration = FoundationModelsOrchestration(
            catalog: catalog,
            household: household,
            recorder: recorder
        )
        let runRequest = RunAssistantRequestUseCase(
            orchestration: orchestration,
            recorder: recorder
        )
        return AppDependencies(runAssistantRequest: runRequest)
    }
}
```

The app entry point calls that factory and constructs its app-owned root view model:

```swift
@main
struct GroceryApp: App {
    @State private var rootViewModel: RootViewModel

    init() {
        let dependencies = try! GroceryAppComposition.makeAppDependencies()
        _rootViewModel = State(
            initialValue: RootViewModel(
                runAssistantRequest: dependencies.runAssistantRequest
            )
        )
    }
}
```

Production error handling should replace the illustrative `try!`. The exact types can change as the design develops; the invariant is that concrete construction and imports remain in `GroceryComposition`, while the app owns its views and view models. Each view model and use case stores dependencies in `let` properties, which avoids hidden lookup and makes Swift 6 isolation review straightforward.

For previews and tests, construct the same view models/use cases with in-memory repository fakes and fake orchestration. Do not add a mutable global override registry merely to save a few initializer arguments.

## Decision

Adopt:

1. Manual constructor injection throughout `GroceryDomain` and the app's view models.
2. A small `GroceryComposition` module as the only concrete graph builder.
3. No DI library in milestone one.
4. Factory as the documented re-evaluation candidate only if the graph later develops meaningful scope, parameterized-factory, or preview-override complexity that manual wiring cannot express cleanly.

Do not use Swinject merely to hide concrete imports: runtime lookup cannot alter compile-time module dependencies. Do not use Point-Free Dependencies unless the project deliberately adopts its ambient task-local dependency model. Do not use Needle unless the graph grows enough to justify a generator and hierarchical component system.
