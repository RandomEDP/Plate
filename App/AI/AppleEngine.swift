#if canImport(FoundationModels)
import Foundation
import FoundationModels
import PlateCore

/// Apple's on-device model (Apple Intelligence). Free, private and works offline.
@available(iOS 26.0, *)
struct AppleEngine: RecipeAIEngine {
    var name: String { "Apple Intelligence" }

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var statusText: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Ready on this iPhone."
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "This iPhone doesn't support Apple Intelligence."
            case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in the Settings app to use it."
            case .modelNotReady: return "Apple Intelligence is still downloading. Try again later."
            @unknown default: return "Apple Intelligence isn't available right now."
            }
        }
    }

    @Generable
    struct GeneratedRecipe {
        @Guide(description: "Short name of the dish")
        var name: String
        @Guide(description: "One of: breakfast, lunch, dinner, snack")
        var meal: String
        @Guide(description: "Number of portions the recipe makes")
        var servings: Int
        @Guide(description: "Total time in minutes")
        var minutes: Int
        @Guide(description: "Ingredients, one food per item (never two foods joined with and), amount first, for example 200g chicken breast")
        var ingredients: [String]
        @Guide(description: "Method steps, short sentences")
        var steps: [String]
        @Guide(description: "Calories per portion")
        var calories: Int
        @Guide(description: "Grams of protein per portion")
        var protein: Int
        @Guide(description: "Grams of carbohydrate per portion")
        var carbs: Int
        @Guide(description: "Grams of fat per portion")
        var fat: Int
        @Guide(description: "One sentence describing the dish")
        var summary: String

        var draft: RecipeDraft {
            RecipeDraft(name: name, meal: meal, servings: servings, minutes: minutes, ingredients: ingredients, steps: steps,
                        calories: Double(calories), protein: Double(protein), carbs: Double(carbs), fat: Double(fat), summary: summary)
        }
    }

    @Generable
    struct GeneratedIdeas {
        @Guide(description: "Different recipe ideas")
        var recipes: [GeneratedRecipe]
    }

    func tidy(caption: String) async throws -> RecipeDraft {
        let session = LanguageModelSession(instructions: AIPrompts.instructions)
        let response = try await session.respond(to: AIPrompts.tidy(caption), generating: GeneratedRecipe.self)
        return response.content.draft
    }

    func ideas(kitchen: [String], meal: MealType?, count: Int, people: Int) async throws -> [RecipeDraft] {
        let session = LanguageModelSession(instructions: AIPrompts.instructions)
        let response = try await session.respond(to: AIPrompts.ideas(kitchen: kitchen, meal: meal, count: count, people: people),
                                                 generating: GeneratedIdeas.self)
        return Array(response.content.recipes.prefix(count).map(\.draft))
    }
}
#endif
