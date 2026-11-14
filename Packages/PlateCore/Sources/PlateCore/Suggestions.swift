import Foundation

/// How well a recipe fits what's in the kitchen.
public struct RecipeMatch: Hashable, Sendable, Identifiable {
    public var id: UUID { recipe.id }
    public var recipe: Recipe
    public var servings: Int
    /// Needed and none in the kitchen.
    public var missing: [Need]
    /// Some in the kitchen, but not enough.
    public var short: [Need]
    /// Share of the main ingredients you have enough of (0...1).
    public var coverage: Double
    /// How many ingredients it uses that go off within three days.
    public var usesExpiring: Int

    public var canCookNow: Bool { missing.isEmpty && short.isEmpty }
    public var missingCount: Int { missing.count + short.count }
}

public enum Suggestions {
    /// Close enough to count as having it (a recipe asking for 400 g when you've got 380 g).
    static let tolerance = 0.9

    public static func evaluate(_ recipe: Recipe, servings: Int? = nil, stock: [String: Double], expiring: Set<String> = []) -> RecipeMatch {
        let s = servings ?? recipe.servings
        var missing: [Need] = []
        var short: [Need] = []
        var covered = 0
        var counted = 0
        var usesExpiring = 0
        for need in Nutrition.needs(recipe, servings: s) {
            if need.isStaple || need.optional { continue }
            counted += 1
            let have = stock[need.key] ?? 0
            if expiring.contains(need.key) { usesExpiring += 1 }
            if let amount = need.amount, amount > 0 {
                if have >= amount * tolerance { covered += 1 }
                else if have > 0 { short.append(need) }
                else { missing.append(need) }
            } else {
                if have > 0 { covered += 1 } else { missing.append(need) }
            }
        }
        return RecipeMatch(recipe: recipe, servings: s, missing: missing, short: short,
                           coverage: counted == 0 ? 1 : Double(covered) / Double(counted), usesExpiring: usesExpiring)
    }

    /// Recipes ranked by how ready you are to cook them, favouring ones that use up food about to go off.
    public static func rank(_ recipes: [Recipe], inventory: [InventoryItem], servings: Int? = nil, now: Date,
                            mealType: MealType? = nil) -> [RecipeMatch] {
        let stock = Kitchen.stock(inventory)
        let expiring = Set(Kitchen.expiringSoon(inventory, within: 3, now: now).map { $0.foodId ?? "name:" + $0.name.lowercased() })
        return recipes
            .filter { mealType == nil || $0.fits(mealType!) }
            .map { evaluate($0, servings: servings, stock: stock, expiring: expiring) }
            .sorted { a, b in
                if a.canCookNow != b.canCookNow { return a.canCookNow }
                if a.missingCount != b.missingCount { return a.missingCount < b.missingCount }
                if a.usesExpiring != b.usesExpiring { return a.usesExpiring > b.usesExpiring }
                if a.coverage != b.coverage { return a.coverage > b.coverage }
                if a.recipe.isFavourite != b.recipe.isFavourite { return a.recipe.isFavourite }
                return a.recipe.name < b.recipe.name
            }
    }
}

/// A recipe changed to use something you have instead of something you don't.
public struct Variation: Hashable, Sendable, Identifiable {
    public var id: String { recipe.name }
    public var recipe: Recipe
    public var swaps: [Swap]

    public struct Swap: Hashable, Sendable {
        public var from: String
        public var to: String
    }
}

public enum Variations {
    /// Short names used in titles when a swap is made.
    static let shortNames: [String: String] = [
        "chicken-breast": "Chicken", "chicken-thigh": "Chicken thigh", "turkey-breast": "Turkey", "prawns": "Prawn",
        "tofu": "Tofu", "halloumi": "Halloumi", "beef-mince": "Beef", "turkey-mince": "Turkey", "pork-mince": "Pork",
        "lamb-mince": "Lamb", "salmon": "Salmon", "cod": "Cod", "mackerel": "Mackerel", "rice": "Rice",
        "microwave-rice": "Rice", "brown-rice": "Brown rice", "couscous": "Couscous", "quinoa": "Quinoa", "pasta": "Pasta",
        "spaghetti": "Spaghetti", "egg-noodles": "Noodle", "rice-noodles": "Rice noodle", "potatoes": "Potato",
        "sweet-potato": "Sweet potato", "wraps": "Wrap", "pitta": "Pitta", "naan": "Naan", "chickpeas": "Chickpea",
        "kidney-beans": "Kidney bean", "black-beans": "Bean", "red-lentils": "Lentil",
    ]
    /// Groups worth swapping for a whole new dish (the main ingredient), rather than small changes.
    static let mainGroups: Set<String> = ["protein", "mince", "fish", "grain", "pasta", "noodle", "starch", "beans", "flatbread"]

