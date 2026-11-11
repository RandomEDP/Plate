import Foundation

public struct PackPick: Hashable, Sendable {
    public var option: PackOption
    public var count: Int
    public var label: String { "\(count) × \(Format.amount(option.size, .g).replacingOccurrences(of: " g", with: "g"))" }
}

/// One line of a shopping list: everything the chosen meals need of one food, added together.
public struct ShoppingLine: Hashable, Sendable, Identifiable {
    public var id: String { key }
    public var key: String
    public var foodId: String?
    public var name: String
    public var category: FoodCategory
    /// Total the meals need (nil when no amounts were given, e.g. "salt to taste").
    public var need: Double?
    public var unit: BaseUnit?
    public var inStock: Double
    public var toBuy: Double?
    public var packs: [PackPick]
    public var cost: Double?
    /// How much the chosen packs save against buying the smallest pack several times.
    public var saving: Double?
    public var savingNote: String?
    public var meals: [String]
    public var store: Store?

    public var alreadyHave: Bool { (toBuy ?? 1) <= 0 }

    /// "2 × 1kg (Sainsbury's)" or "600 g".
    public var buyText: String {
        if !packs.isEmpty {
            let unit = unit ?? .g
            return packs.map { "\($0.count) × \(Format.amount($0.option.size, unit))" }.joined(separator: " + ")
        }
        if let toBuy, let unit, toBuy > 0 { return Format.amount(toBuy, unit) }
        return ""
    }
}

public struct ShoppingResult: Sendable {
    public var lines: [ShoppingLine]
    public var totalCost: Double
    public var totalSaving: Double
    public var toBuy: [ShoppingLine] { lines.filter { !$0.alreadyHave } }
    public var covered: [ShoppingLine] { lines.filter(\.alreadyHave) }
    public func cost(at store: Store) -> Double { lines.filter { $0.store == store }.compactMap(\.cost).reduce(0, +) }
}

public enum ShoppingBuilder {
    /// Builds a list from the chosen meals (each recipe and how many portions) plus anything added by hand.
    public static func build(meals: [(Recipe, Int)], manual: [ManualItem] = [], inventory: [InventoryItem],
                             stores: [Store], useKitchen: Bool = true) -> ShoppingResult {
        struct Acc { var need: Need; var amount: Double?; var meals: [String] }
        var acc: [String: Acc] = [:]
        var order: [String] = []
        func add(_ need: Need, meal: String?) {
            if need.isStaple || (need.optional && need.amount == nil) { return }
            if var a = acc[need.key] {
                if let amount = need.amount {
                    // Different units for the same unknown item can't be added: keep the first unit.
                    if a.need.unit == need.unit || a.amount == nil { a.amount = (a.amount ?? 0) + amount; a.need.unit = need.unit }
                }
                if let meal, !a.meals.contains(meal) { a.meals.append(meal) }
                acc[need.key] = a
            } else {
                acc[need.key] = Acc(need: need, amount: need.amount, meals: meal.map { [$0] } ?? [])
                order.append(need.key)
            }
        }
        for (recipe, servings) in meals {
            for need in Nutrition.needs(recipe, servings: servings) { add(need, meal: recipe.name) }
        }
        for item in manual {
            let food = FoodDatabase.food(item.foodId) ?? FoodMatcher.match(item.name)
            var amount = item.amount
            var unit = item.unit
            if let food, let a = amount, let u = unit { amount = Units.convert(a, from: u, to: food.unit, food: food) ?? a; unit = food.unit }
            // "Bananas" with no amount: one of the smallest pack.
            if let food, amount == nil, let smallest = food.packs.filter({ stores.contains($0.store) }).map(\.size).min() ?? food.packs.map(\.size).min() {
                amount = smallest; unit = food.unit
            }
            add(Need(key: food?.id ?? "name:" + item.name.lowercased(), foodId: food?.id, name: food?.name ?? item.name,
                     amount: amount, unit: unit ?? food?.unit, optional: false, isStaple: false), meal: nil)
        }

        let stock = useKitchen ? Kitchen.stock(inventory) : [:]
        var lines: [ShoppingLine] = []
        for key in order {
            guard let a = acc[key] else { continue }
            let food = a.need.food
            let have = stock[key] ?? 0
            var toBuy: Double? = a.amount.map { max(0, $0 - have) }
            if a.amount == nil { toBuy = have > 0 ? 0 : nil }
            var line = ShoppingLine(key: key, foodId: food?.id, name: food?.name ?? a.need.name,
                                    category: food?.category ?? .other, need: a.amount, unit: a.need.unit,
                                    inStock: have, toBuy: toBuy, packs: [], cost: nil, saving: nil, savingNote: nil,
                                    meals: a.meals, store: nil)
            if let food, let buy = toBuy, buy > 0 {
                let options = food.packs.filter { stores.contains($0.store) }
                if let best = bestPacks(need: buy, options: options, perishable: food.isPerishable) {
                    line.packs = best.picks
                    line.cost = best.cost
                    line.store = best.picks.first?.option.store
                    if let base = baseline(need: buy, options: options), base - best.cost >= 0.10,
                       best.picks.contains(where: { $0.option.size > (options.map(\.size).min() ?? 0) }) {
                        line.saving = base - best.cost
                        let smallest = options.min { $0.size < $1.size }!
                        let n = Int((buy / smallest.size).rounded(.up))
                        line.savingNote = "Bulk buy saves \(Format.money(base - best.cost)) against \(n) × \(Format.amount(smallest.size, food.unit)) at \(smallest.store.title)"
                    }
                }
            }
            lines.append(line)
        }
        lines.sort { a, b in
            if (a.store?.rawValue ?? "zz") != (b.store?.rawValue ?? "zz") { return (a.store?.rawValue ?? "zz") < (b.store?.rawValue ?? "zz") }
            if a.category != b.category { return FoodCategory.allCases.firstIndex(of: a.category)! < FoodCategory.allCases.firstIndex(of: b.category)! }
            return a.name < b.name
        }
        return ShoppingResult(lines: lines, totalCost: lines.compactMap(\.cost).reduce(0, +),
                              totalSaving: lines.compactMap(\.saving).reduce(0, +))
    }

