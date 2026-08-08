// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GroceryData",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "GroceryData", targets: ["GroceryData"])],
    dependencies: [.package(path: "../GroceryDomain")],
    targets: [
        .target(name: "GroceryData", dependencies: ["GroceryDomain"]),
        .testTarget(name: "GroceryDataTests", dependencies: ["GroceryData", "GroceryDomain"])
    ]
)
