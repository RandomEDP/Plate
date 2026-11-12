import Foundation

/// Splits a line that names two foods ("50g garlic and scallions") into one ingredient each, so both get their macros
/// and both reach the shopping list. Before this, only the first food was matched and the other was lost (Ethan's
/// video import, 12 November 2026: the list asked for garlic and forgot the scallions).
public enum IngredientSplit {
    static let joiners = [" and ", " & ", " + "]
    static let sharedUnits: Set<MeasureUnit> = [.g, .kg, .mg, .ml, .l, .oz, .lb, .floz]

    /// The two foods in a name, when it really is two: each side matches a different food, and the whole thing isn't
    /// one food's own name ("salt and pepper", "sweet and sour sauce").
    public static func parts(of name: String) -> [(name: String, food: Food)]? {
        let lower = name.lowercased()
        guard let joiner = joiners.first(where: { lower.contains($0) }) else { return nil }
        // One food whose own name has "and" in it.
        if FoodDatabase.all.contains(where: { f in ([f.name] + f.aliases).contains { a in
            let a = a.lowercased()
            return joiners.contains(where: a.contains) && lower.contains(a)
        } }) { return nil }
        let pieces = lower.components(separatedBy: joiner).map { $0.trimmingCharacters(in: .whitespaces) }
        guard pieces.count == 2, !pieces.contains(where: \.isEmpty) else { return nil }
        // Slice the original so capitals are kept.
        let first = String(name.prefix(pieces[0].count)).trimmingCharacters(in: .whitespaces)
        let second = String(name.suffix(pieces[1].count)).trimmingCharacters(in: .whitespaces)
        guard let a = FoodMatcher.match(first), let b = FoodMatcher.match(second), a.id != b.id else { return nil }
        // "pasta and sauce" style lines where one side only matches because of the other aren't split: each side
        // must be short and to the point.
        guard first.split(separator: " ").count <= 4, second.split(separator: " ").count <= 4 else { return nil }
        return [(first, a), (second, b)]
    }

    /// One ingredient, or two when the line named two foods. A weight or volume is shared between them (half each,
    /// with a note saying so); a count or spoonful is taken to mean that much of each.
    public static func split(_ ing: RecipeIngredient) -> [RecipeIngredient] {
        guard let parts = parts(of: ing.name) else { return [ing] }
        var quantity = ing.quantity
        var note = ing.note
        if let q = ing.quantity, sharedUnits.contains(q.unit) {
            quantity = Quantity(q.amount / 2, q.unit)
            let shared = "half of the \(Format.quantity(q)) given for \(ing.name)"
            note = note.map { $0 + "; " + shared } ?? shared
        }
        return parts.map { RecipeIngredient(name: $0.name, foodId: $0.food.id, quantity: quantity, note: note, optional: ing.optional) }
    }

    public static func split(_ ingredients: [RecipeIngredient]) -> [RecipeIngredient] {
        ingredients.flatMap(split)
    }
}
