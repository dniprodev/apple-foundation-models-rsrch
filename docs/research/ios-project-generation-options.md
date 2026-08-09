# iOS project-generation options for the Reference App

Research snapshot: 2026-08-06. Primary sources only.

## Recommendation

Use a **plain Xcode project checked into Git**. Do not add Tuist or XcodeGen for milestone one.

The planned graph is small:

```text
GroceryApp.xcodeproj
  └─ app target
       ├─ local package: GroceryDomain
       └─ local package: GroceryComposition
            ├─ local package: GroceryData ────> GroceryDomain
            └─ local package: GroceryModels ──> GroceryDomain

CatalogBuilder (separate developer-only Swift executable package)
```

Xcode supports local packages as a first-party way to modularize an app, and Swift packages can contain library or executable products and depend on other local packages by path. The app project therefore does not need to mirror every package as an Xcode target or workspace project. It links the domain-facing products it uses; the package manifests own the package-to-package graph. [Apple: organizing code with local packages](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages) · [Apple: creating a standalone Swift package](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode)

This choice is not a rejection of project generation in general. It is the smallest toolchain that expresses this particular design. The project has one app target, a few local packages, no release matrix, no large workspace, no measured build-time problem, and no team-scale project-file contention. A generator would replace one small checked-in project with a manifest, a pinned third-party executable, a generation command, and another compatibility boundary while Xcode 27 is in beta.

Use Xcode's folder-backed groups for app sources and resources. Apple says folders have a much smaller project-file representation, automatically track file-system changes, and reduce merge conflicts because adding or removing files does not modify the project file. That removes much of the historical reason to introduce XcodeGen for source-file bookkeeping. [Apple: managing files and folders in an Xcode project](https://developer.apple.com/documentation/xcode/managing-files-and-folders-in-your-xcode-project)

## Comparison

| Concern | Checked-in Xcode project | XcodeGen | Tuist |
| --- | --- | --- | --- |
| Source of truth | `.xcodeproj` created and edited by Xcode | YAML or JSON `project.yml` | Swift `Project.swift`/`Workspace.swift` manifests |
| Bootstrap | Install the required Xcode beta, clone, open the project | Install and pin XcodeGen, clone, run `xcodegen generate`, open the result | Install and pin Tuist, clone, install dependencies as applicable, run `tuist generate`, open the result |
| Local packages | Native Xcode local-package references; package manifests own transitive path dependencies | Top-level packages support `path` to a directory containing `Package.swift`; targets can link one or several products | Supports local Swift-package dependencies; can also convert a root `Package.swift`, but Tuist labels that package-as-project mode beta |
| Dependency resolution | Xcode/SwiftPM; commit `Package.resolved` for deterministic remote versions | Generated project uses Xcode/SwiftPM; exact versions/revisions can live in the spec, while flexible requirements need an explicit lock-file workflow because Xcode stores `Package.resolved` inside the generated project | Either Xcode's native package integration or Tuist's XcodeProj-based integration; the latter adds control and cache compatibility but can lag new SwiftPM features |
| Generation/build features | No generation. Native Xcode incremental build behavior is enough until measurements say otherwise | `--use-cache` skips project regeneration when the spec and referenced files are unchanged; it is not a compiled-module cache | Dependency-graph validation, focused generation, selective testing, module caching, and Xcode compilation-cache integration |
| Xcode 27 beta risk | Lowest: Xcode writes and consumes its own current format | Highest here: XcodeGen's install instructions explicitly require the latest stable, non-beta Xcode | Additional generator/XcodeProj compatibility layer; native package integration reduces package-mapping risk, but the project still depends on the pinned Tuist release supporting the beta |
| CI/reproducibility | Build the checked-in project directly; pin Xcode and commit `Package.resolved` | Install the pinned generator, regenerate, and build; CI should fail if generation differs or the build fails | Install the pinned Tuist version, generate, and build/test; Tuist recommends `mise` pinning and requires an install/generate step in Xcode Cloud |
| Generated `.xcodeproj` in Git | Yes; it is the source of truth | Normally no; XcodeGen explicitly promotes removing it from Git | No; manifests are the source of truth and generation is the normal editing workflow |
| Contributor experience | No non-Apple bootstrap tool and no manifest DSL to learn | Small extra tool and a readable YAML schema; changes to project settings must be made in the spec, not retained as ad hoc generated-project edits | Largest conceptual and operational surface: Swift manifest DSL, Tuist commands, version pinning, and optional server-backed features |

