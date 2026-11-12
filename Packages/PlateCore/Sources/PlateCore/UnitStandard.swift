import Foundation

/// Puts each recipe ingredient in the unit you'd count it in, so every recipe reads the same way: garlic in cloves,
/// onions, lemons and eggs by the piece, oils and milk in ml, and no ounces or cups. A recipe that says "50g garlic"
/// becomes "10 cloves garlic", with what it said kept in the note (Ethan, 12 November 2026).
///
/// Foods kept by weight (chicken, carrots, rice) stay as the recipe wrote them, apart from ounces and pounds becoming
/// grams: "2 chicken breasts" is clearer to cook from than "320g", and the shopping list converts either way.
public enum UnitStandard {
    static let weights: Set<MeasureUnit> = [.g, .kg, .mg, .oz, .lb]
    static let spoons: Set<MeasureUnit> = [.tsp, .tbsp]
    static let imperialVolumes: Set<MeasureUnit> = [.cup, .floz]
    /// Foods where a spoonful really means some of the food itself (minced garlic, garlic purée).
    static let spoonsCountAsPieces: Set<String> = ["garlic"]
    /// Foods counted in cloves rather than as plain pieces.
    static let cloveFoods: Set<String> = ["garlic"]

    /// The quantity in the food's standard unit, or nil when it's already standard or can't be converted.
    public static func standard(_ q: Quantity, food: Food) -> Quantity? {
        switch food.unit {
        case .piece:
            guard let each = food.gramsPerPiece, each > 0 else { return nil }
            let clove = cloveFoods.contains(food.id)
            if q.unit == .piece && clove { return Quantity(q.amount, .clove) }
            let convertible = weights.contains(q.unit) || (spoons.contains(q.unit) && spoonsCountAsPieces.contains(food.id))
            guard convertible, let pieces = Units.amount(q, in: .piece, food: food), pieces > 0 else { return nil }
            return Quantity(roundPieces(pieces, gramsEach: each), clove ? .clove : .piece)
        case .g:
            guard q.unit == .oz || q.unit == .lb, let g = Units.amount(q, in: .g, food: food) else { return nil }
            return Quantity(roundTo(g, g < 50 ? 1 : 5), .g)
        case .ml:
            guard weights.contains(q.unit) || imperialVolumes.contains(q.unit),
                  let ml = Units.amount(q, in: .ml, food: food) else { return nil }
            return Quantity(roundTo(ml, ml < 50 ? 1 : 5), .ml)
        }
    }

    /// Small things (cloves, eggs, wraps, tomatoes) go to whole ones, at least one: half an egg isn't much use.
    /// Bigger things go to quarters below one ("¼ onion") and halves above.
    static func roundPieces(_ n: Double, gramsEach: Double) -> Double {
        if gramsEach <= 90 { return max(1, n.rounded()) }
        if n < 1 { return max(0.25, roundTo(n, 0.25)) }
        return roundTo(n, 0.5)
    }

    static func roundTo(_ v: Double, _ step: Double) -> Double { (v / step).rounded() * step }

    public static func standardise(_ ing: RecipeIngredient) -> RecipeIngredient {
        guard let q = ing.quantity, let food = FoodDatabase.food(ing.foodId), let new = standard(q, food: food),
              new != q else { return ing }
        var out = ing
        out.quantity = new
        // Say what the recipe said, unless only the word changed (3 garlic → 3 cloves) or a note already gives it.
        let note = ing.note ?? ""
        if q.unit != .piece, !note.contains(Format.quantity(q)), !note.contains("given for") {
            let said = "recipe said \(Format.quantity(q))"
            out.note = ing.note.map { $0 + "; " + said } ?? said
        }
        return out
    }

    public static func standardise(_ ingredients: [RecipeIngredient]) -> [RecipeIngredient] {
        ingredients.map(standardise)
    }

    /// Splits lines naming two foods, then puts each in its standard unit. What every new recipe goes through.
    public static func tidy(_ ingredients: [RecipeIngredient]) -> [RecipeIngredient] {
        standardise(IngredientSplit.split(ingredients))
    }
}

extension Household {
    static let unitsStandardisedKey = "unitsStandardised"

    /// Puts the units of recipes saved before standard units came in into the standard ones, once. True when it ran.
    @discardableResult
    public mutating func standardiseSavedRecipeUnitsOnce() -> Bool {
        guard extras[Household.unitsStandardisedKey] == nil else { return false }
        for i in recipes.indices {
            let tidied = UnitStandard.standardise(recipes[i].ingredients)
            if tidied != recipes[i].ingredients {
                recipes[i].ingredients = tidied
                recipes[i].updatedAt = Date()
            }
        }
        extras[Household.unitsStandardisedKey] = "1"
        updatedAt = Date()
        return true
    }
}
