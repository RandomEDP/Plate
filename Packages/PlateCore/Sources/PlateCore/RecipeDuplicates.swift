import Foundation

/// Spots a recipe you've already saved, so sharing the same Reel twice (or pasting the same recipe text again)
/// doesn't leave two copies.
///
/// - The same post: the links give the same key (`BulkImport.key`), whatever tracking bits are on the end.
/// - The same recipe without a link to go on: the same name and most of the same ingredients, or nearly all the
///   same ingredients whatever it's called. Two different posts (both with links) are never called the same recipe.
public enum RecipeDuplicates {
    public enum Reason: Equatable, Sendable {
        /// Saved from the same post.
        case sameLink
        /// The same name and ingredients, from pasted text or a different source.
        case sameRecipe
    }

    public struct Match: Equatable, Sendable {
        public let recipe: Recipe
        public let reason: Reason

        /// "You already have …", ready to show.
        public var message: String {
            switch reason {
            case .sameLink: return "You already saved this post as “\(recipe.name)”."
            case .sameRecipe: return "You already have this recipe, as “\(recipe.name)”."
            }
        }
    }

    /// The saved recipe this one repeats, if there is one. A recipe never matches itself (same id).
    public static func match(for candidate: Recipe, in saved: [Recipe]) -> Match? {
        let others = saved.filter { $0.id != candidate.id }
        let link = candidate.source.url.flatMap(linkKey)
        if let link, let r = others.first(where: { $0.source.url.flatMap(linkKey) == link }) {
            return Match(recipe: r, reason: .sameLink)
        }
        let name = normalisedName(candidate.name)
        let foods = ingredientKeys(candidate)
        guard !foods.isEmpty else { return nil }
        var best: (recipe: Recipe, score: Double)?
        for r in others {
            // Two different posts: different recipes, even if they look alike.
            if let link, let theirs = r.source.url.flatMap(linkKey), theirs != link { continue }
            let theirFoods = ingredientKeys(r)
            let score = similarity(foods, theirFoods)
            let sameName = !name.isEmpty && normalisedName(r.name) == name
            let alike = (sameName && score >= 0.5) || (score >= 0.85 && min(foods.count, theirFoods.count) >= 4)
            if alike, score > (best?.score ?? -1) { best = (r, score) }
        }
        return best.map { Match(recipe: $0.recipe, reason: .sameRecipe) }
    }

    /// The key for a saved link, or nil when it isn't a web link at all.
    public static func linkKey(_ link: String) -> String? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let raw = trimmed.lowercased().hasPrefix("http") ? trimmed : "https://" + trimmed
        guard let url = URL(string: raw), url.host != nil else { return nil }
        let key = BulkImport.key(for: url)
        return key.isEmpty ? nil : key
    }

    /// Lower case, no accents, emoji or punctuation, single spaces: "Creamy Chicken Orzo! 🍗" → "creamy chicken orzo".
    static func normalisedName(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_GB"))
        let kept = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// Each ingredient as the food it matched, or its tidied name when it matched none.
    static func ingredientKeys(_ recipe: Recipe) -> Set<String> {
        Set(recipe.ingredients.map { ing in ing.foodId.map { "food:\($0)" } ?? normalisedName(ing.name) }.filter { !$0.isEmpty })
    }

    /// Shared ingredients over all the ingredients in either (0 to 1).
    static func similarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        let all = a.union(b)
        return all.isEmpty ? 0 : Double(a.intersection(b).count) / Double(all.count)
    }
}

/// The note shown when Plate opens and picks up recipes saved from the share sheet.
public enum InboxSummary {
    public static func text(saved: [String], updated: [String], repeats: [String]) -> String? {
        var parts: [String] = []
        if saved.count == 1 { parts.append("Saved \(saved[0])") }
        else if saved.count > 1 { parts.append("Saved \(saved.count) recipes") }
        if updated.count == 1 { parts.append("Updated \(updated[0])") }
        else if updated.count > 1 { parts.append("Updated \(updated.count) recipes") }
        if repeats.count == 1 { parts.append("You already had \(repeats[0]), so it wasn't saved twice") }
        else if repeats.count > 1 { parts.append("\(repeats.count) you already had weren't saved twice") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ". ") + "."
    }
}
