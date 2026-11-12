import XCTest
@testable import PlateCore

final class RecipeLibraryTests: XCTestCase {
    func testDeletingSeveralRecipesTidiesUpAfterThem() {
        let mine = (0..<3).map { Recipe(name: "Mine \($0)", mealTypes: [.dinner], servings: 2, ingredients: [], steps: []) }
        let builtIn = BuiltInRecipes.all[0]
        var h = Household()
        h.recipes = mine
        h.plan.entries = [
            PlanEntry(day: 0, meal: .dinner, recipeId: mine[0].id, servings: 2),
            PlanEntry(day: 1, meal: .dinner, recipeId: mine[2].id, servings: 2),
            PlanEntry(day: 2, meal: .dinner, recipeId: builtIn.id, servings: 2),
        ]
        var list = ShoppingList(name: "Week")
        list.meals = [ListMeal(recipeId: mine[1].id, servings: 2), ListMeal(recipeId: mine[2].id, servings: 2)]
        h.lists = [list]

        h.deleteRecipes([mine[0].id, mine[1].id, builtIn.id])

        XCTAssertEqual(h.recipes.map(\.name), ["Mine 2"])
        XCTAssertTrue(h.hiddenBuiltIns.contains(builtIn.id), "Built-in recipes are hidden, not lost")
        XCTAssertEqual(h.plan.entries.map(\.recipeId), [mine[2].id])
        XCTAssertEqual(h.lists[0].meals.map(\.recipeId), [mine[2].id])
    }

    func testDeletingNothingChangesNothing() {
        var h = Household()
        h.recipes = [Recipe(name: "Keep", mealTypes: [.lunch], servings: 1, ingredients: [], steps: [])]
        let before = h
        h.deleteRecipes([])
        XCTAssertEqual(h, before)
    }
}
