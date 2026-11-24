import Foundation

/// Recipes from Instagram or TikTok that an older Plate read badly, read again once from their links.
/// Ethan's "Got the gravy ick" (24 November 2026) came from a caption laid out as "SMOKY TOFU: 1 block tofu, …"
/// sections, which Plate didn't read: it was saved with almost no ingredients and 7 kcal a portion.
public enum ImportRepair {
    /// A saved import worth reading again: it came from a post link and has too little in it to be the real recipe.
    public static func looksThin(_ recipe: Recipe) -> Bool {
        guard [.instagram, .tiktok].contains(recipe.source.kind), let url = recipe.source.url, !url.isEmpty else { return false }
        if recipe.ingredients.count < 4 { return true }
        let counted = recipe.ingredients.filter { $0.foodId != nil && $0.quantity != nil }.count
        return counted < 3 || Nutrition.perServing(recipe).kcal < 60
    }

    /// Whether a fresh reading should replace the saved one: it has to find clearly more.
    public static func isBetter(_ fresh: Recipe, than old: Recipe) -> Bool {
        let counted = { (r: Recipe) in r.ingredients.filter { $0.foodId != nil }.count }
        return fresh.ingredients.count > old.ingredients.count && counted(fresh) > counted(old)
    }
}

extension Household {
    static let thinImportsCheckedKey = "thinImportsReread"

    /// The thin imports to read again, once (the app marks it done with `markThinImportsReread` when it has tried).
    public var thinImportsToReread: [Recipe] {
        guard extras[Household.thinImportsCheckedKey] == nil else { return [] }
        return recipes.filter(ImportRepair.looksThin)
    }

    public mutating func markThinImportsReread() {
        extras[Household.thinImportsCheckedKey] = "1"
        updatedAt = Date()
    }
}
