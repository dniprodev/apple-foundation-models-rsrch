import GroceryDomain

public struct DemoCatalog: ProductCatalog, Sendable {
    private let products: [CatalogProduct]

    public init(products: [CatalogProduct] = DemoCatalog.defaultProducts) {
        self.products = products
    }

    public func search(matching text: String) -> [CatalogProduct] {
        let query = text.lowercased()
        return products.filter {
            $0.name.lowercased().contains(query) || $0.detail.lowercased().contains(query)
        }
    }

    public static let defaultProducts = [
        CatalogProduct(name: "Green lentils", detail: "A pantry staple for soups and salads."),
        CatalogProduct(name: "Whole-wheat pasta", detail: "A quick base for a weeknight meal."),
        CatalogProduct(name: "Canned tomatoes", detail: "Useful for sauces, soups, and stews.")
    ]
}
