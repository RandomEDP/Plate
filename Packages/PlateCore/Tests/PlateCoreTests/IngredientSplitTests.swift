import XCTest
@testable import PlateCore

final class IngredientSplitTests: XCTestCase {
    func split(_ line: String) -> [RecipeIngredient] {
        IngredientSplit.split(IngredientParser.ingredient(line)!)
    }

    /// Ethan's video import, 12 November 2026: the shopping list asked for garlic and forgot the scallions.
    func testTwoFoodsOnOneLineBecomeTwoIngredients() {
        let parts = split("50g garlic and scallions")
        XCTAssertEqual(parts.map(\.foodId), ["garlic", "spring-onion"])
        XCTAssertEqual(parts.map(\.name), ["garlic", "scallions"])
        XCTAssertEqual(parts.map { $0.quantity?.amount }, [25, 25], "A weight is shared between the two")
        XCTAssertTrue(parts[0].note?.contains("half of") == true)
    }

    func testASpoonfulMeansThatMuchOfEach() {
        let parts = split("2 tbsp soy sauce & honey")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.map { $0.quantity?.amount }, [2, 2])
    }

    func testOneFoodWithAndInItsNameStaysWhole() {
        XCTAssertEqual(split("salt and pepper to taste").count, 1)
        XCTAssertEqual(split("200g chicken breast").count, 1)
        XCTAssertEqual(split("1 onion and a good mood").count, 1, "Only split when both sides are foods")
    }

    func testBothFoodsReachTheRecipeAndSoTheShoppingList() {
        let recipe = RecipeTextParser.parse("""
        Lazy hotpot
        Ingredients:
        50g garlic and scallions
        100g silken tofu
        50g mushrooms
        """).recipe(source: RecipeSource(kind: .manual))
        XCTAssertTrue(recipe.ingredients.contains { $0.foodId == "spring-onion" })
        XCTAssertTrue(recipe.ingredients.contains { $0.foodId == "garlic" })
        XCTAssertEqual(recipe.ingredients.count, 4)
    }
}
