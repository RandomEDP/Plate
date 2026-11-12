import Foundation
import PlateCore
import Security

/// A recipe as an AI model writes it: plain lines that then go through Plate's own ingredient reader.
struct RecipeDraft: Codable, Hashable {
    var name: String
    var meal: String
    var servings: Int
    var minutes: Int
    var ingredients: [String]
    var steps: [String]
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var summary: String?

    func recipe(source: RecipeSource) -> Recipe {
        let ings = UnitStandard.tidy(ingredients.compactMap { IngredientParser.ingredient($0) ?? RecipeIngredient(name: $0, foodId: nil, quantity: nil) })
        let mealType = MealType(rawValue: meal.lowercased())
        let types: [MealType] = mealType.map { $0 == .lunch || $0 == .dinner ? [$0, $0 == .lunch ? .dinner : .lunch] : [$0] }
            ?? RecipeTextParser.guessMealTypes(name: name, tags: [], ingredients: ings, text: "")
        let stated = calories > 0 ? Macros(kcal: calories, protein: protein, carbs: carbs, fat: fat) : nil
        return Recipe(name: name, summary: summary ?? "", mealTypes: types, servings: max(1, servings), ingredients: ings,
                      steps: steps, minutes: minutes > 0 ? minutes : nil, source: source, statedPerServing: stated,
                      mealPrepFriendly: servings >= 3)
    }
}

enum AIChoice: String, CaseIterable, Identifiable {
    case automatic, apple, claude, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .apple: return "Apple Intelligence only"
        case .claude: return "Claude"
        case .off: return "Off"
        }
    }
    var detail: String {
        switch self {
        case .automatic: return "Uses Apple's free on-device model, and Claude if you've added a key and Apple's isn't available."
        case .apple: return "Free and private. Needs an iPhone with Apple Intelligence turned on."
        case .claude: return "Uses your Claude API key for everything. Most creative, costs a fraction of a penny a go."
        case .off: return "No AI. Recipes are read by Plate's own reader and ideas come from your recipe library."
        }
    }
}

enum ClaudeModel: String, CaseIterable, Identifiable {
    case opus = "claude-opus-5-5"
    case haiku = "claude-haiku-5-5"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .opus: return "Claude Opus 5.5 (best)"
        case .haiku: return "Claude Haiku 5.5 (cheapest)"
        }
    }
}

protocol RecipeAIEngine {
    var name: String { get }
    func tidy(caption: String) async throws -> RecipeDraft
    func ideas(kitchen: [String], meal: MealType?, count: Int, people: Int) async throws -> [RecipeDraft]
}

enum AIPrompts {
    static let instructions = """
    You are the cooking assistant in Plate, a UK kitchen app. Use British ingredient names (courgette, coriander, \
    chickpeas, double cream) and metric amounts. Write each ingredient as one line with the amount first, for example \
    "200g chicken breast", "1 tin chopped tomatoes", "2 garlic cloves". One food per line: never join two foods with \
    "and" (write "2 garlic cloves" and "3 spring onions" as two lines). When no amount is given, write the food on its own \
    rather than guessing one. Keep method steps short. Give calories and \
    macros per portion as your best estimate.
    """

    static func tidy(_ caption: String) -> String {
        """
        This is the caption from an Instagram Reel or TikTok. Pull out the recipe exactly as the creator gives it: \
        their amounts, their number of portions, and their macros if they state them. Leave out hashtags, adverts and \
        "follow for more". If the caption doesn't say how many portions, make a sensible guess. The meal is one of \
        breakfast, lunch, dinner or snack.

        Caption:
        \(caption.prefix(6000))
        """
    }

    static func ideas(kitchen: [String], meal: MealType?, count: Int, people: Int) -> String {
        let mealText = meal.map { "\($0.rawValue) recipes" } ?? "recipes (any meal)"
        return """
        Here's what's in my kitchen right now:
        \(kitchen.prefix(80).joined(separator: "\n"))

        Suggest \(count) different \(mealText) for \(people) \(people == 1 ? "person" : "people") that use mostly these \
        foods, needing at most three extra ingredients each (store cupboard basics like oil, salt, pepper and dried \
        spices are fine). Make them tasty and realistic for a weeknight, with a good amount of protein. Vary the cuisines.
        """
    }
}

/// Picks the engine to use, following the person's choice in Settings.
enum AIService {
    static func engine(choice: AIChoice, claudeModel: ClaudeModel) -> RecipeAIEngine? {
        switch choice {
        case .off:
            return nil
        case .apple:
            return appleEngine()
        case .claude:
            return Keychain.claudeKey.map { ClaudeEngine(key: $0, model: claudeModel) }
        case .automatic:
            if let apple = appleEngine() { return apple }
            return Keychain.claudeKey.map { ClaudeEngine(key: $0, model: claudeModel) }
        }
    }

    static func appleEngine() -> RecipeAIEngine? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleEngine.isAvailable { return AppleEngine() }
        #endif
        return nil
    }

    /// Why Apple's model can't be used on this phone, in plain words (nil when it can).
    static var appleStatus: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return AppleEngine.statusText }
        #endif
        return "Needs iOS 26 or later."
    }
}

/// The Claude API key, kept in the iPhone's keychain (never in the app's files or backups in plain text).
enum Keychain {
    static let service = "com.randomedp.plate"
    static let account = "claude-api-key"

    static var claudeKey: String? {
        get {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
            var out: AnyObject?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
                  let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
            return s
        }
        set {
            let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                       kSecAttrAccount as String: account]
            SecItemDelete(base as CFDictionary)
            guard let v = newValue?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return }
            var add = base
            add[kSecValueData as String] = Data(v.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
