import XCTest
@testable import PlateCore

final class KitchenTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_794_000_000) // Nov 2026
    func day(_ n: Int) -> Date { now.addingTimeInterval(Double(n) * 86400) }
    func item(_ id: String, _ amount: Double, expires: Int? = nil) -> InventoryItem {
        let f = FoodDatabase.byId[id]!
        return InventoryItem(foodId: id, name: f.name, amount: amount, unit: f.unit, location: f.storage, expiry: expires.map(day), addedAt: now)
    }
    func recipe(_ name: String) -> Recipe { BuiltInRecipes.all.first { $0.name == name }! }

    func testUsingFoodTakesSoonestFirst() {
        var inv = [item("chicken-breast", 1000, expires: 5), item("chicken-breast", 500, expires: 1)]
        let used = Kitchen.use([Need(key: "chicken-breast", foodId: "chicken-breast", name: "Chicken", amount: 600, unit: .g, optional: false, isStaple: false)], from: &inv, now: now)
        XCTAssertEqual(inv.count, 1)
        XCTAssertEqual(inv[0].amount, 900, accuracy: 0.01)
        XCTAssertEqual(used.first?.amount ?? 0, 600, accuracy: 0.01)
    }

    func testCookingARecipeUsesItsIngredients() {
        let bol = recipe("Spaghetti bolognese")
        var inv = [item("beef-mince", 500), item("onion", 3), item("carrot", 1000), item("garlic", 10), item("chopped-tomatoes", 800),
                   item("tomato-puree", 200), item("spaghetti", 500), item("parmesan", 180), item("stock-cube", 10)]
        let match = Suggestions.evaluate(bol, stock: Kitchen.stock(inv))
        XCTAssertTrue(match.canCookNow, "missing \(match.missing.map(\.name)) short \(match.short.map(\.name))")
        Kitchen.use(Nutrition.needs(bol), from: &inv, now: now)
        XCTAssertNil(inv.first { $0.foodId == "beef-mince" }, "the mince should all be used")
        XCTAssertEqual(inv.first { $0.foodId == "onion" }!.amount, 2, accuracy: 0.01)
        XCTAssertEqual(inv.first { $0.foodId == "spaghetti" }!.amount, 200, accuracy: 0.01)
        XCTAssertEqual(inv.first { $0.foodId == "carrot" }!.amount, 840, accuracy: 0.01)
    }

    func testHalfARecipe() {
        let bol = recipe("Spaghetti bolognese")
        let needs = Nutrition.needs(bol, servings: 2)
        XCTAssertEqual(needs.first { $0.foodId == "beef-mince" }?.amount ?? 0, 250, accuracy: 0.01)
    }

    func testSuggestionsRankWhatYouCanCookFirst() {
        let inv = [item("eggs", 6), item("wholemeal-bread", 400), item("butter", 250), item("milk", 1000)]
        let ranked = Suggestions.rank(BuiltInRecipes.all, inventory: inv, now: now)
        XCTAssertEqual(ranked.first?.recipe.name, "Scrambled eggs on toast")
        XCTAssertTrue(ranked.first!.canCookNow)
        XCTAssertFalse(ranked.last!.canCookNow)
    }

    func testExpiringFoodBumpsARecipe() {
        let inv = [item("spinach", 200, expires: 1), item("salmon", 240), item("pasta", 500)]
        let ranked = Suggestions.rank(BuiltInRecipes.all, inventory: inv, now: now, mealType: .dinner)
        let top = ranked.prefix(5).map(\.recipe.name)
        XCTAssertTrue(top.contains("Prawn & chorizo pasta") || top.contains("Pesto chicken pasta") || top.contains("Chickpea & spinach curry"), "\(top)")
    }

    func testRunningLow() {
        let usage = (0..<14).map { UsageRecord(foodId: "milk", amount: 250, unit: .ml, date: day(-$0)) }
        let low = Kitchen.runningLow([item("milk", 500)], usage: usage, now: now)
        XCTAssertEqual(low.first?.foodId, "milk")
        XCTAssertEqual(low.first?.daysLeft ?? 0, 500 / (3500 / 13.0), accuracy: 0.2)
        XCTAssertTrue(Kitchen.runningLow([item("milk", 5000)], usage: usage, now: now).isEmpty)
    }

    func testVariationsSwapForWhatYouHave() {
        let stirFry = recipe("Chicken stir-fry")
        let inv = [item("prawns", 300), item("egg-noodles", 250), item("pepper", 2), item("broccoli", 350)]
        let vs = Variations.of(stirFry, inventory: inv)
        XCTAssertEqual(vs.first?.recipe.name, "Prawn stir-fry")
        XCTAssertEqual(vs.first?.swaps.first?.to, "King prawns")
        let swapped = vs.first!.recipe.ingredients.first { $0.foodId == "prawns" }
        XCTAssertEqual(swapped?.quantity?.amount, 300)
        XCTAssertNotEqual(vs.first!.recipe.id, stirFry.id)
        XCTAssertTrue(vs.first!.recipe.steps.contains { $0.contains("king prawns") })
    }

    func testVariationsOfferAlternatives() {
        let bol = recipe("Spaghetti bolognese")
        let vs = Variations.of(bol, inventory: [], limit: 6)
        let names = vs.map(\.recipe.name)
        XCTAssertTrue(names.contains { $0.lowercased().contains("turkey") }, "\(names)")
        XCTAssertTrue(names.contains { $0.lowercased().contains("lamb") }, "\(names)")
    }
}

