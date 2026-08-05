// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "CatalogCalibration",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.10.0")
    ],
    targets: [
        .executableTarget(
            name: "CatalogProbe",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/CatalogProbe"
        )
    ]
)
