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
    static let volumes: Set<MeasureUnit> = [.cup, .floz, .ml, .l]
    /// Foods where a spoonful really means some of the food itself (minced garlic, garlic purée).
    static let spoonsCountAsPieces: Set<String> = ["garlic"]
    /// Foods counted in cloves rather than as plain pieces.
    public static let cloveFoods: Set<String> = ["garlic", "black-garlic"]
    /// Cloves in a whole bulb ("1 bulb of garlic").
    public static let clovesPerBulb = 10.0

    /// The quantity in the food's standard unit, or nil when it's already standard or can't be converted.
    ///
    /// Spoons, pinches, tins, bunches and handfuls are kept: "1 tsp cumin" and "1 tin chickpeas" are how you'd
    /// measure them. Counts of weighed foods ("2 chicken breasts", "1 butternut squash") are kept too.
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
            // Cups and ml only when Plate knows how heavy the food is: a cup of spinach isn't 240 g.
            let byVolume = volumes.contains(q.unit) && food.gramsPerMl != 1
            guard q.unit == .oz || q.unit == .lb || byVolume, let g = Units.amount(q, in: .g, food: food) else { return nil }
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

    /// Puts one ingredient in its food's unit. `record` keeps what the recipe said in `convertedFrom`, so it's shown
    /// under the line and can be put back; built-in recipes don't need that.
    public static func standardise(_ ing: RecipeIngredient, record: Bool = true) -> RecipeIngredient {
        guard let q = ing.quantity, let food = FoodDatabase.food(ing.foodId), let new = standard(q, food: food),
              new != q else { return ing }
        var out = ing
        out.quantity = new
        // Keep what the recipe said, unless only the word changed (3 garlic → 3 cloves), or the line was split from
        // one naming two foods (its note already says the amount was for both).
        let wordOnly = q.unit == .piece && new.unit == .clove && q.amount == new.amount
        let split = ing.note?.contains("given for") == true
        if record, !wordOnly, !split, ing.convertedFrom == nil { out.convertedFrom = q }
        if new.unit == .piece { out.name = Plural.fit(ing.name, to: new.amount) }
        return out
    }

    public static func standardise(_ ingredients: [RecipeIngredient], record: Bool = true) -> [RecipeIngredient] {
        ingredients.map { standardise($0, record: record) }
    }

    /// Splits lines naming two foods, then puts each in its standard unit. What every new recipe goes through.
    public static func tidy(_ ingredients: [RecipeIngredient]) -> [RecipeIngredient] {
        standardise(IngredientSplit.split(ingredients))
    }

    /// "Converted from 30g red chillies", for the small text under a converted line.
    public static func convertedNote(_ ing: RecipeIngredient, scale: Double = 1) -> String? {
        guard let from = ing.convertedFrom else { return nil }
        let scaled = Quantity(from.amount * scale, from.unit)
        let name = from.unit == .piece ? Plural.fit(ing.name, to: scaled.amount) : ing.name
        return "Converted from \(Format.quantity(scaled)) \(name)"
    }
}

/// Makes "2 red chilli" read "2 red chillies" and "1 onions" read "1 onion" after a conversion changes the count.
enum Plural {
    static let irregular: [String: String] = ["chilli": "chillies", "chili": "chilies", "leaf": "leaves", "loaf": "loaves"]
    /// Words that don't take an s, or would read oddly with one.
    static let uncountable: Set<String> = [
        "celery", "fennel", "kohlrabi", "lemongrass", "choi", "choy", "radicchio", "iceberg", "romaine", "cos", "garlic",
        "ginger", "broccoli", "cauliflower", "squash", "kale", "spinach", "lettuce", "rocket", "watercress", "papaya",
    ]

    static func fit(_ name: String, to amount: Double) -> String {
        var words = name.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard let last = words.last, last.count > 2, last.allSatisfy(\.isLetter) else { return name }
        let lower = last.lowercased()
        let singular = self.singular(lower)
        guard !uncountable.contains(singular) else { return name }
        let wanted = amount > 1 ? plural(singular) : singular
        guard wanted != lower else { return name }
        words[words.count - 1] = wanted
        return words.joined(separator: " ")
    }

    static func plural(_ w: String) -> String {
        if let p = irregular[w] { return p }
        if w.hasSuffix("s") { return w }
        if w.hasSuffix("y"), let before = w.dropLast().last, !"aeiou".contains(before) { return w.dropLast() + "ies" }
        if w.hasSuffix("ch") || w.hasSuffix("sh") || w.hasSuffix("x") || w.hasSuffix("o") { return w + "es" }
        return w + "s"
    }

    static func singular(_ w: String) -> String {
        if let s = irregular.first(where: { $0.value == w })?.key { return s }
        if w.hasSuffix("ss") || w.hasSuffix("us") { return w }
        if w.hasSuffix("ies") { return w.dropLast(3) + "y" }
        if w.hasSuffix("oes") || w.hasSuffix("ches") || w.hasSuffix("shes") || w.hasSuffix("xes") { return String(w.dropLast(2)) }
        if w.hasSuffix("s") { return String(w.dropLast()) }
        return w
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
