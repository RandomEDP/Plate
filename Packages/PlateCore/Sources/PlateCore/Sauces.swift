import Foundation

/// Sauces, dips and dressings: made to go with a meal, not eaten as one. A recipe is a sauce when it carries the
/// tag "sauce", so the household file needs no new field and older copies of Plate still open it. Sauces get their
/// own filter in Recipes and are never planned as a breakfast, lunch, dinner or snack.
public enum Sauces {
    public static let tag = "sauce"

    /// Words a sauce's name ends with ("Honey mustard dressing", "Spicy mayo").
    static let endings: Set<String> = [
        "sauce", "sauces", "dressing", "dressings", "vinaigrette", "pesto", "dip", "dips", "salsa", "chimichurri",
        "aioli", "mayo", "mayonnaise", "gravy", "marinade", "hummus", "houmous", "hummous", "guacamole", "guac",
        "tzatziki", "raita", "glaze", "relish", "chutney", "ketchup", "harissa", "gremolata", "romesco", "coulis",
        "jus", "condiment", "condiments", "drizzle", "baba ganoush", "pico de gallo", "salsa verde", "chilli oil",
        "chili oil", "chilli crisp", "chili crisp", "curry paste", "spice paste", "garlic butter", "herb butter",
        "compound butter", "salad cream", "tahini", "nam jim", "nuoc cham", "ponzu",
    ]

    /// Endings that are a sauce even after a main food ("Chicken marinade", "Pasta sauce"). The rest aren't:
    /// "Chicken pesto" and "Tuna mayo" are dishes.
    static let alwaysSauce: Set<String> = [
        "sauce", "sauces", "dressing", "dressings", "vinaigrette", "gravy", "marinade", "glaze", "dip", "dips", "jus",
        "condiment", "condiments",
    ]

    /// Main foods. A name with one of these is a dish unless it ends with one of `alwaysSauce`.
    static let mainFoods: Set<String> = [
        "chicken", "beef", "pork", "lamb", "steak", "mince", "turkey", "duck", "sausage", "sausages", "bacon", "ham",
        "salmon", "tuna", "cod", "fish", "prawn", "prawns", "shrimp", "tofu", "halloumi", "paneer", "egg", "eggs",
        "pasta", "spaghetti", "penne", "gnocchi", "rice", "noodles", "potato", "potatoes", "chips", "fries", "bread",
        "toast", "wrap", "wraps", "sandwich", "burger", "pizza", "bowl", "nachos", "meatballs", "wings", "tacos",
    ]

    /// Words that make the name a dish served with a sauce ("Salmon with pesto", "Chicken in garlic sauce").
    static let connectors: Set<String> = ["with", "in", "on", "over", "served", "topped", "plus", "w", "alongside"]

    /// Words a caption often tacks on after the real name ("Burger sauce recipe", "Pesto (vegan)").
    static let filler: Set<String> = [
        "recipe", "recipes", "ever", "easy", "quick", "healthy", "vegan", "vegetarian", "gf", "df", "version",
        "edition", "style", "homemade", "simple", "minute", "minutes", "mins", "min", "only", "ingredient",
        "ingredients", "x", "the", "best",
    ]

    /// Whether a recipe's name says it's a sauce, dip or dressing rather than a dish that comes with one.
    public static func looksLike(name: String) -> Bool {
        var words = name.lowercased()
            .map { $0.isLetter ? $0 : " " }
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        while let last = words.last, filler.contains(last) { words.removeLast() }
        guard !words.isEmpty, !words.contains(where: { connectors.contains($0) }) else { return false }
        let tails = [3, 2, 1].filter { words.count >= $0 }.map { words.suffix($0).joined(separator: " ") }
        guard let ending = tails.first(where: { endings.contains($0) }) else { return false }
        // "Nachos and salsa" is a dish; "Sweet and sour sauce" and "Garlic and herb dip" aren't.
        if let and = words.lastIndex(where: { $0 == "and" || $0 == "n" }),
           words[(and + 1)...].joined(separator: " ") == ending { return false }
        if !alwaysSauce.contains(ending), words.contains(where: { mainFoods.contains($0) }) { return false }
        return true
    }

    /// Tags a newly built recipe as a sauce when its name says so. Nothing is ever untagged here: that's yours to do.
    public static func mark(_ recipe: inout Recipe) {
        if !recipe.isSauce && looksLike(name: recipe.name) { recipe.isSauce = true }
    }
}

extension Recipe {
    /// A sauce, dip or dressing: shown under Sauces and kept out of the meal plan.
    public var isSauce: Bool {
        get { tags.contains { $0.lowercased() == Sauces.tag } }
        set {
            tags.removeAll { $0.lowercased() == Sauces.tag }
            if newValue { tags.append(Sauces.tag) }
        }
    }

    /// Whether the recipe can be eaten as this meal. Sauces never count, whatever meals they're marked for.
    public func fits(_ meal: MealType) -> Bool {
        !isSauce && mealTypes.contains(meal)
    }
}

extension Household {
    static let saucesMarkedKey = "saucesMarked"

    /// Tags the sauces already in your recipes, once, so the Sauces filter isn't empty when it first appears.
    /// Later changes (untagging one, say) are left alone.
    public mutating func markSavedSaucesOnce() -> Bool {
        guard extras[Household.saucesMarkedKey] == nil else { return false }
        for i in recipes.indices where !recipes[i].isSauce && Sauces.looksLike(name: recipes[i].name) {
            recipes[i].isSauce = true
            recipes[i].updatedAt = Date()
        }
        extras[Household.saucesMarkedKey] = "1"
        updatedAt = Date()
        return true
    }
}
