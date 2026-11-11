import Foundation

/// What a recipe needs, in the food's own unit.
public struct Need: Hashable, Sendable {
    /// Stable key for adding needs together: the food id, or the ingredient's name when it isn't a known food.
    public var key: String
    public var foodId: String?
    public var name: String
    /// Nil for "salt to taste" and other lines with no amount.
    public var amount: Double?
    public var unit: BaseUnit?
    public var optional: Bool
    public var isStaple: Bool

    public var food: Food? { FoodDatabase.food(foodId) }
}

public enum Nutrition {
    /// What the recipe needs for the given number of servings.
    public static func needs(_ recipe: Recipe, servings: Int? = nil) -> [Need] {
        let factor = Double(servings ?? recipe.servings) / Double(max(1, recipe.servings))
        return recipe.ingredients.map { ing in
            let food = FoodDatabase.food(ing.foodId)
            var amount: Double?
            var unit: BaseUnit?
            if let q = ing.quantity {
                let scaled = Quantity(q.amount * factor, q.unit)
                if let food {
                    amount = Units.amountInFoodUnit(scaled, food: food)
                    unit = food.unit
                    if amount == nil {
                        // Can't convert to the food's unit (e.g. grams of something kept by count with no weight): keep as written.
                        amount = scaled.amount * scaled.unit.factor; unit = scaled.unit.base
                    }
                } else {
                    amount = scaled.amount * scaled.unit.factor
                    unit = scaled.unit.base
                }
            }
            return Need(key: ing.foodId ?? "name:" + ing.name.lowercased(), foodId: ing.foodId, name: food?.name ?? ing.name,
                        amount: amount, unit: unit, optional: ing.optional, isStaple: food?.isStaple ?? false)
        }
    }

    /// Macros for the whole recipe worked out from its ingredients, and the share of ingredients that could be counted.
    public static func computed(_ recipe: Recipe) -> (total: Macros, coverage: Double) {
        var total = Macros.zero
        var counted = 0
        var countable = 0
        for ing in recipe.ingredients {
            let food = FoodDatabase.food(ing.foodId)
            if food?.isStaple == true && food?.id != "olive-oil" { continue }
            countable += 1
            guard let food, let q = ing.quantity, let g = Units.grams(q, food: food) else { continue }
            total += food.per100 * (g / 100)
            counted += 1
        }
        return (total, countable == 0 ? 1 : Double(counted) / Double(countable))
    }

    /// Per serving: what the creator stated if they gave it, otherwise worked out.
    public static func perServing(_ recipe: Recipe) -> Macros {
        if let s = recipe.statedPerServing, s.kcal > 0 { return s }
        return computed(recipe).total / Double(max(1, recipe.servings))
    }
}

/// Everything about what's in the kitchen: totals, using things up, expiry and running low.
public enum Kitchen {
    /// Total of each known food, in the food's unit. Unknown items are keyed "name:<lowercased name>".
    public static func stock(_ inventory: [InventoryItem]) -> [String: Double] {
        var out: [String: Double] = [:]
        for item in inventory where item.amount > 0 {
            if let food = FoodDatabase.food(item.foodId) {
                let v = Units.convert(item.amount, from: item.unit, to: food.unit, food: food) ?? item.amount
                out[food.id, default: 0] += v
            } else {
                out["name:" + item.name.lowercased(), default: 0] += item.amount
            }
        }
        return out
    }

    public static func defaultExpiry(for food: Food?, location: StorageLocation, from now: Date) -> Date? {
        guard var days = food?.shelfLifeDays else { return nil }
        if location == .freezer { days = max(days, 90) }
        if days > 3000 { return nil }
        return Calendar.plate.date(byAdding: .day, value: days, to: Calendar.plate.startOfDay(for: now))
    }

