import Foundation

// MARK: - Basics

/// Calories and macros. Used per 100 g (or 100 ml) for foods, and per serving for recipes and the food log.
public struct Macros: Codable, Hashable, Sendable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var fibre: Double

    public init(kcal: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0, fibre: Double = 0) {
        self.kcal = kcal; self.protein = protein; self.carbs = carbs; self.fat = fat; self.fibre = fibre
    }

    public static let zero = Macros()

    public static func + (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, carbs: a.carbs + b.carbs, fat: a.fat + b.fat, fibre: a.fibre + b.fibre)
    }
    public static func += (a: inout Macros, b: Macros) { a = a + b }
    public static func * (a: Macros, k: Double) -> Macros {
        Macros(kcal: a.kcal * k, protein: a.protein * k, carbs: a.carbs * k, fat: a.fat * k, fibre: a.fibre * k)
    }
    public static func / (a: Macros, k: Double) -> Macros { k == 0 ? .zero : a * (1 / k) }

    /// Rounded for display and for comparing in tests.
    public var rounded: Macros {
        Macros(kcal: kcal.rounded(), protein: (protein * 10).rounded() / 10, carbs: (carbs * 10).rounded() / 10,
               fat: (fat * 10).rounded() / 10, fibre: (fibre * 10).rounded() / 10)
    }
}

/// The three ways an amount is kept: by weight, by volume, or by count ("3 eggs").
public enum BaseUnit: String, Codable, CaseIterable, Sendable {
    case g, ml, piece

    public var short: String {
        switch self { case .g: return "g"; case .ml: return "ml"; case .piece: return "" }
    }
}

/// Units people write in recipes. Each converts to one of the base units.
public enum MeasureUnit: String, Codable, CaseIterable, Sendable {
    case g, kg, mg, ml, l, tsp, tbsp, cup, oz, lb, floz, pinch, piece, clove, slice, can, pack, bunch, handful

    public var base: BaseUnit {
        switch self {
        case .g, .kg, .mg, .oz, .lb, .can, .pack, .handful: return .g
        case .ml, .l, .tsp, .tbsp, .cup, .floz, .pinch: return .ml
        case .piece, .clove, .slice, .bunch: return .piece
        }
    }

    /// How many base units one of these is. Cans, packs and handfuls are typical UK sizes.
    public var factor: Double {
        switch self {
        case .g, .ml, .piece, .clove, .slice, .bunch: return 1
        case .kg, .l: return 1000
        case .mg: return 0.001
        case .tsp: return 5
        case .tbsp: return 15
        case .cup: return 240
        case .floz: return 28.4
        case .pinch: return 0.3
        case .oz: return 28.35
        case .lb: return 453.6
        case .can: return 400
        case .pack: return 250
        case .handful: return 30
        }
    }

    public var label: String {
        switch self {
        case .piece: return ""
        case .floz: return "fl oz"
        default: return rawValue
        }
    }
}

public struct Quantity: Codable, Hashable, Sendable {
    public var amount: Double
    public var unit: MeasureUnit
    public init(_ amount: Double, _ unit: MeasureUnit) { self.amount = amount; self.unit = unit }
}

public enum StorageLocation: String, Codable, CaseIterable, Sendable, Identifiable {
    case fridge, freezer, cupboard
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum FoodCategory: String, Codable, CaseIterable, Sendable {
    case produce, meat, fish, dairy, eggs, bakery, grains, tins, condiments, spices, frozen, snacks, drinks, other

    public var title: String {
        switch self {
        case .produce: return "Fruit & veg"
        case .meat: return "Meat"
        case .fish: return "Fish"
        case .dairy: return "Dairy"
        case .eggs: return "Eggs"
        case .bakery: return "Bakery"
        case .grains: return "Pasta, rice & grains"
        case .tins: return "Tins & jars"
        case .condiments: return "Sauces & oils"
        case .spices: return "Herbs & spices"
        case .frozen: return "Frozen"
        case .snacks: return "Snacks"
        case .drinks: return "Drinks"
        case .other: return "Other"
        }
    }
}

public enum Store: String, Codable, CaseIterable, Sendable, Identifiable {
    case sainsburys, costco
    public var id: String { rawValue }
    public var title: String {
        switch self { case .sainsburys: return "Sainsbury's"; case .costco: return "Costco" }
    }
}

/// One size of a product on a shop's shelf, with a rough price in pounds.
public struct PackOption: Codable, Hashable, Sendable {
    public var store: Store
    /// Size in the food's base unit (grams, ml or pieces).
    public var size: Double
    public var price: Double
    public init(_ store: Store, _ size: Double, _ price: Double) { self.store = store; self.size = size; self.price = price }
}

/// An entry in Plate's built-in food list.
public struct Food: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var aliases: [String]
    public var category: FoodCategory
    public var storage: StorageLocation
    /// The unit you'd naturally keep it in (eggs by count, milk by ml, rice by g).
    public var unit: BaseUnit
    public var per100: Macros
    public var gramsPerPiece: Double?
    public var gramsPerMl: Double
    /// What "1 tin" means for this food, in its base unit (drained weight for beans and tuna). Plain tins are 400 g.
    public var canSize: Double?
    public var shelfLifeDays: Int?
    /// Salt, pepper, oil and the like: assumed to be in the cupboard unless you say otherwise.
    public var isStaple: Bool
    /// Foods in the same group can stand in for each other in a variation (chicken for turkey, rice for couscous).
    public var swapGroup: String?
    public var packs: [PackOption]

