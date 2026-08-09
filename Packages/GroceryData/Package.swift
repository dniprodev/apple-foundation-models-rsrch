// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GroceryData",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "GroceryData", targets: ["GroceryData"])],
    dependencies: [
        .package(path: "../GroceryDomain"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.10.0")
    ],
    targets: [
        .target(
            name: "GroceryData",
            dependencies: ["GroceryDomain", .product(name: "GRDB", package: "GRDB.swift")],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "GroceryDataTests",
            dependencies: ["GroceryData", "GroceryDomain", .product(name: "GRDB", package: "GRDB.swift")]
        )
    ]
)
