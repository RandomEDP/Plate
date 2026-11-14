import Foundation

/// A small seeded random number generator, so "shuffle" gives a new plan but tests are repeatable.
public struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    public mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Builds a week of meals: the number of breakfasts, lunches, dinners and snacks you asked for, for everyone,
/// picking recipes that use what's already in, share ingredients with each other, and suit batch cooking.
public enum Planner {
    public struct Options: Sendable {
        public var settings: PlanSettings
        public var seed: UInt64
        /// Entries to keep as they are (locked by the person).
        public var keep: [PlanEntry]
        /// Calories per person per day, to steer portion-heavy picks.
        public var dailyKcal: Double?
        public init(settings: PlanSettings, seed: UInt64 = 1, keep: [PlanEntry] = [], dailyKcal: Double? = nil) {
            self.settings = settings; self.seed = seed; self.keep = keep; self.dailyKcal = dailyKcal
        }
    }

    /// Which days a meal goes on: every day if 7, otherwise spread from Monday (lunches 5 → Mon–Fri).
    public static func days(for count: Int) -> [Int] {
        let n = max(0, min(count, 14))
        if n == 0 { return [] }
        if n <= 7 { return Array(0..<n) }
        // More than one a day (snacks): repeat days.
        return (0..<n).map { $0 % 7 }.sorted()
    }

    public static func generate(recipes: [Recipe], inventory: [InventoryItem], options: Options, now: Date) -> [PlanEntry] {
        var rng = SeededRandom(seed: options.seed)
        let stock = Kitchen.stock(inventory)
        let expiring = Set(Kitchen.expiringSoon(inventory, within: 4, now: now).compactMap(\.foodId))
        let people = max(1, options.settings.people)
        var entries: [PlanEntry] = options.keep
        var pickedFoods: [String: Int] = [:]
        for e in options.keep {
            if let r = recipes.first(where: { $0.id == e.recipeId }) { note(r, into: &pickedFoods) }
        }
        var usedRecipes = Set(options.keep.map(\.recipeId))

        // Dinners first: they drive most of the shop, and lunches can then share their ingredients.
        for meal in [MealType.dinner, .lunch, .breakfast, .snack] {
            let slotDays = days(for: options.settings.count(meal))
            let keptDays = Set(options.keep.filter { $0.meal == meal }.map(\.day))
            let freeDays = slotDays.filter { !keptDays.contains($0) }
            if freeDays.isEmpty { continue }
            let variety = max(1, min(options.settings.variety(meal), freeDays.count))
            let pool = recipes.filter { $0.fits(meal) }  // never a sauce on its own
            if pool.isEmpty { continue }

            var chosen: [Recipe] = []
            for _ in 0..<variety {
                let candidates = pool.filter { !usedRecipes.contains($0.id) }
                let from = candidates.isEmpty ? pool : candidates
                let target = options.dailyKcal.map { $0 * share(meal) }
                let scored = from.map { r -> (Double, Recipe) in
                    (score(r, servings: people, stock: stock, expiring: expiring, picked: pickedFoods,
                           batch: freeDays.count > variety, kcalTarget: target) + Double.random(in: 0..<1.2, using: &rng), r)
                }
                guard let best = scored.max(by: { $0.0 < $1.0 })?.1 else { break }
                chosen.append(best)
                usedRecipes.insert(best.id)
                note(best, into: &pickedFoods)
            }
            // Give each recipe a run of consecutive days, so one cook covers several meals.
            let perRecipe = split(freeDays.count, into: chosen.count)
            var dayIndex = 0
            for (r, n) in zip(chosen, perRecipe) {
                for _ in 0..<n {
                    entries.append(PlanEntry(day: freeDays[dayIndex], meal: meal, recipeId: r.id, servings: people))
                    dayIndex += 1
                }
            }
        }
        return entries.sorted { ($0.day, order($0.meal)) < ($1.day, order($1.meal)) }
    }

    static func order(_ m: MealType) -> Int {
        switch m { case .breakfast: return 0; case .lunch: return 1; case .dinner: return 2; case .snack: return 3 }
    }

    static func share(_ m: MealType) -> Double {
        switch m { case .breakfast: return 0.25; case .lunch: return 0.3; case .dinner: return 0.35; case .snack: return 0.1 }
    }

    /// Splits n days between k recipes as evenly as possible, bigger runs first (7 into 3 → 3, 2, 2).
    public static func split(_ n: Int, into k: Int) -> [Int] {
        guard k > 0 else { return [] }
        let base = n / k, extra = n % k
        return (0..<k).map { $0 < extra ? base + 1 : base }
    }

    static func note(_ r: Recipe, into picked: inout [String: Int]) {
        for ing in r.ingredients {
            if let id = ing.foodId, FoodDatabase.food(id)?.isStaple != true { picked[id, default: 0] += 1 }
        }
    }

    static func score(_ r: Recipe, servings: Int, stock: [String: Double], expiring: Set<String>, picked: [String: Int],
                      batch: Bool, kcalTarget: Double?) -> Double {
        let match = Suggestions.evaluate(r, servings: servings, stock: stock)
        let foods = Set(r.ingredients.compactMap(\.foodId).filter { FoodDatabase.food($0)?.isStaple != true })
        let overlap = foods.isEmpty ? 0 : Double(foods.filter { picked[$0] != nil }.count) / Double(foods.count)
        let usesExpiring = Double(foods.filter { expiring.contains($0) }.count)
        var s = match.coverage * 3 + overlap * 2 + usesExpiring * 1.5
        if r.isFavourite { s += 1 }
        // Dishes you rated well come round more often; ones you didn't like, less.
        if let stars = r.rating { s += Double(min(5, max(1, stars)) - 3) * 0.4 }
        if batch && r.mealPrepFriendly { s += 0.6 }
        if let target = kcalTarget, target > 0 {
            let kcal = Nutrition.perServing(r).kcal
            if kcal > 0 { s -= min(1.5, abs(kcal - target) / target * 2) }
        }
        return s
    }
}
