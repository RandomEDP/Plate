import Foundation
import Observation
import PlateCore
import SwiftUI

/// Everything the app shows, kept on the phone as one household file. Every change saves itself shortly after.
@MainActor
@Observable
final class AppModel {
    var household: Household {
        didSet { scheduleSave() }
    }
    /// A short message shown at the top of the screen ("Saved Chicken fajitas from TikTok").
    var banner: String?
    /// Reels and TikToks shared to Plate whose recipe is only in the video, waiting for a recording of it.
    var waitingVideos: [WaitingVideo] = []
    var selectedTab: Tab = .today
    /// The full-screen dashboard for an iPad on the wall.
    var showWall = false
    /// A recipe that has just arrived as a Plate link, shown so it can be looked over and saved.
    var arrived: Recipe?
    /// Pictures found for recipes that haven't been saved yet (a video still, a post's cover), by recipe id.
    @ObservationIgnored var foundPhotos: [UUID: FoundPhoto] = [:]

    enum Tab: Hashable { case today, kitchen, recipes, plan, shop, home }

    private var saveTask: Task<Void, Never>?

    init() {
        if let data = try? Data(contentsOf: SharedStorage.householdURL),
           var h = try? JSONDecoder.plate.decode(Household.self, from: data) {
            // Recipes saved before standard units (garlic in cloves and so on) are converted once.
            let converted = h.standardiseSavedRecipeUnitsOnce()
            // Sauces already saved are tagged once, so the Sauces filter has them from the start.
            if h.markSavedSaucesOnce() || converted { AppModel.write(h) }
            household = h
        } else {
            household = Household()
        }
        // The iPad opens on the home dashboard. Any device opens straight into wall mode if that's turned on for it.
        if UIDevice.current.userInterfaceIdiom == .pad { selectedTab = .home }
        showWall = UserDefaults.standard.bool(forKey: "wallModeOnLaunch")
        // Pictures of dishes whose recipes have been deleted are cleared out.
        let snapshot = household
        Task.detached(priority: .utility) { DishPhotos.tidy(snapshot) }
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = household
        saveTask = Task { [snapshot] in
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            AppModel.write(snapshot)
        }
    }

    nonisolated static func write(_ h: Household) {
        do {
            var copy = h
            copy.updatedAt = Date()
            let data = try JSONEncoder.plate.encode(copy)
            try data.write(to: SharedStorage.householdURL, options: .atomic)
        } catch {
            print("Plate couldn't save: \(error)")
        }
    }

    func saveNow() {
        saveTask?.cancel()
        AppModel.write(household)
    }

    // MARK: Recipes

    /// The built-in recipes still in the library, then the person's own, newest first.
    var recipes: [Recipe] {
        let own = household.recipes.sorted { $0.createdAt > $1.createdAt }
        let builtIn = BuiltInRecipes.all.filter { !household.hiddenBuiltIns.contains($0.id) }
            .map { r -> Recipe in
                var r = household.dressed(r)
                r.isFavourite = household.favouriteBuiltIns.contains(r.id)
                return r
            }
        return own + builtIn
    }

    func recipe(_ id: UUID) -> Recipe? {
        household.recipes.first { $0.id == id } ?? BuiltInRecipes.all.first { $0.id == id }.map { r in
            var r = household.dressed(r)
            r.isFavourite = household.favouriteBuiltIns.contains(r.id)
            return r
        }
    }

    func isBuiltIn(_ r: Recipe) -> Bool { r.source.kind == .builtIn }

    func save(_ recipe: Recipe) {
        var r = recipe
        r.updatedAt = Date()
        if isBuiltIn(r) {
            // Editing a built-in recipe makes it your own copy.
            if household.recipes.contains(where: { $0.id == r.id }) == false && BuiltInRecipes.all.contains(where: { $0.id == r.id }) {
                r.id = UUID()
                r.source = RecipeSource(kind: .manual)
                r.createdAt = Date()
            }
        }
        if let i = household.recipes.firstIndex(where: { $0.id == r.id }) {
            household.recipes[i] = r
        } else {
            household.recipes.append(r)
        }
        // A picture found while it was being imported (a still from the video, or the post's cover).
        if let found = foundPhotos.removeValue(forKey: recipe.id) { setPhoto(found.data, origin: found.origin, for: r.id) }
    }

    func toggleFavourite(_ r: Recipe) {
        if isBuiltIn(r) {
            if household.favouriteBuiltIns.contains(r.id) { household.favouriteBuiltIns.remove(r.id) }
            else { household.favouriteBuiltIns.insert(r.id) }
        } else if let i = household.recipes.firstIndex(where: { $0.id == r.id }) {
            household.recipes[i].isFavourite.toggle()
        }
    }

    func delete(_ r: Recipe) {
        household.deleteRecipes([r.id])
    }

    func delete(_ ids: Set<UUID>) {
        household.deleteRecipes(ids)
    }

    // MARK: Kitchen

    func add(_ item: InventoryItem) {
        Kitchen.add(item, to: &household.inventory)
    }

