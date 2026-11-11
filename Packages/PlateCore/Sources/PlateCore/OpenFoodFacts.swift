import Foundation

/// Reads a product from Open Food Facts (the free, open barcode database) for barcode scanning.
public enum OpenFoodFacts {
    public struct Product: Equatable, Sendable {
        public var barcode: String
        public var name: String
        public var brand: String?
        public var per100: Macros?
        /// Pack size in grams, ml or pieces, when the label gives one.
        public var size: Double?
        public var unit: BaseUnit?
        /// The built-in food it most likely is (scanned semi-skimmed milk → milk), for recipes and suggestions.
        public var food: Food?
    }

    public static func url(for barcode: String) -> URL? {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return URL(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json?fields=product_name,product_name_en,generic_name,brands,quantity,product_quantity,product_quantity_unit,nutriments,categories_tags")
    }

    public static func parse(_ data: Data, barcode: String) -> Product? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let p = obj["product"] as? [String: Any] else { return nil }
        let name = [p["product_name_en"], p["product_name"], p["generic_name"]]
            .compactMap { $0 as? String }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let name else { return nil }
        let brand = (p["brands"] as? String)?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }

        var per100: Macros?
        if let n = p["nutriments"] as? [String: Any] {
            func num(_ k: String) -> Double? {
                if let d = n[k] as? Double { return d }
                if let i = n[k] as? Int { return Double(i) }
                if let s = n[k] as? String { return Double(s) }
                return nil
            }
            let kcal = num("energy-kcal_100g") ?? num("energy_100g").map { $0 / 4.184 }
            if let kcal {
                per100 = Macros(kcal: kcal, protein: num("proteins_100g") ?? 0, carbs: num("carbohydrates_100g") ?? 0,
                                fat: num("fat_100g") ?? 0, fibre: num("fiber_100g") ?? 0)
            }
        }

        var size: Double?
        var unit: BaseUnit?
        if let q = p["quantity"] as? String, let parsed = IngredientParser.parse(q + " x"), let qty = parsed.quantity {
            size = qty.amount * qty.unit.factor
            unit = qty.unit.base
        } else if let pq = p["product_quantity"] {
            size = (pq as? Double) ?? (pq as? Int).map(Double.init) ?? (pq as? String).flatMap(Double.init)
            let u = (p["product_quantity_unit"] as? String)?.lowercased() ?? "g"
            unit = u.hasPrefix("ml") || u == "l" || u == "cl" ? .ml : .g
        }
        let food = FoodMatcher.match(name)
        return Product(barcode: barcode, name: name, brand: brand, per100: per100, size: size, unit: unit, food: food)
    }
}
