import Foundation

/// Checks that an AI's tidied recipe really comes from the text it was given. Apple's on-device model, handed a page
/// with no recipe on it, will happily invent one (Ethan's Osta import, 12 November 2026, saved a run of "Chickpea &
/// Courgette Salad"s this way), so a tidy-up is only used when its ingredients are found in the original text.
public enum AIGuard {
    static let filler: Set<String> = [
        "and", "the", "for", "with", "fresh", "large", "small", "medium", "chopped", "sliced", "diced", "minced", "of",
        "to", "taste", "optional", "some", "into", "your", "choice", "finely", "roughly", "ground", "whole", "pinch",
    ]

    /// The words in an ingredient that matter for matching ("2 tbsp extra virgin olive oil" → extra, virgin, olive, oil).
    static func keyWords(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 3 && !filler.contains($0) && !MeasureUnitWords.all.contains($0) }
    }

    /// Whether most of the AI's ingredients appear in the original text.
    public static func faithful(ingredients: [String], to text: String) -> Bool {
        guard !ingredients.isEmpty else { return false }
        let haystack = text.lowercased()
        let found = ingredients.filter { ing in
            let words = keyWords(ing)
            // An ingredient with no telling words ("salt") can't be checked, so it doesn't count against the AI.
            return words.isEmpty || words.contains { haystack.contains(String($0.prefix(5))) }
        }
        return Double(found.count) / Double(ingredients.count) >= 0.7
    }
}

enum MeasureUnitWords {
    static let all: Set<String> = [
        "tsp", "tbsp", "teaspoon", "teaspoons", "tablespoon", "tablespoons", "cup", "cups", "gram", "grams", "kg", "litre",
        "litres", "ml", "clove", "cloves", "tin", "tins", "can", "cans", "handful", "slice", "slices", "pack", "packet",
    ]
}

extension AIGuard {
    /// Whether a recipe name the AI gave shares at least one real word with the text it read.
    public static func faithful(name: String, to text: String) -> Bool {
        let words = keyWords(name)
        guard !words.isEmpty else { return true }
        let haystack = text.lowercased()
        return words.contains { haystack.contains(String($0.prefix(5))) }
    }
}