    /// The cheapest packs that cover the amount, allowing for waste: buying more than you need of something that goes
    /// off quickly costs most of the extra, while extra rice or tins only costs a little (it'll get used).
    public static func bestPacks(need: Double, options: [PackOption], perishable: Bool) -> (picks: [PackPick], cost: Double)? {
        guard need > 0, !options.isEmpty else { return nil }
        // Work in whole units of a step that keeps the table small.
        let maxSize = options.map(\.size).max()!
        // Whole units (grams, ml, pieces) unless the amounts are huge; then coarser steps, rounding pack sizes down so
        // the packs chosen always cover the need.
        let step = max(1, ((need + maxSize) / 50000).rounded(.up))
        let target = Int((need / step).rounded(.up))
        let sizes = options.map { max(1, Int(($0.size / step).rounded(.down))) }
        let limit = target + sizes.max()!
        var cost = [Double](repeating: .infinity, count: limit + 1)
        var choice = [Int](repeating: -1, count: limit + 1)
        cost[0] = 0
        for t in 1...limit {
            for (i, sz) in sizes.enumerated() where sz <= t && cost[t - sz] + options[i].price < cost[t] {
                cost[t] = cost[t - sz] + options[i].price
                choice[t] = i
            }
        }
        let wasteRate = perishable ? 0.8 : 0.1
        var bestT = -1
        var bestScore = Double.infinity
        for t in target...limit where cost[t].isFinite {
            let extra = Double(t - target) * step
            // Price of the extra at the dearest per-unit rate among the packs used.
            let unitPrice = cost[t] / (Double(t) * step)
            let score = cost[t] + extra * unitPrice * wasteRate
            if score < bestScore - 1e-9 { bestScore = score; bestT = t }
        }
        guard bestT > 0 else { return nil }
        var counts: [Int: Int] = [:]
        var t = bestT
        while t > 0, choice[t] >= 0 { counts[choice[t], default: 0] += 1; t -= sizes[choice[t]] }
        let picks = counts.map { PackPick(option: options[$0.key], count: $0.value) }
            .sorted { $0.option.size > $1.option.size }
        return (picks, cost[bestT])
    }

    /// What it would cost buying only the smallest pack (the "no bulk" price).
    static func baseline(need: Double, options: [PackOption]) -> Double? {
        guard let smallest = options.min(by: { $0.size < $1.size }) else { return nil }
        return Double(Int((need / smallest.size).rounded(.up))) * smallest.price
    }

    /// Turns ticked lines into kitchen items once the shopping is put away.
    public static func purchases(_ lines: [ShoppingLine], now: Date) -> [InventoryItem] {
        lines.compactMap { line in
            let food = FoodDatabase.food(line.foodId)
            let bought = line.packs.isEmpty ? (line.toBuy ?? line.need ?? 0) : line.packs.reduce(0) { $0 + $1.option.size * Double($1.count) }
            guard bought > 0 || food == nil else { return nil }
            let location = food?.storage ?? .cupboard
            return InventoryItem(foodId: food?.id, name: food?.name ?? line.name, amount: max(bought, food == nil ? 1 : 0),
                                 unit: food?.unit ?? line.unit ?? .piece, location: location,
                                 expiry: Kitchen.defaultExpiry(for: food, location: location, from: now), addedAt: now)
        }
    }
}
