// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GroceryModels",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [.library(name: "GroceryModels", targets: ["GroceryModels"])],
    dependencies: [
        .package(path: "../GroceryDomain"),
        .package(
            url: "https://github.com/anthropics/ClaudeForFoundationModels.git",
            revision: "98a74ff2300996ff192062c25114aea8c4103d2b"
        )
    ],
    targets: [
        .target(
            name: "GroceryModels",
            dependencies: ["GroceryDomain", "ClaudeForFoundationModels"]
        ),
        .testTarget(name: "GroceryModelsTests", dependencies: ["GroceryModels", "GroceryDomain"])
    ]
)