    /// Takes what was used out of the kitchen, soonest-to-expire first, and returns what was used.
    @discardableResult
    public static func use(_ needs: [Need], from inventory: inout [InventoryItem], now: Date) -> [UsageRecord] {
        var used: [UsageRecord] = []
        for need in needs {
            guard var remaining = need.amount, remaining > 0, !need.isStaple || need.foodId == "olive-oil" else { continue }
            let total = remaining
            let indices = inventory.indices.filter { i in
                if let id = need.foodId { return inventory[i].foodId == id }
                return inventory[i].foodId == nil && inventory[i].name.lowercased() == need.name.lowercased()
            }.sorted { (inventory[$0].expiry ?? .distantFuture) < (inventory[$1].expiry ?? .distantFuture) }
            let food = need.food
            for i in indices where remaining > 1e-6 {
                let needUnit = need.unit ?? inventory[i].unit
                // Amount of this item in the need's unit.
                guard let have = Units.convert(inventory[i].amount, from: inventory[i].unit, to: needUnit, food: food) else { continue }
                let take = min(have, remaining)
                remaining -= take
                let left = have - take
                inventory[i].amount = Units.convert(left, from: needUnit, to: inventory[i].unit, food: food) ?? 0
                inventory[i].updatedAt = now
            }
            if let id = need.foodId, let unit = need.unit {
                used.append(UsageRecord(foodId: id, amount: total - max(0, remaining), unit: unit, date: now))
            }
        }
        inventory.removeAll { $0.amount <= 0.01 }
        return used.filter { $0.amount > 0 }
    }

    /// Adds bought or scanned food, merging with a matching item that has the same expiry day and place.
    public static func add(_ item: InventoryItem, to inventory: inout [InventoryItem]) {
        let cal = Calendar.plate
        if let i = inventory.firstIndex(where: {
            $0.foodId != nil && $0.foodId == item.foodId && $0.location == item.location && $0.unit == item.unit &&
            ($0.expiry.map { cal.startOfDay(for: $0) } == item.expiry.map { cal.startOfDay(for: $0) })
        }) {
            inventory[i].amount += item.amount
            inventory[i].updatedAt = item.addedAt
        } else {
            inventory.append(item)
        }
    }

    public static func expiringSoon(_ inventory: [InventoryItem], within days: Int = 3, now: Date) -> [InventoryItem] {
        let limit = Calendar.plate.date(byAdding: .day, value: days, to: Calendar.plate.startOfDay(for: now))!
        return inventory.filter { ($0.expiry ?? .distantFuture) < limit }.sorted { ($0.expiry ?? .distantFuture) < ($1.expiry ?? .distantFuture) }
    }

    public struct LowStock: Hashable, Sendable {
        public var foodId: String
        public var have: Double
        public var perDay: Double
        /// Nil when there's none left.
        public var daysLeft: Double?
    }

    /// Foods you've used in the last four weeks that will run out within `days` at the rate you're going.
    public static func runningLow(_ inventory: [InventoryItem], usage: [UsageRecord], now: Date, days: Double = 4) -> [LowStock] {
        let since = now.addingTimeInterval(-28 * 86400)
        var used: [String: Double] = [:]
        var first: [String: Date] = [:]
        for u in usage where u.date >= since {
            guard let food = FoodDatabase.food(u.foodId), !food.isStaple else { continue }
            used[u.foodId, default: 0] += Units.convert(u.amount, from: u.unit, to: food.unit, food: food) ?? u.amount
            first[u.foodId] = min(first[u.foodId] ?? u.date, u.date)
        }
        let stock = stock(inventory)
        var out: [LowStock] = []
        for (id, total) in used {
            // Average over the time we've been watching, at least a week, so one big cook doesn't look like a habit.
            let span = max(7, now.timeIntervalSince(first[id]!) / 86400)
            let perDay = total / span
            let have = stock[id] ?? 0
            if have <= 0 { out.append(LowStock(foodId: id, have: 0, perDay: perDay, daysLeft: nil)); continue }
            let left = have / perDay
            if left < days { out.append(LowStock(foodId: id, have: have, perDay: perDay, daysLeft: left)) }
        }
        return out.sorted { ($0.daysLeft ?? -1) < ($1.daysLeft ?? -1) }
    }
}
