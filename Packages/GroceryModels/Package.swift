// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GroceryModels",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "GroceryModels", targets: ["GroceryModels"])],
    dependencies: [.package(path: "../GroceryDomain")],
    targets: [
        .target(name: "GroceryModels", dependencies: ["GroceryDomain"]),
        .testTarget(name: "GroceryModelsTests", dependencies: ["GroceryModels", "GroceryDomain"])
    ]
)
