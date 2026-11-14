import Foundation

/// Finds the amounts in an AI-tidied recipe that aren't in the text it was read from, so the recipe can say they were
/// guessed (Ethan, 14 November 2026: the guessed amounts "seem off a decent amount"). Where Plate's own reader found
/// the amount in the text, that amount is used instead of the AI's.
public enum GuessCheck {
    /// The recipe with each ingredient's `amountGuessed` set, and its portions checked against the text.
    public static func check(_ recipe: Recipe, against text: String, parsed: ParsedRecipe) -> Recipe {
        var r = recipe
        let lines = RecipeTextParser.splitLines(text)
        let ownReading = UnitStandard.tidy(parsed.ingredients)
        r.ingredients = recipe.ingredients.map { ing in
            var out = ing
            guard let said = ing.convertedFrom ?? ing.quantity else { out.amountGuessed = nil; return out }
            if stated(said, for: ing, in: lines) { out.amountGuessed = nil; return out }
            if let mine = ownReading.first(where: { $0.foodId != nil && $0.foodId == ing.foodId && $0.quantity != nil }) {
                out.quantity = mine.quantity
                out.convertedFrom = mine.convertedFrom
                out.amountGuessed = nil
                return out
            }
            out.amountGuessed = true
            return out
        }
        let portions = servings(parsed: parsed.servings, ai: recipe.servings, text: text)
        r.servings = portions.count
        r.servingsGuessed = portions.guessed ? true : nil
        return r
    }

    /// Portions: what the text says, or the AI's figure when the text backs it up, or 2 (guessed).
    public static func servings(parsed: Int?, ai: Int?, text: String) -> (count: Int, guessed: Bool) {
        if let parsed { return (parsed, false) }
        if let ai, ai > 0 {
            let words = ["serv", "portion", "people", "person", "makes", "feeds", "meals", "batch"]
            for line in RecipeTextParser.splitLines(text).map({ $0.lowercased() }) where words.contains(where: line.contains) {
                if numbers(in: line).contains(Double(ai)) { return (ai, false) }
            }
        }
        return (ParsedRecipe.assumedServings, true)
    }

    /// Whether a line of the text that names this food gives this amount (in any unit that comes to about the same).
    static func stated(_ q: Quantity, for ing: RecipeIngredient, in lines: [String]) -> Bool {
        let keys = AIGuard.keyWords(ing.name).map { String($0.prefix(5)) }
        guard !keys.isEmpty else { return true }
        let food = FoodDatabase.food(ing.foodId)
        for line in lines {
            let lower = line.lowercased()
            guard keys.contains(where: lower.contains) else { continue }
            if numbers(in: lower).contains(where: { close($0, q.amount) }) { return true }
            if let food, let theirs = IngredientParser.parse(line)?.quantity,
               let a = Units.amount(theirs, in: food.unit, food: food), let b = Units.amount(q, in: food.unit, food: food),
               a > 0, abs(a - b) / max(a, b) <= 0.15 { return true }
        }
        return false
    }

    static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= max(0.01, 0.01 * max(a, b)) }

    /// Every number written in a line: 200, 1.5, 1/2, 1 1/2, ½, 1½, and words like "two" or "half".
    static func numbers(in line: String) -> [Double] {
        var out: [Double] = []
        let pattern = #"(\d+(?:[.,]\d+)?)(?:\s+(\d+)\s*/\s*(\d+)|\s*/\s*(\d+)|\s*([½¼¾⅓⅔⅛]))?|([½¼¾⅓⅔⅛])"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return out }
        let ns = line as NSString
        func num(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            if let f = num(m, 6), let c = f.first, let v = IngredientParser.unicodeFractions[c] { out.append(v); continue }
            guard let w = num(m, 1).flatMap({ Double($0.replacingOccurrences(of: ",", with: ".")) }) else { continue }
            if let n = num(m, 2).flatMap(Double.init), let d = num(m, 3).flatMap(Double.init), d != 0 {
                out.append(w + n / d)
            } else if let d = num(m, 4).flatMap(Double.init), d != 0 {
                out.append(w / d)
            } else if let f = num(m, 5), let c = f.first, let v = IngredientParser.unicodeFractions[c] {
                out.append(w + v)
            } else {
                out.append(w)
            }
        }
        for word in line.components(separatedBy: CharacterSet.letters.inverted) {
            if let v = IngredientParser.numberWords[word], word != "a", word != "an" { out.append(v) }
        }
        return out
    }
}

