// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GroceryModels",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [.library(name: "GroceryModels", targets: ["GroceryModels"])],
    dependencies: [.package(path: "../GroceryDomain")],
    targets: [
        .target(name: "GroceryModels", dependencies: ["GroceryDomain"]),
        .testTarget(name: "GroceryModelsTests", dependencies: ["GroceryModels", "GroceryDomain"])
    ]
)