    public init(id: String, name: String, aliases: [String] = [], category: FoodCategory, storage: StorageLocation,
                unit: BaseUnit = .g, per100: Macros, gramsPerPiece: Double? = nil, gramsPerMl: Double = 1,
                canSize: Double? = nil, shelfLifeDays: Int? = nil, isStaple: Bool = false, swapGroup: String? = nil, packs: [PackOption] = []) {
        self.id = id; self.name = name; self.aliases = aliases; self.category = category; self.storage = storage
        self.unit = unit; self.per100 = per100; self.gramsPerPiece = gramsPerPiece; self.gramsPerMl = gramsPerMl; self.canSize = canSize
        self.shelfLifeDays = shelfLifeDays; self.isStaple = isStaple; self.swapGroup = swapGroup; self.packs = packs
    }

    public var isPerishable: Bool { (shelfLifeDays ?? 365) <= 10 }
}

// MARK: - Kitchen

public struct InventoryItem: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var foodId: String?
    public var name: String
    public var amount: Double
    public var unit: BaseUnit
    public var location: StorageLocation
    public var expiry: Date?
    public var addedAt: Date
    public var barcode: String?
    /// Nutrition from a scanned label, used when the item isn't in the built-in list.
    public var customPer100: Macros?
    public var updatedAt: Date

    public init(id: UUID = UUID(), foodId: String?, name: String, amount: Double, unit: BaseUnit,
                location: StorageLocation, expiry: Date? = nil, addedAt: Date = Date(), barcode: String? = nil,
                customPer100: Macros? = nil) {
        self.id = id; self.foodId = foodId; self.name = name; self.amount = amount; self.unit = unit
        self.location = location; self.expiry = expiry; self.addedAt = addedAt; self.barcode = barcode
        self.customPer100 = customPer100; self.updatedAt = addedAt
    }
}

/// A record of food used, so Plate learns how fast you get through things.
public struct UsageRecord: Codable, Hashable, Sendable {
    public var foodId: String
    public var amount: Double
    public var unit: BaseUnit
    public var date: Date
    public init(foodId: String, amount: Double, unit: BaseUnit, date: Date) {
        self.foodId = foodId; self.amount = amount; self.unit = unit; self.date = date
    }
}

// MARK: - Recipes

public enum MealType: String, Codable, CaseIterable, Sendable, Identifiable {
    case breakfast, lunch, dinner, snack
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct RecipeIngredient: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// What the recipe said, tidied ("chicken breast").
    public var name: String
    public var foodId: String?
    public var quantity: Quantity?
    /// "diced", "to taste" and so on.
    public var note: String?
    public var optional: Bool

    public init(id: UUID = UUID(), name: String, foodId: String?, quantity: Quantity?, note: String? = nil, optional: Bool = false) {
        self.id = id; self.name = name; self.foodId = foodId; self.quantity = quantity; self.note = note; self.optional = optional
    }
}

public enum RecipeSourceKind: String, Codable, Sendable {
    case builtIn, instagram, tiktok, web, manual, ai, variation
}

public struct RecipeSource: Codable, Hashable, Sendable {
    public var kind: RecipeSourceKind
    public var url: String?
    public var author: String?
    public init(kind: RecipeSourceKind, url: String? = nil, author: String? = nil) {
        self.kind = kind; self.url = url; self.author = author
    }
}