extension Household {
    static let conversionNotesKey = "conversionNotesMoved"

    /// Once, for recipes saved before the big ingredient list: moves "recipe said 15g" notes into the converted-from
    /// line (so they can be put back), matches ingredients the old list didn't know, and puts those in their units.
    @discardableResult
    public mutating func upgradeIngredientsOnce() -> Bool {
        guard extras[Household.conversionNotesKey] == nil else { return false }
        for i in recipes.indices {
            let before = recipes[i].ingredients
            recipes[i].ingredients = before.map { ing in
                var out = ing
                if let note = ing.note, let range = note.range(of: #"(; )?recipe said [^;]+"#, options: .regularExpression) {
                    let said = note[range].replacingOccurrences(of: "; ", with: "").replacingOccurrences(of: "recipe said ", with: "")
                    if out.convertedFrom == nil, let q = IngredientParser.parse("\(said) \(ing.name)")?.quantity { out.convertedFrom = q }
                    var rest = note
                    rest.removeSubrange(range)
                    rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: " ;"))
                    out.note = rest.isEmpty ? nil : rest
                }
                if out.foodId == nil, let food = FoodMatcher.match(out.name) {
                    out.foodId = food.id
                    out = UnitStandard.standardise(out)
                }
                return out
            }
            if recipes[i].ingredients != before { recipes[i].updatedAt = Date() }
        }
        extras[Household.conversionNotesKey] = "1"
        updatedAt = Date()
        return true
    }
}

extension Recipe {
    /// Lines whose amount the AI filled in.
    public var guessedCount: Int { ingredients.filter(\.isGuessed).count }

    /// Puts a converted line back to what the recipe said.
    public func undoingConversion(of id: UUID) -> Recipe {
        var r = self
        guard let i = r.ingredients.firstIndex(where: { $0.id == id }), let from = r.ingredients[i].convertedFrom else { return self }
        r.ingredients[i].quantity = from
        r.ingredients[i].convertedFrom = nil
        if from.unit == .piece { r.ingredients[i].name = Plural.fit(r.ingredients[i].name, to: from.amount) }
        r.updatedAt = Date()
        return r
    }

    /// Accepts a line as it is: hides its converted-from note and its guessed marker.
    public func confirming(_ id: UUID) -> Recipe {
        var r = self
        guard let i = r.ingredients.firstIndex(where: { $0.id == id }) else { return self }
        r.ingredients[i].convertedFrom = nil
        r.ingredients[i].amountGuessed = nil
        r.updatedAt = Date()
        return r
    }

    /// Sets a line's amount from what was typed ("3", "40g", "2 tbsp"). Nil when it can't be read.
    public func settingAmount(of id: UUID, to text: String) -> Recipe? {
        guard let i = ingredients.firstIndex(where: { $0.id == id }) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let q = IngredientParser.parse("\(trimmed) \(ingredients[i].name)")?.quantity else { return nil }
        var r = self
        r.ingredients[i].quantity = r.ingredients[i].foodId.flatMap { FoodDatabase.food($0) }.map { food in
            q.unit == .piece && UnitStandard.cloveFoods.contains(food.id) ? Quantity(q.amount, .clove) : q
        } ?? q
        r.ingredients[i].convertedFrom = nil
        r.ingredients[i].amountGuessed = nil
        r.updatedAt = Date()
        return r
    }
}