    /// Variations of a recipe using foods from the same group that you have in. Swaps the missing ingredients first,
    /// then offers a different main ingredient (chicken → prawns) for some variety.
    public static func of(_ recipe: Recipe, inventory: [InventoryItem], limit: Int = 4) -> [Variation] {
        let stock = Kitchen.stock(inventory)
        let needs = Nutrition.needs(recipe)
        var out: [Variation] = []

        func candidates(for food: Food) -> [Food] {
            guard let group = food.swapGroup else { return [] }
            return FoodDatabase.all.filter { $0.swapGroup == group && $0.id != food.id }
        }

        // 1. Use what you've got: swap every missing ingredient that has an in-stock alternative.
        var swaps: [(String, Food)] = []
        for need in needs where !need.isStaple && !need.optional {
            guard let food = need.food, (stock[food.id] ?? 0) < (need.amount ?? 1) * Suggestions.tolerance else { continue }
            let options = candidates(for: food).filter { (stock[$0.id] ?? 0) > 0 }
                .sorted { (stock[$0.id] ?? 0) > (stock[$1.id] ?? 0) }
            if let pick = options.first { swaps.append((food.id, pick)) }
        }
        if !swaps.isEmpty {
            out.append(make(recipe, swaps: swaps))
        }

        // 2. Different main ingredient, from what you have first, then anything in the group.
        for need in needs where !need.isStaple {
            guard let food = need.food, let group = food.swapGroup, mainGroups.contains(group) else { continue }
            let options = candidates(for: food).sorted { a, b in
                let ha = (stock[a.id] ?? 0) > 0, hb = (stock[b.id] ?? 0) > 0
                if ha != hb { return ha }
                return (shortNames[a.id] != nil) && (shortNames[b.id] == nil)
            }
            for pick in options.prefix(3) where shortNames[pick.id] != nil {
                let v = make(recipe, swaps: [(food.id, pick)])
                if !out.contains(where: { $0.recipe.name == v.recipe.name }) { out.append(v) }
            }
        }
        return Array(out.prefix(limit))
    }

    static func make(_ recipe: Recipe, swaps: [(String, Food)]) -> Variation {
        var r = recipe
        r.id = UUID()
        r.source = RecipeSource(kind: .variation, url: recipe.source.url, author: recipe.name)
        r.statedPerServing = nil
        r.isFavourite = false
        var done: [Variation.Swap] = []
        var name = recipe.name
        for (fromId, to) in swaps {
            guard let from = FoodDatabase.food(fromId) else { continue }
            for i in r.ingredients.indices where r.ingredients[i].foodId == fromId {
                var ing = r.ingredients[i]
                // Keep the same weight where possible (200 g chicken → 200 g prawns).
                if let q = ing.quantity, let g = Units.grams(q, food: from) {
                    if to.unit == .piece, let pg = to.gramsPerPiece {
                        ing.quantity = Quantity((g / pg).rounded(.up), .piece)
                    } else {
                        ing.quantity = Quantity(g.rounded(), .g)
                    }
                }
                ing.foodId = to.id
                ing.name = to.name.lowercased()
                r.ingredients[i] = ing
            }
            r.steps = r.steps.map { replaceWord(in: $0, from: from, to: to) }
            let oldShort = shortNames[fromId] ?? from.name
            let newShort = shortNames[to.id] ?? to.name
            if let range = name.range(of: oldShort, options: .caseInsensitive) {
                name.replaceSubrange(range, with: newShort)
            } else if mainGroups.contains(from.swapGroup ?? "") {
                name += " with \(newShort.lowercased())"
            }
            done.append(.init(from: from.name, to: to.name))
        }
        if name == recipe.name { name += " (my version)" }
        r.name = name
        return Variation(recipe: r, swaps: done)
    }

    static func replaceWord(in text: String, from: Food, to: Food) -> String {
        let candidates = ([from.name] + from.aliases).sorted { $0.count > $1.count }
        var out = text
        for c in candidates {
            if let range = out.range(of: c, options: .caseInsensitive) {
                out.replaceSubrange(range, with: to.name.lowercased())
                break
            }
        }
        return out
    }
}
