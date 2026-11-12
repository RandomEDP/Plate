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

    func testReimportKeepsTheRecipesPlaceAndFavourite() {
        let old = Recipe(name: "Chickpea & Courgette Salad", mealTypes: [.lunch], servings: 2, ingredients: [], steps: [],
                         source: RecipeSource(kind: .web, url: "https://ostarecipes.com/s/recipes/AAAAAAAAAA"),
                         isFavourite: true, createdAt: Date(timeIntervalSince1970: 1000))
        var h = Household()
        h.recipes = [old]
        h.plan.entries = [PlanEntry(day: 0, meal: .lunch, recipeId: old.id, servings: 2)]
        let fresh = Recipe(name: "Creamy Tirokafteri", mealTypes: [.lunch], servings: 4,
                           ingredients: [RecipeIngredient(name: "feta", foodId: nil, quantity: Quantity(200, .g))], steps: ["Blend."],
                           source: RecipeSource(kind: .web, url: "https://ostarecipes.com/s/recipes/AAAAAAAAAA"))

        XCTAssertTrue(h.replaceRecipe(old.id, with: fresh))

        XCTAssertEqual(h.recipes.count, 1)
        let r = h.recipes[0]
        XCTAssertEqual(r.id, old.id, "The meal plan still points at it")
        XCTAssertEqual(r.name, "Creamy Tirokafteri")
        XCTAssertEqual(r.servings, 4)
        XCTAssertTrue(r.isFavourite)
        XCTAssertEqual(r.createdAt, old.createdAt)
        XCTAssertEqual(h.plan.entries.first?.recipeId, old.id)
        XCTAssertFalse(h.replaceRecipe(UUID(), with: fresh), "A recipe deleted meanwhile isn't brought back")
    }
}
