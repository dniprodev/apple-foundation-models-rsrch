// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GroceryDomain",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "GroceryDomain", targets: ["GroceryDomain"])],
    targets: [
        .target(name: "GroceryDomain"),
        .testTarget(name: "GroceryDomainTests", dependencies: ["GroceryDomain"])
    ]
)
