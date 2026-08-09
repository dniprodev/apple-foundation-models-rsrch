import CryptoKit
import Foundation
import GRDB

public enum ReferenceDatasetError: Error, Equatable, LocalizedError {
    case invalidManifest
    case artifactChecksumMismatch
    case invalidDatabase
    case productCountMismatch
    case missingBundleResource(String)

    public var errorDescription: String? {
        switch self {
        case .invalidManifest:
            "The bundled Reference Dataset manifest is invalid."
        case .artifactChecksumMismatch:
            "The bundled Reference Dataset does not match its provenance manifest."
        case .invalidDatabase:
            "The bundled Reference Dataset database is invalid."
        case .productCountMismatch:
            "The bundled Reference Dataset product count does not match its provenance manifest."
        case let .missingBundleResource(name):
            "The bundled Reference Dataset resource \(name) is missing."
        }
    }
}

public struct ReferenceDatasetResources: Sendable {
    public let databaseURL: URL
    public let manifestURL: URL

    public init(databaseURL: URL, manifestURL: URL) {
        self.databaseURL = databaseURL
        self.manifestURL = manifestURL
    }
}

public enum BundledReferenceDataset {
    public static func resources() throws -> ReferenceDatasetResources {
        guard let databaseURL = Bundle.module.url(
            forResource: "catalog-v1",
            withExtension: "sqlite"
        ) else {
            throw ReferenceDatasetError.missingBundleResource("catalog-v1.sqlite")
        }
        guard let manifestURL = Bundle.module.url(
            forResource: "catalog-manifest-v1",
            withExtension: "json"
        ) else {
            throw ReferenceDatasetError.missingBundleResource("catalog-manifest-v1.json")
        }
        return ReferenceDatasetResources(databaseURL: databaseURL, manifestURL: manifestURL)
    }
}

public struct ReferenceDatasetInstaller: Sendable {
    public let installedDatabaseURL: URL
    private let installationMarkerURL: URL

    public init(applicationSupportDirectory: URL) {
        installedDatabaseURL = applicationSupportDirectory
            .appendingPathComponent("ReferenceDataset", isDirectory: true)
            .appendingPathComponent("catalog-v1.sqlite")
        installationMarkerURL = installedDatabaseURL.appendingPathExtension("sha256")
    }

    @discardableResult
    public func install(database databaseURL: URL, manifest manifestURL: URL) throws -> URL {
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw ReferenceDatasetError.invalidManifest
        }

        guard try Self.sha256(databaseURL) == manifest.artifact.sha256 else {
            throw ReferenceDatasetError.artifactChecksumMismatch
        }
        try Self.validateDatabase(databaseURL, expectedProductCount: manifest.selection.retainedProducts)

        if FileManager.default.fileExists(atPath: installedDatabaseURL.path),
           let installedVersion = try? String(contentsOf: installationMarkerURL, encoding: .utf8),
           installedVersion == manifest.artifact.sha256 {
            try Self.validateDatabase(
                installedDatabaseURL,
                expectedProductCount: manifest.selection.retainedProducts
            )
            return installedDatabaseURL
        }

        let directory = installedDatabaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: installedDatabaseURL.path) {
            try FileManager.default.removeItem(at: installedDatabaseURL)
        }
        try FileManager.default.copyItem(at: databaseURL, to: installedDatabaseURL)
        try manifest.artifact.sha256.write(
            to: installationMarkerURL,
            atomically: true,
            encoding: .utf8
        )
        return installedDatabaseURL
    }

    private static func sha256(_ url: URL) throws -> String {
        let stream = try FileHandle(forReadingFrom: url)
        defer { try? stream.close() }
        var hasher = SHA256()
        while let data = try stream.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func validateDatabase(_ url: URL, expectedProductCount: Int) throws {
        do {
            var configuration = Configuration()
            configuration.readonly = true
            let database = try DatabaseQueue(path: url.path, configuration: configuration)
            let productCount = try database.read { db in
                try Int.fetchOne(db, sql: "SELECT count(*) FROM products") ?? 0
            }
            guard productCount == expectedProductCount else {
                throw ReferenceDatasetError.productCountMismatch
            }
            let catalogIsUsable = try database.read { db in
                let productColumns = try Row.fetchAll(
                    db,
                    sql: "PRAGMA table_info(products)"
                ).map { row -> String in row["name"] }
                let requiredColumns: Set<String> = [
                    "code", "name", "brand", "quantity", "median_price", "price_basis"
                ]
                guard requiredColumns.isSubset(of: Set(productColumns)) else { return false }

                let fullTextDefinition = try String.fetchOne(
                    db,
                    sql: "SELECT sql FROM sqlite_master WHERE name = 'product_fts'"
                )?.lowercased()
                guard fullTextDefinition?.contains("virtual table product_fts using fts5") == true else {
                    return false
                }
                let fullTextCount = try Int.fetchOne(
                    db,
                    sql: "SELECT count(*) FROM product_fts"
                ) ?? 0
                guard fullTextCount == productCount else { return false }

                let orphanedFullTextRows = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT count(*)
                        FROM product_fts
                        LEFT JOIN products p ON p.code = product_fts.code
                        WHERE p.code IS NULL
                        """
                ) ?? 0
                guard orphanedFullTextRows == 0 else { return false }

                let searchProbe = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT p.code, p.name, p.brand, p.quantity, p.median_price, p.price_basis
                        FROM product_fts
                        JOIN products p ON p.code = product_fts.code
                        WHERE product_fts MATCH 'breakfast'
                        LIMIT 1
                        """
                )
                return searchProbe != nil
            }
            guard catalogIsUsable else {
                throw ReferenceDatasetError.invalidDatabase
            }
        } catch let error as ReferenceDatasetError {
            throw error
        } catch {
            throw ReferenceDatasetError.invalidDatabase
        }
    }
}

private struct Manifest: Decodable {
    struct Artifact: Decodable {
        let sha256: String
    }

    struct Selection: Decodable {
        let retainedProducts: Int

        enum CodingKeys: String, CodingKey {
            case retainedProducts = "retained_products"
        }
    }

    let artifact: Artifact
    let selection: Selection
}