    func update(_ item: InventoryItem) {
        if let i = household.inventory.firstIndex(where: { $0.id == item.id }) {
            var it = item
            it.updatedAt = Date()
            household.inventory[i] = it
        }
    }

    func remove(_ ids: [UUID]) {
        household.inventory.removeAll { ids.contains($0.id) }
    }

    /// Marks an item as used up (thrown away or finished) and remembers it was used.
    func finish(_ item: InventoryItem) {
        if let id = item.foodId {
            household.usage.append(UsageRecord(foodId: id, amount: item.amount, unit: item.unit, date: Date()))
        }
        remove([item.id])
    }

    var stock: [String: Double] { Kitchen.stock(household.inventory) }

    // MARK: Cooking and eating

    /// Cooks a recipe: takes the ingredients out of the kitchen, remembers what was used, and logs the portions eaten.
    func cook(_ recipe: Recipe, portionsMade: Int, portionsEaten: Double, meal: MealType, useKitchen: Bool, on date: Date = Date()) {
        if useKitchen {
            let used = Kitchen.use(Nutrition.needs(recipe, servings: portionsMade), from: &household.inventory, now: date)
            household.usage.append(contentsOf: used)
        }
        if portionsEaten > 0 {
            log(recipe, portions: portionsEaten, meal: meal, on: date)
        }
        // Leftover portions go in the fridge as a ready meal.
        let leftover = Double(portionsMade) - portionsEaten
        if leftover >= 1 {
            let item = InventoryItem(foodId: nil, name: "\(recipe.name) (prepped)", amount: leftover.rounded(.down), unit: .piece,
                                     location: .fridge, expiry: Calendar.plate.date(byAdding: .day, value: 4, to: date), addedAt: date,
                                     customPer100: nil)
            household.inventory.append(item)
            household.preppedMeals[item.id] = recipe.id
        }
        // Tick it off the plan if it's there today.
        let today = dayIndex(for: date)
        if let i = household.plan.entries.firstIndex(where: { $0.recipeId == recipe.id && $0.day == today && !$0.cooked }) {
            household.plan.entries[i].cooked = true
        }
    }

    func log(_ recipe: Recipe, portions: Double, meal: MealType, on date: Date = Date()) {
        household.log.append(FoodLogEntry(date: date, meal: meal, title: recipe.name,
                                          macros: Nutrition.perServing(recipe) * portions, recipeId: recipe.id, portions: portions))
    }

    /// Eats one portion of a prepped meal from the fridge.
    func eatPrepped(_ item: InventoryItem, meal: MealType) {
        guard let recipeId = household.preppedMeals[item.id], let r = recipe(recipeId) else { return }
        log(r, portions: 1, meal: meal)
        if let i = household.inventory.firstIndex(where: { $0.id == item.id }) {
            household.inventory[i].amount -= 1
            if household.inventory[i].amount < 0.5 {
                household.inventory.remove(at: i)
                household.preppedMeals[item.id] = nil
            }
        }
    }

    func logQuick(title: String, macros: Macros, meal: MealType, on date: Date = Date()) {
        household.log.append(FoodLogEntry(date: date, meal: meal, title: title, macros: macros))
    }

    func entries(on date: Date) -> [FoodLogEntry] {
        let cal = Calendar.plate
        return household.log.filter { cal.isDate($0.date, inSameDayAs: date) }.sorted { $0.date < $1.date }
    }

    func totals(on date: Date) -> Macros {
        entries(on: date).reduce(Macros.zero) { $0 + $1.macros }
    }

    var targets: MacroTargets { household.members.first?.targets ?? MacroTargets() }

    // MARK: Plan

    func dayIndex(for date: Date) -> Int {
        let cal = Calendar.plate
        let start = cal.startOfWeek(for: date)
        guard cal.isDate(start, inSameDayAs: household.plan.weekStart) else { return -1 }
        return cal.dateComponents([.day], from: start, to: cal.startOfDay(for: date)).day ?? -1
    }

    func date(forDay day: Int) -> Date {
        Calendar.plate.date(byAdding: .day, value: day, to: household.plan.weekStart) ?? household.plan.weekStart
    }

    /// Moves the plan on to this week if it's from an earlier one.
    func rollPlanForward(now: Date = Date()) {
        let thisWeek = Calendar.plate.startOfWeek(for: now)
        if household.plan.weekStart < thisWeek {
            household.plan = MealPlan(weekStart: thisWeek, entries: [])
        }
    }

    func generatePlan(seed: UInt64 = UInt64.random(in: 1...UInt64.max - 1), keepLocked: Bool = true) {
        let keep = keepLocked ? household.plan.entries.filter(\.locked) : []
        let kcal = targets.kcal
        let entries = Planner.generate(recipes: recipes, inventory: household.inventory,
                                       options: .init(settings: household.planSettings, seed: seed, keep: keep, dailyKcal: kcal),
                                       now: Date())
        household.plan.entries = entries
    }

