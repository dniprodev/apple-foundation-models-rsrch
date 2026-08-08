// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GroceryComposition",
    platforms: [.iOS(.v17), .macOS(.v14)],
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