public struct Recipe: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var summary: String
    public var mealTypes: [MealType]
    public var servings: Int
    public var ingredients: [RecipeIngredient]
    public var steps: [String]
    public var minutes: Int?
    public var tags: [String]
    public var source: RecipeSource
    /// Macros the creator gave (from a caption, say). When nil, Plate works them out from the ingredients.
    public var statedPerServing: Macros?
    public var isFavourite: Bool
    /// Good for cooking in bulk and keeping in the fridge.
    public var mealPrepFriendly: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, summary: String = "", mealTypes: [MealType], servings: Int,
                ingredients: [RecipeIngredient], steps: [String], minutes: Int? = nil, tags: [String] = [],
                source: RecipeSource = RecipeSource(kind: .manual), statedPerServing: Macros? = nil,
                isFavourite: Bool = false, mealPrepFriendly: Bool = false, createdAt: Date = Date()) {
        self.id = id; self.name = name; self.summary = summary; self.mealTypes = mealTypes; self.servings = max(1, servings)
        self.ingredients = ingredients; self.steps = steps; self.minutes = minutes; self.tags = tags; self.source = source
        self.statedPerServing = statedPerServing; self.isFavourite = isFavourite; self.mealPrepFriendly = mealPrepFriendly
        self.createdAt = createdAt; self.updatedAt = createdAt
    }
}

// MARK: - Plan, log and lists

public struct PlanEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Days from the start of the plan's week (0 = Monday).
    public var day: Int
    public var meal: MealType
    public var recipeId: UUID
    /// How many portions to make (people eating it).
    public var servings: Int
    public var cooked: Bool
    public var locked: Bool

    public init(id: UUID = UUID(), day: Int, meal: MealType, recipeId: UUID, servings: Int, cooked: Bool = false, locked: Bool = false) {
        self.id = id; self.day = day; self.meal = meal; self.recipeId = recipeId; self.servings = servings
        self.cooked = cooked; self.locked = locked
    }
}

/// How the planner fills a week. All counts are per week.
public struct PlanSettings: Codable, Hashable, Sendable {
    public var people: Int
    public var breakfasts: Int
    public var lunches: Int
    public var dinners: Int
    public var snacks: Int
    /// How many different recipes for each meal. Fewer means more batch cooking and a cheaper shop.
    public var breakfastVariety: Int
    public var lunchVariety: Int
    public var dinnerVariety: Int
    public var snackVariety: Int

    public init(people: Int = 1, breakfasts: Int = 7, lunches: Int = 5, dinners: Int = 7, snacks: Int = 0,
                breakfastVariety: Int = 2, lunchVariety: Int = 2, dinnerVariety: Int = 4, snackVariety: Int = 1) {
        self.people = people; self.breakfasts = breakfasts; self.lunches = lunches; self.dinners = dinners; self.snacks = snacks
        self.breakfastVariety = breakfastVariety; self.lunchVariety = lunchVariety; self.dinnerVariety = dinnerVariety
        self.snackVariety = snackVariety
    }

    public func count(_ m: MealType) -> Int {
        switch m { case .breakfast: return breakfasts; case .lunch: return lunches; case .dinner: return dinners; case .snack: return snacks }
    }
    public func variety(_ m: MealType) -> Int {
        switch m {
        case .breakfast: return breakfastVariety; case .lunch: return lunchVariety
        case .dinner: return dinnerVariety; case .snack: return snackVariety
        }
    }
}

public struct MealPlan: Codable, Hashable, Sendable {
    public var weekStart: Date
    public var entries: [PlanEntry]
    public init(weekStart: Date, entries: [PlanEntry] = []) { self.weekStart = weekStart; self.entries = entries }
}

public struct FoodLogEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var meal: MealType
    public var title: String
    public var macros: Macros
    public var recipeId: UUID?
    public var portions: Double
    public init(id: UUID = UUID(), date: Date, meal: MealType, title: String, macros: Macros, recipeId: UUID? = nil, portions: Double = 1) {
        self.id = id; self.date = date; self.meal = meal; self.title = title; self.macros = macros
        self.recipeId = recipeId; self.portions = portions
    }
}

public struct MacroTargets: Codable, Hashable, Sendable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public init(kcal: Double = 2200, protein: Double = 150, carbs: Double = 230, fat: Double = 75) {
        self.kcal = kcal; self.protein = protein; self.carbs = carbs; self.fat = fat
    }
}

/// A meal picked for a shopping list, and how many portions.
public struct ListMeal: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var recipeId: UUID
    public var servings: Int
    public init(id: UUID = UUID(), recipeId: UUID, servings: Int) { self.id = id; self.recipeId = recipeId; self.servings = servings }
}