    /// Picks a different recipe for one slot.
    func swap(_ entry: PlanEntry) {
        let options = recipes.filter { $0.fits(entry.meal) && $0.id != entry.recipeId }
        let ranked = Suggestions.rank(options, inventory: household.inventory, servings: entry.servings, now: Date(), mealType: entry.meal)
        let pick = ranked.prefix(6).randomElement()?.recipe ?? options.randomElement()
        guard let pick, let i = household.plan.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        household.plan.entries[i].recipeId = pick.id
        household.plan.entries[i].cooked = false
    }

    func addToPlan(_ recipe: Recipe, day: Int, meal: MealType, servings: Int) {
        household.plan.entries.append(PlanEntry(day: day, meal: meal, recipeId: recipe.id, servings: servings))
    }

    /// A new shopping list with every meal in the plan, portions added up per recipe.
    @discardableResult
    func makeListFromPlan() -> ShoppingList {
        var totals: [UUID: Int] = [:]
        var order: [UUID] = []
        for e in household.plan.entries where !e.cooked {
            if totals[e.recipeId] == nil { order.append(e.recipeId) }
            totals[e.recipeId, default: 0] += e.servings
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM"
        let list = ShoppingList(name: "Week of \(fmt.string(from: household.plan.weekStart))",
                                meals: order.map { ListMeal(recipeId: $0, servings: totals[$0]!) },
                                stores: household.stores)
        household.lists.insert(list, at: 0)
        return list
    }

    // MARK: Shopping

    func list(_ id: UUID) -> ShoppingList? { household.lists.first { $0.id == id } }

    func update(_ list: ShoppingList) {
        if let i = household.lists.firstIndex(where: { $0.id == list.id }) {
            var l = list
            l.updatedAt = Date()
            household.lists[i] = l
        }
    }

    func result(for list: ShoppingList) -> ShoppingResult {
        let meals = list.meals.compactMap { m in recipe(m.recipeId).map { ($0, m.servings) } }
        return ShoppingBuilder.build(meals: meals, manual: list.manualItems, inventory: household.inventory,
                                     stores: list.stores.isEmpty ? Store.allCases : list.stores, useKitchen: list.useKitchen)
    }

    /// Puts the ticked items into the kitchen and clears them off the list.
    func putAway(_ list: ShoppingList) -> Int {
        let res = result(for: list)
        let ticked = res.lines.filter { list.checked.contains($0.key) && !$0.alreadyHave }
        let items = ShoppingBuilder.purchases(ticked, now: Date())
        for item in items { add(item) }
        var l = list
        l.checked.subtract(ticked.map(\.key))
        // Manual items that were bought come off the list too.
        let boughtNames = Set(ticked.map { $0.name.lowercased() })
        l.manualItems.removeAll { boughtNames.contains($0.name.lowercased()) || boughtNames.contains((FoodDatabase.food($0.foodId)?.name ?? "").lowercased()) }
        update(l)
        return items.count
    }

    // MARK: Imports from the share sheet

    func collectInbox() {
        waitingVideos = WaitingForVideo.all()
        let items = Inbox.takeAll()
        guard !items.isEmpty else { return }
        var names: [String] = []
        for item in items {
            var recipe: Recipe
            if let r = item.recipe {
                recipe = r
            } else {
                let parsed = RecipeTextParser.parse(item.caption)
                let platform = item.link.flatMap(URL.init(string:)).map(SocialImport.platform(of:))
                let kind: RecipeSourceKind = platform == .tiktok ? .tiktok : platform == .instagram ? .instagram : (item.link == nil ? .manual : .web)
                recipe = parsed.recipe(source: RecipeSource(kind: kind, url: item.link, author: item.author))
            }
            recipe.createdAt = item.savedAt
            household.recipes.append(recipe)
            names.append(recipe.name)
            // The post's cover picture, as the dish's photo until there's a better one.
            if let cover = item.thumbnail.flatMap(URL.init(string:)) {
                let id = recipe.id
                Task { await offerCover(cover, for: id) }
            }
        }
        banner = names.count == 1 ? "Saved \(names[0])" : "Saved \(names.count) recipes"
    }
}

extension Household {
    /// Built-in recipes marked as favourites (the built-ins themselves never change).
    var favouriteBuiltIns: Set<UUID> {
        get { Set(extras["favouriteBuiltIns"]?.split(separator: ",").compactMap { UUID(uuidString: String($0)) } ?? []) }
        set { extras["favouriteBuiltIns"] = newValue.map(\.uuidString).sorted().joined(separator: ",") }
    }

    /// Prepped meals in the fridge, and which recipe each one is.
    var preppedMeals: [UUID: UUID] {
        get {
            var out: [UUID: UUID] = [:]
            for pair in (extras["prepped"] ?? "").split(separator: ",") {
                let parts = pair.split(separator: ":")
                if parts.count == 2, let a = UUID(uuidString: String(parts[0])), let b = UUID(uuidString: String(parts[1])) { out[a] = b }
            }
            return out
        }
        set { extras["prepped"] = newValue.map { "\($0.key.uuidString):\($0.value.uuidString)" }.sorted().joined(separator: ",") }
    }
}