final class PlannerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_794_000_000)

    func testWeekHasTheRightShape() {
        let settings = PlanSettings(people: 2, breakfasts: 7, lunches: 5, dinners: 7, snacks: 0, breakfastVariety: 2, lunchVariety: 1, dinnerVariety: 3)
        let plan = Planner.generate(recipes: BuiltInRecipes.all, inventory: [], options: .init(settings: settings, seed: 7), now: now)
        XCTAssertEqual(plan.filter { $0.meal == .breakfast }.count, 7)
        XCTAssertEqual(plan.filter { $0.meal == .lunch }.count, 5)
        XCTAssertEqual(plan.filter { $0.meal == .dinner }.count, 7)
        XCTAssertEqual(Set(plan.filter { $0.meal == .lunch }.map(\.day)), Set(0..<5))
        XCTAssertEqual(Set(plan.filter { $0.meal == .dinner }.map(\.recipeId)).count, 3)
        XCTAssertEqual(Set(plan.filter { $0.meal == .lunch }.map(\.recipeId)).count, 1)
        XCTAssertTrue(plan.allSatisfy { $0.servings == 2 })
        // Dinners come in runs: 3, 2, 2 consecutive days.
        let dinners = plan.filter { $0.meal == .dinner }.sorted { $0.day < $1.day }.map(\.recipeId)
        var runs: [Int] = []
        for (i, id) in dinners.enumerated() { if i > 0 && dinners[i - 1] == id { runs[runs.count - 1] += 1 } else { runs.append(1) } }
        XCTAssertEqual(runs, [3, 2, 2])
        // Recipes suit their slot.
        let byId = Dictionary(uniqueKeysWithValues: BuiltInRecipes.all.map { ($0.id, $0) })
        for e in plan { XCTAssertTrue(byId[e.recipeId]!.mealTypes.contains(e.meal)) }
    }

    func testPlansAreRepeatableAndShuffleChangesThem() {
        let s = PlanSettings()
        let a = Planner.generate(recipes: BuiltInRecipes.all, inventory: [], options: .init(settings: s, seed: 1), now: now).map(\.recipeId)
        let b = Planner.generate(recipes: BuiltInRecipes.all, inventory: [], options: .init(settings: s, seed: 1), now: now).map(\.recipeId)
        XCTAssertEqual(a, b)
        let others = (2...6).map { Planner.generate(recipes: BuiltInRecipes.all, inventory: [], options: .init(settings: s, seed: UInt64($0)), now: now).map(\.recipeId) }
        XCTAssertTrue(others.contains { $0 != a })
    }

    func testPlannerUsesWhatsInTheKitchen() {
        let f = FoodDatabase.byId["salmon"]!
        let inv = [InventoryItem(foodId: "salmon", name: f.name, amount: 480, unit: .g, location: .fridge, expiry: now.addingTimeInterval(86400), addedAt: now),
                   InventoryItem(foodId: "broccoli", name: "Broccoli", amount: 400, unit: .g, location: .fridge, addedAt: now)]
        let s = PlanSettings(people: 2, breakfasts: 0, lunches: 0, dinners: 4, dinnerVariety: 2)
        var hits = 0
        for seed in 1...10 {
            let plan = Planner.generate(recipes: BuiltInRecipes.all, inventory: inv, options: .init(settings: s, seed: UInt64(seed)), now: now)
            if plan.contains(where: { e in BuiltInRecipes.all.first { $0.id == e.recipeId }!.name.contains("salmon") }) { hits += 1 }
        }
        XCTAssertGreaterThanOrEqual(hits, 8)
    }

    func testLockedEntriesStay() {
        let keep = PlanEntry(day: 2, meal: .dinner, recipeId: BuiltInRecipes.all.first { $0.name == "Shepherd's pie" }!.id, servings: 1, locked: true)
        let plan = Planner.generate(recipes: BuiltInRecipes.all, inventory: [], options: .init(settings: PlanSettings(), keep: [keep]), now: now)
        XCTAssertEqual(plan.filter { $0.meal == .dinner }.count, 7)
        XCTAssertTrue(plan.contains(keep))
        XCTAssertEqual(plan.filter { $0.meal == .dinner && $0.day == 2 }.count, 1)
    }

    func testSplit() {
        XCTAssertEqual(Planner.split(7, into: 3), [3, 2, 2])
        XCTAssertEqual(Planner.split(5, into: 5), [1, 1, 1, 1, 1])
        XCTAssertEqual(Planner.days(for: 5), [0, 1, 2, 3, 4])
    }
}