public struct ManualItem: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var foodId: String?
    public var amount: Double?
    public var unit: BaseUnit?
    public init(id: UUID = UUID(), name: String, foodId: String? = nil, amount: Double? = nil, unit: BaseUnit? = nil) {
        self.id = id; self.name = name; self.foodId = foodId; self.amount = amount; self.unit = unit
    }
}

public struct ShoppingList: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var meals: [ListMeal]
    public var manualItems: [ManualItem]
    /// Keys of lines ticked off in the shop.
    public var checked: Set<String>
    public var stores: [Store]
    /// Count what's already in the kitchen against the list.
    public var useKitchen: Bool
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), meals: [ListMeal] = [], manualItems: [ManualItem] = [],
                checked: Set<String> = [], stores: [Store] = Store.allCases, useKitchen: Bool = true) {
        self.id = id; self.name = name; self.createdAt = createdAt; self.meals = meals; self.manualItems = manualItems
        self.checked = checked; self.stores = stores; self.useKitchen = useKitchen; self.updatedAt = createdAt
    }
}

public struct Member: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var targets: MacroTargets
    public init(id: UUID = UUID(), name: String, targets: MacroTargets = MacroTargets()) {
        self.id = id; self.name = name; self.targets = targets
    }
}

/// Everything Plate keeps, for one household. Kept on the phone for now; every record has an id and an updatedAt,
/// so the same document can later be synced and merged between people sharing a household.
public struct Household: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var id: UUID
    public var name: String
    public var members: [Member]
    public var inventory: [InventoryItem]
    public var usage: [UsageRecord]
    public var recipes: [Recipe]
    /// Built-in recipes the person has removed from their library.
    public var hiddenBuiltIns: Set<UUID>
    public var plan: MealPlan
    public var planSettings: PlanSettings
    public var lists: [ShoppingList]
    public var log: [FoodLogEntry]
    public var stores: [Store]
    /// Small settings that don't need their own field (kept as text so older files always open).
    public var extras: [String: String]
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String = "My kitchen", members: [Member] = [Member(name: "Me")],
                inventory: [InventoryItem] = [], usage: [UsageRecord] = [], recipes: [Recipe] = [],
                hiddenBuiltIns: Set<UUID> = [], plan: MealPlan = MealPlan(weekStart: Calendar.plate.startOfWeek(for: Date())),
                planSettings: PlanSettings = PlanSettings(), lists: [ShoppingList] = [], log: [FoodLogEntry] = [],
                stores: [Store] = Store.allCases) {
        self.version = Household.currentVersion
        self.id = id; self.name = name; self.members = members; self.inventory = inventory; self.usage = usage
        self.recipes = recipes; self.hiddenBuiltIns = hiddenBuiltIns; self.plan = plan; self.planSettings = planSettings
        self.lists = lists; self.log = log; self.stores = stores; self.extras = [:]; self.updatedAt = Date()
    }

    enum CodingKeys: String, CodingKey {
        case version, id, name, members, inventory, usage, recipes, hiddenBuiltIns, plan, planSettings, lists, log, stores, extras, updatedAt
    }

    /// Reads a saved household, filling in anything an older version of Plate didn't save.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fresh = Household()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Household.currentVersion
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? fresh.id
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? fresh.name
        members = try c.decodeIfPresent([Member].self, forKey: .members) ?? fresh.members
        inventory = try c.decodeIfPresent([InventoryItem].self, forKey: .inventory) ?? []
        usage = try c.decodeIfPresent([UsageRecord].self, forKey: .usage) ?? []
        recipes = try c.decodeIfPresent([Recipe].self, forKey: .recipes) ?? []
        hiddenBuiltIns = try c.decodeIfPresent(Set<UUID>.self, forKey: .hiddenBuiltIns) ?? []
        plan = try c.decodeIfPresent(MealPlan.self, forKey: .plan) ?? fresh.plan
        planSettings = try c.decodeIfPresent(PlanSettings.self, forKey: .planSettings) ?? PlanSettings()
        lists = try c.decodeIfPresent([ShoppingList].self, forKey: .lists) ?? []
        log = try c.decodeIfPresent([FoodLogEntry].self, forKey: .log) ?? []
        stores = try c.decodeIfPresent([Store].self, forKey: .stores) ?? Store.allCases
        extras = try c.decodeIfPresent([String: String].self, forKey: .extras) ?? [:]
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

extension Calendar {
    /// Weeks start on Monday, as in the UK.
    public static var plate: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.locale = Locale(identifier: "en_GB")
        return c
    }

    public func startOfWeek(for date: Date) -> Date {
        let comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: comps).map { startOfDay(for: $0) } ?? startOfDay(for: date)
    }
}
