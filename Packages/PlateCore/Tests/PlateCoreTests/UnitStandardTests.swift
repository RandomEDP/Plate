import XCTest
@testable import PlateCore

final class UnitStandardTests: XCTestCase {
    func tidy(_ line: String) -> RecipeIngredient {
        UnitStandard.standardise(IngredientParser.ingredient(line)!)
    }

    /// Ethan, 12 November 2026: garlic should be in cloves, whatever the recipe says.
    func testGarlicInGramsBecomesCloves() {
        let ing = tidy("15g garlic")
        XCTAssertEqual(ing.quantity, Quantity(3, .clove))
        XCTAssertEqual(ing.convertedFrom, Quantity(15, .g))
        XCTAssertEqual(UnitStandard.convertedNote(ing), "Converted from 15g garlic")
        XCTAssertNil(ing.note)
    }

    func testGarlicPasteBySpoonBecomesCloves() {
        XCTAssertEqual(tidy("1 tbsp garlic puree").quantity, Quantity(3, .clove))
    }

    func testPlainCountOfGarlicIsCalledCloves() {
        let ing = tidy("2 garlic")
        XCTAssertEqual(ing.quantity, Quantity(2, .clove))
        XCTAssertNil(ing.note, "Only the word changed, so there's nothing to note")
        XCTAssertEqual(tidy("3 garlic cloves").quantity, Quantity(3, .clove))
    }

    func testCountedFoodsInGramsBecomeCounts() {
        XCTAssertEqual(tidy("300g onion").quantity, Quantity(2, .piece))
        XCTAssertEqual(tidy("40g red onion").quantity, Quantity(0.25, .piece), "A bit of onion is a quarter")
        XCTAssertEqual(tidy("100g eggs").quantity, Quantity(2, .piece))
        XCTAssertEqual(tidy("20g spring onions").quantity, Quantity(1, .piece), "Small things are whole, at least one")
    }

    func testSpoonsOfJuiceStaySpoons() {
        XCTAssertEqual(tidy("1 tbsp lemon juice").quantity, Quantity(1, .tbsp))
    }

    func testWeighedFoodsStayAsWritten() {
        XCTAssertEqual(tidy("2 chicken breasts").quantity, Quantity(2, .piece))
        XCTAssertEqual(tidy("200g chicken breast").quantity, Quantity(200, .g))
        XCTAssertEqual(tidy("1 lb beef mince").quantity, Quantity(455, .g), "Pounds become grams")
    }

    func testLiquidsGoIntoMl() {
        XCTAssertEqual(tidy("1 cup milk").quantity, Quantity(240, .ml))
        XCTAssertEqual(tidy("2 tbsp olive oil").quantity, Quantity(2, .tbsp), "Spoons stay spoons")
    }

    func testUnknownFoodsAreLeftAlone() {
        let ing = RecipeIngredient(name: "gochujang", foodId: nil, quantity: Quantity(30, .g))
        XCTAssertEqual(UnitStandard.standardise(ing), ing)
    }

    /// The hotpot: split first, then each half in its own unit.
    func testSplitThenStandardised() {
        let parts = UnitStandard.tidy([IngredientParser.ingredient("50g garlic and scallions")!])
        XCTAssertEqual(parts.map(\.quantity), [Quantity(5, .clove), Quantity(2, .piece)])
        XCTAssertNil(parts[0].convertedFrom, "The split's note already says what was given")
    }

    func testNewRecipesComeOutStandard() {
        let recipe = RecipeTextParser.parse("""
        Garlic noodles
        Ingredients:
        20g garlic
        200g noodles
        """).recipe(source: RecipeSource(kind: .manual))
        XCTAssertEqual(recipe.ingredients.first { $0.foodId == "garlic" }?.quantity, Quantity(4, .clove))
    }

    func testSavedRecipesAreConvertedOnce() {
        var h = Household()
        h.recipes = [Recipe(name: "Old", mealTypes: [.dinner], servings: 1,
                            ingredients: [RecipeIngredient(name: "garlic", foodId: "garlic", quantity: Quantity(10, .g))],
                            steps: [])]
        XCTAssertTrue(h.standardiseSavedRecipeUnitsOnce())
        XCTAssertEqual(h.recipes[0].ingredients[0].quantity, Quantity(2, .clove))
        h.recipes[0].ingredients[0].quantity = Quantity(10, .g)
        XCTAssertFalse(h.standardiseSavedRecipeUnitsOnce(), "Runs once, so later edits are left alone")
        XCTAssertEqual(h.recipes[0].ingredients[0].quantity, Quantity(10, .g))
    }
}
