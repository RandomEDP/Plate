import XCTest
@testable import PlateCore

/// Ethan, 14 November 2026: "there should be a sauces filter like breakfast dinner etc".
final class SaucesTests: XCTestCase {
    func recipe(_ name: String, meals: [MealType] = [.dinner, .lunch], tags: [String] = []) -> Recipe {
        Recipe(name: name, mealTypes: meals, servings: 2,
               ingredients: [RecipeIngredient(name: "olive oil", foodId: nil, quantity: nil)], steps: [], tags: tags)
    }

    func testSauceNamesAreSpotted() {
        for name in ["Burger Sauce", "Honey mustard dressing", "Basil Pesto", "Spicy Mayo", "Chimichurri",
                     "Sweet and sour sauce", "Garlic & herb dip", "Garlic chilli oil", "Salsa verde", "Hummus",
                     "Chicken marinade", "Big Mac sauce recipe 🍔", "Peri peri sauce (vegan)", "Tzatziki", "Pasta sauce",
                     "Buffalo chicken dip", "Easy 5 minute satay sauce"] {
            XCTAssertTrue(Sauces.looksLike(name: name), name)
        }
    }

    func testDishesWithASauceAreNotSauces() {
        for name in ["Salmon with pesto", "Chicken in garlic sauce", "Pesto pasta", "Peanut sauce noodles",
                     "Chicken pesto", "Tuna mayo", "Nachos and salsa", "Chips 'n' dip", "Hummus bowl",
                     "Spaghetti bolognese", "Chicken teriyaki", "Overnight oats", "Salad topped with dressing"] {
            XCTAssertFalse(Sauces.looksLike(name: name), name)
        }
    }

    func testIsSauceIsATag() {
        var r = recipe("Gravy")
        XCTAssertFalse(r.isSauce)
        r.isSauce = true
        XCTAssertEqual(r.tags, ["sauce"])
        r.isSauce = true
        XCTAssertEqual(r.tags, ["sauce"], "Not added twice")
        r.isSauce = false
        XCTAssertEqual(r.tags, [])
        XCTAssertTrue(recipe("x", tags: ["Sauce"]).isSauce)
    }

    func testSaucesDontFitAnyMeal() {
        var r = recipe("Chimichurri")
        XCTAssertTrue(r.fits(.dinner))
        r.isSauce = true
        for meal in MealType.allCases { XCTAssertFalse(r.fits(meal)) }
    }

    func testImportedCaptionIsTaggedFromItsName() {
        let sauce = RecipeTextParser.parse("""
        Creamy garlic sauce 🧄
        Ingredients:
        4 garlic cloves
        200ml double cream
        30g parmesan
        """).recipe(source: RecipeSource(kind: .instagram))
        XCTAssertTrue(sauce.isSauce)

        let dish = RecipeTextParser.parse("""
        Creamy chicken pasta
        Ingredients:
        2 chicken breasts
        200g penne
        200ml double cream
        #sauce #pasta
        """).recipe(source: RecipeSource(kind: .instagram))
        XCTAssertFalse(dish.isSauce, "A #sauce hashtag on a dish doesn't make it a sauce")
        XCTAssertTrue(dish.tags.contains("pasta"))
    }

    func testPlannerNeverPlansASauce() {
        var sauce = recipe("Burger sauce")
        sauce.isSauce = true
        let dinner = recipe("Chilli con carne")
        let settings = PlanSettings(people: 1, breakfasts: 0, lunches: 7, dinners: 7, snacks: 0)
        for seed in 1...20 {
            let plan = Planner.generate(recipes: [sauce, dinner], inventory: [],
                                        options: Planner.Options(settings: settings, seed: UInt64(seed)), now: Date())
            XCTAssertFalse(plan.contains { $0.recipeId == sauce.id }, "seed \(seed)")
            XCTAssertFalse(plan.isEmpty)
        }
    }

    func testSuggestionsForAMealLeaveSaucesOut() {
        var sauce = recipe("Pesto")
        sauce.isSauce = true
        let ranked = Suggestions.rank([sauce, recipe("Stir fry")], inventory: [], now: Date(), mealType: .dinner)
        XCTAssertEqual(ranked.map(\.recipe.name), ["Stir fry"])
        XCTAssertEqual(Suggestions.rank([sauce], inventory: [], now: Date()).count, 1, "Still there with no meal chosen")
    }

    func testSavedSaucesAreTaggedOnce() {
        var h = Household()
        h.recipes = [recipe("Burger sauce"), recipe("Chicken curry")]
        XCTAssertTrue(h.markSavedSaucesOnce())
        XCTAssertEqual(h.recipes.map(\.isSauce), [true, false])
        h.recipes[0].isSauce = false
        XCTAssertFalse(h.markSavedSaucesOnce(), "Runs once, so untagging one sticks")
        XCTAssertFalse(h.recipes[0].isSauce)
    }

    func testSharedLinkKeepsItASauce() throws {
        var r = recipe("Chimichurri")
        r.ingredients.append(RecipeIngredient(name: "parsley", foodId: nil, quantity: nil))
        r.isSauce = true
        let code = try XCTUnwrap(RecipeShare.code(for: r))
        XCTAssertTrue(try XCTUnwrap(RecipeShare.recipe(fromCode: code)).isSauce)
    }
}
