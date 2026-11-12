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
