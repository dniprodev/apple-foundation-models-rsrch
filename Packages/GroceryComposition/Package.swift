// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GroceryComposition",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "GroceryComposition", type: .static, targets: ["GroceryComposition"])],
    dependencies: [
        .package(path: "../GroceryDomain"),
        .package(path: "../GroceryData"),
        .package(path: "../GroceryModels")
    ],
    targets: [
        .target(name: "GroceryComposition", dependencies: ["GroceryDomain", "GroceryData", "GroceryModels"]),
        .testTarget(name: "GroceryCompositionTests", dependencies: ["GroceryComposition", "GroceryDomain"])
    ]
)