Sources for the generator behavior: [XcodeGen README and installation/usage](https://github.com/yonaskolb/XcodeGen) · [XcodeGen project specification](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) · [Tuist generated projects](https://tuist.dev/en/docs/guides/features/projects) · [Tuist directory structure and Swift-package mode](https://tuist.dev/en/docs/guides/features/projects/directory-structure) · [Tuist dependency integration](https://tuist.dev/en/docs/guides/features/projects/dependencies) · [Tuist installation](https://tuist.dev/en/docs/guides/install-tuist) · [Tuist CI](https://tuist.dev/en/docs/guides/automate/continuous-integration)

## What each generated option would buy

### XcodeGen

XcodeGen is the smaller generator. Its YAML/JSON specification declares targets, schemes, build settings, source paths, and packages; `xcodegen generate` turns that into an Xcode project. Local packages are supported with a `path`, and an app dependency can select multiple products from one package. Its `--use-cache` option avoids rewriting the project when generator inputs are unchanged. [XcodeGen README](https://github.com/yonaskolb/XcodeGen) · [XcodeGen local-package specification](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md#local-package)

That would be valuable if this repository had recurring `.pbxproj` merge conflicts or a frequently changing set of Xcode targets and schemes. It offers little for the current package graph because the four architectural modules are already declared in `Package.swift`, not individually maintained as app-project targets. The remaining Xcode project is mostly the app target, its tests, resources, signing, and local-package product links.

XcodeGen is also the weaker fit for a beta-toolchain research app: its own installation section says the latest stable, non-beta Xcode must be installed. Its current project specification defaults to the Xcode 16.0 project format and lists formats only through Xcode 16.3; it does not list an Xcode 27 format. That does not prove a generated project will fail when opened by Xcode 27 beta, but it is a concrete compatibility and project-rewrite risk with no compensating benefit here. [XcodeGen installation](https://github.com/yonaskolb/XcodeGen#installing) · [XcodeGen project-format options](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md#options)

If XcodeGen is adopted later, pin its version, commit `project.yml` and any included specs, ignore the generated `.xcodeproj`, and make generation plus a clean build part of CI. Do not check in both the spec and project as competing sources of truth.

### Tuist

Tuist is a broader project and build-workflow platform. Its Swift manifests are statically checked and can share Swift helpers, which becomes useful when a large workspace repeats target conventions. It can validate and inspect dependency graphs, generate focused workspaces, selectively run affected tests, and replace cacheable modules with binaries. Its current module cache requires a generated project plus a Tuist account/project, and Tuist recommends a CI cache-warming workflow. [Tuist manifests](https://tuist.dev/en/docs/guides/features/projects/manifests) · [Tuist module cache](https://tuist.dev/en/docs/guides/features/cache/module-cache) · [Tuist selective testing](https://tuist.dev/en/docs/guides/develop/selective-testing/xcode-project)

Those capabilities address measured scale problems, not the mere existence of four local packages. This app has neither a large target graph nor a build-performance target. Adding Tuist now would make every contributor install a pinned tool and generate before opening, while the cache and selective-test advantages would be unused.

Tuist offers two Swift-package integration paths. Xcode's default integration is the convenient, Apple-maintained route. Tuist's XcodeProj-based integration provides more control and supports Tuist caching/selective-test workflows, but Tuist explicitly warns that it is more likely to take time to support new Swift Package features and configurations. For an Xcode 27 beta experiment, that warning argues against introducing the XcodeProj mapping unless a Tuist-only feature is actually needed. [Tuist dependencies](https://tuist.dev/en/docs/guides/features/projects/dependencies)

If Tuist is adopted later, pin it project-locally with `mise`, commit the manifests and pin file, ignore generated projects, and have CI run generation before build/test. Tuist documents this exact installation and CI shape, including a post-clone generation step for Xcode Cloud. [Tuist installation](https://tuist.dev/en/docs/guides/install-tuist) · [Tuist CI](https://tuist.dev/en/docs/guides/automate/continuous-integration)

## Native setup and reproducibility

The milestone-one bootstrap should be:

1. Install the named Xcode 27 beta build and required simulator runtime.
2. Clone the repository.
3. Open the checked-in `GroceryApp.xcodeproj`.
4. Let Xcode resolve the package graph, then build the shared app scheme.

Commit the app project's `Package.resolved`. Apple says it records the exact commits and binary checksums selected by package resolution and should be committed so team members and CI use the same dependency versions. In CI, pass `-disableAutomaticPackageResolution` after the lock file exists so unexpected versions cannot be selected. [Apple: adding package dependencies](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) · [Apple: Swift packages in CI](https://developer.apple.com/documentation/xcode/building-swift-packages-or-apps-that-use-them-in-continuous-integration-workflows)

`CatalogBuilder` should remain a standalone Swift executable package invoked by a documented command. It produces the catalog artifact before app development or when the pinned source snapshot changes; it does not need to appear as a target in the app project. SwiftPM natively supports executable products, so neither generator simplifies this boundary. [Apple: creating a standalone Swift package](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode)

## Re-evaluation thresholds

Keep the checked-in Xcode project until evidence crosses one of these thresholds:

- Adopt **XcodeGen** if the app project grows to several Xcode-owned targets/schemes/configurations and `.pbxproj` changes cause recurring merge conflicts or manual drift that folder-backed groups and review cannot contain.
- Adopt **Tuist** if the workspace grows to dozens of targets or multiple apps, target conventions need reusable checked abstractions, dependency-graph mistakes recur, or measured clean/CI build and test times justify focused generation, caching, or selective testing.
- Do not switch merely because `GroceryDomain`, `GroceryData`, `GroceryModels`, and `GroceryComposition` are separate modules. SwiftPM already declares and enforces that graph.

At either threshold, run a small migration proof against the exact Xcode beta before committing to the generator. The proof must generate, resolve every local/remote package, build, run tests and previews, and open without Xcode rewriting the generated project unexpectedly.

## Decision

Adopt:

1. One checked-in Xcode project containing the app and app test targets.
2. Separate local Swift packages for the architectural modules, with dependencies declared in their `Package.swift` manifests.
3. A standalone Swift executable package for `CatalogBuilder`.
4. Folder-backed Xcode groups to minimize project-file churn.
5. A committed `Package.resolved` and a documented Xcode 27 beta build as the reproducibility boundary.

Add no project generator for milestone one. XcodeGen is the first candidate if project-file churn becomes real; Tuist is the candidate only when workspace/build scale makes its graph and caching features earn their operational cost.
