import Foundation

extension Household {
    /// Deletes several recipes at once. Your own are removed; built-in ones are hidden (they can't be removed from the
    /// app). Either way they come out of the meal plan and the shopping lists, so nothing points at a missing recipe.
    public mutating func deleteRecipes(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let builtIn = Set(BuiltInRecipes.all.map(\.id))
        hiddenBuiltIns.formUnion(ids.intersection(builtIn))
        recipes.removeAll { ids.contains($0.id) }
        plan.entries.removeAll { ids.contains($0.recipeId) }
        for i in lists.indices where lists[i].meals.contains(where: { ids.contains($0.recipeId) }) {
            lists[i].meals.removeAll { ids.contains($0.recipeId) }
            lists[i].updatedAt = Date()
        }
        updatedAt = Date()
    }
}

extension Recipe {
    /// This recipe read again from its source: the new reading, but the same id (so the meal plan and shopping lists
    /// still point at it), still a favourite if it was, and still dated when it was first saved.
    public func refreshed(from fresh: Recipe) -> Recipe {
        var r = fresh
        r.id = id
        r.isFavourite = isFavourite
        r.mealPrepFriendly = mealPrepFriendly || fresh.mealPrepFriendly
        // Your rating and the dish's picture belong to you, not to the page it was read from.
        r.rating = rating
        r.photo = photo
        r.createdAt = createdAt
        r.updatedAt = Date()
        if r.source.url == nil { r.source = source }
        return r
    }
}

extension Household {
    /// Puts a re-read recipe in place of the old one. False when the old one has gone (deleted meanwhile).
    @discardableResult
    public mutating func replaceRecipe(_ id: UUID, with fresh: Recipe) -> Bool {
        guard let i = recipes.firstIndex(where: { $0.id == id }) else { return false }
        recipes[i] = recipes[i].refreshed(from: fresh)
        updatedAt = Date()
        return true
    }
}