final class ShoppingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_794_000_000)
    func recipe(_ name: String) -> Recipe { BuiltInRecipes.all.first { $0.name == name }! }

    func testOverlappingIngredientsAreAddedTogether() {
        let result = ShoppingBuilder.build(meals: [(recipe("Chicken fajitas"), 4), (recipe("Pesto chicken pasta"), 2)], inventory: [], stores: Store.allCases)
        let chicken = result.lines.first { $0.foodId == "chicken-breast" }!
        XCTAssertEqual(chicken.need ?? 0, 900, accuracy: 0.1)
        XCTAssertEqual(chicken.meals.count, 2)
        // Covered by packs, and at least as much as needed.
        let bought = chicken.packs.reduce(0) { $0 + $1.option.size * Double($1.count) }
        XCTAssertGreaterThanOrEqual(bought, 900)
        // Staples don't appear.
        XCTAssertNil(result.lines.first { $0.foodId == "salt" || $0.foodId == "spices" })
    }

    func testScalingForPeople() {
        let one = ShoppingBuilder.build(meals: [(recipe("Spaghetti bolognese"), 4)], inventory: [], stores: Store.allCases)
        let two = ShoppingBuilder.build(meals: [(recipe("Spaghetti bolognese"), 8)], inventory: [], stores: Store.allCases)
        XCTAssertEqual(two.lines.first { $0.foodId == "beef-mince" }!.need!, 2 * one.lines.first { $0.foodId == "beef-mince" }!.need!, accuracy: 0.01)
    }

    func testKitchenIsTakenOff() {
        let inv = [InventoryItem(foodId: "spaghetti", name: "Spaghetti", amount: 1000, unit: .g, location: .cupboard, addedAt: now),
                   InventoryItem(foodId: "beef-mince", name: "Mince", amount: 200, unit: .g, location: .fridge, addedAt: now)]
        let r = ShoppingBuilder.build(meals: [(recipe("Spaghetti bolognese"), 4)], inventory: inv, stores: Store.allCases)
        XCTAssertTrue(r.lines.first { $0.foodId == "spaghetti" }!.alreadyHave)
        XCTAssertEqual(r.lines.first { $0.foodId == "beef-mince" }!.toBuy ?? 0, 300, accuracy: 0.01)
        let without = ShoppingBuilder.build(meals: [(recipe("Spaghetti bolognese"), 4)], inventory: inv, stores: Store.allCases, useKitchen: false)
        XCTAssertFalse(without.lines.first { $0.foodId == "spaghetti" }!.alreadyHave)
    }

    func testBulkPacksWhenCheaper() {
        let food = FoodDatabase.byId["chopped-tomatoes"]!
        let best = ShoppingBuilder.bestPacks(need: 3200, options: food.packs.filter { $0.store == .sainsburys }, perishable: false)!
        XCTAssertEqual(best.cost, 4.00, accuracy: 0.001)
        XCTAssertEqual(best.picks.first?.option.size, 1600)
        // Through the builder: the saving is reported.
        var r = recipe("Chilli con carne")
        r.ingredients = r.ingredients.map { var i = $0; if i.foodId == "chopped-tomatoes" { i.quantity = Quantity(8, .can) }; return i }
        let res = ShoppingBuilder.build(meals: [(r, 4)], inventory: [], stores: [.sainsburys])
        let line = res.lines.first { $0.foodId == "chopped-tomatoes" }!
        XCTAssertEqual(line.saving ?? 0, 0.40, accuracy: 0.001)
        XCTAssertNotNil(line.savingNote)
        XCTAssertGreaterThan(res.totalSaving, 0.39)
    }

    func testCostcoWhenItWins() {
        // 2 kg of chicken: Costco's 2.3 kg pack (£15.49) vs 2 × 1 kg at Sainsbury's (£15.50), but chicken goes off,
        // so the extra 300 g counts against Costco. 4.5 kg tips it to two Costco packs.
        let chicken = FoodDatabase.byId["chicken-breast"]!
        let a = ShoppingBuilder.bestPacks(need: 2000, options: chicken.packs, perishable: true)!
        XCTAssertEqual(a.picks.map(\.option.store), [.sainsburys])
        let b = ShoppingBuilder.bestPacks(need: 4500, options: chicken.packs, perishable: true)!
        XCTAssertTrue(b.picks.contains { $0.option.store == .costco }, "\(b.picks)")
        // Only Sainsbury's allowed.
        let c = ShoppingBuilder.bestPacks(need: 4500, options: chicken.packs.filter { $0.store == .sainsburys }, perishable: true)!
        XCTAssertTrue(c.picks.allSatisfy { $0.option.store == .sainsburys })
        // Non-perishable bulk: 9 kg of rice → Costco 10 kg.
        let rice = FoodDatabase.byId["rice"]!
        let d = ShoppingBuilder.bestPacks(need: 9000, options: rice.packs, perishable: false)!
        XCTAssertEqual(d.picks.first?.option.store, .costco)
    }

    func testPacksAlwaysCoverTheNeed() {
        for food in FoodDatabase.all where !food.packs.isEmpty {
            for need in [1.0, 37, 250, 999, 2500, 12000] {
                guard let best = ShoppingBuilder.bestPacks(need: need, options: food.packs, perishable: food.isPerishable) else { XCTFail(food.id); continue }
                let total = best.picks.reduce(0) { $0 + $1.option.size * Double($1.count) }
                XCTAssertGreaterThanOrEqual(total + 1e-6, need * 0.999, "\(food.id) need \(need)")
            }
        }
    }

    func testManualItemsAndPutAway() {
        let r = ShoppingBuilder.build(meals: [], manual: [ManualItem(name: "Bananas"), ManualItem(name: "Kitchen roll")], inventory: [], stores: Store.allCases)
        XCTAssertEqual(r.lines.count, 2)
        XCTAssertEqual(r.lines.first { $0.foodId == "banana" }?.name, "Bananas")
        let bought = ShoppingBuilder.purchases(r.lines, now: now)
        XCTAssertEqual(bought.count, 2)
        XCTAssertEqual(bought.first { $0.foodId == nil }?.name, "Kitchen roll")
    }

    func testPutAwayAddsToKitchenWithExpiry() {
        let r = ShoppingBuilder.build(meals: [(recipe("Chicken stir-fry"), 2)], inventory: [], stores: Store.allCases)
        let items = ShoppingBuilder.purchases(r.lines, now: now)
        let chicken = items.first { $0.foodId == "chicken-breast" }!
        XCTAssertGreaterThanOrEqual(chicken.amount, 300)
        XCTAssertEqual(chicken.location, .fridge)
        XCTAssertNotNil(chicken.expiry)
        var inv: [InventoryItem] = []
        for i in items { Kitchen.add(i, to: &inv) }
        XCTAssertTrue(Suggestions.evaluate(recipe("Chicken stir-fry"), stock: Kitchen.stock(inv)).canCookNow)
    }

    func testHouseholdRoundTrips() throws {
        var h = Household()
        h.recipes = Array(BuiltInRecipes.all.prefix(3))
        h.lists = [ShoppingList(name: "Big shop", meals: [ListMeal(recipeId: h.recipes[0].id, servings: 2)], checked: ["rice"])]
        let data = try JSONEncoder().encode(h)
        let back = try JSONDecoder().decode(Household.self, from: data)
        XCTAssertEqual(back, h)
    }
}
