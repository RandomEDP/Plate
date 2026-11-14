import XCTest
@testable import PlateCore

final class IngredientCatalogueTests: XCTestCase {
    func tidy(_ line: String) -> RecipeIngredient {
        UnitStandard.standardise(IngredientParser.ingredient(line)!)
    }

    func testCatalogueIsBigAndVegetarian() {
        XCTAssertGreaterThan(IngredientCatalogue.all.count, 400)
        for f in IngredientCatalogue.all {
            XCTAssertFalse([.meat, .fish].contains(f.category), "\(f.id) isn't vegetarian")
            XCTAssertNil(FoodDatabase.base.first { $0.id == f.id }, "\(f.id) is already in the original list")
        }
    }

    func testNoAliasBelongsToTwoFoods() {
        var owner: [String: String] = [:]
        for f in FoodDatabase.all {
            for a in Set(([f.name] + f.aliases).map(IngredientCatalogue.aliasKey)) where !a.isEmpty {
                if let other = owner[a], other != f.id { XCTFail("“\(a)” is in both \(other) and \(f.id)") }
                owner[a] = f.id
            }
        }
    }

    /// Ethan, 14 November 2026: "2 red chillies (converted from 30g of red chillies)".
    func testEthansChilliExample() {
        let ing = tidy("30g red chillies")
        XCTAssertEqual(ing.foodId, "chilli")
        XCTAssertEqual(ing.quantity, Quantity(2, .piece))
        XCTAssertEqual(ing.name, "red chillies")
        XCTAssertEqual(UnitStandard.convertedNote(ing), "Converted from 30g red chillies")
        XCTAssertEqual(UnitStandard.convertedNote(ing, scale: 2), "Converted from 60g red chillies", "Scales with the portions")
    }

    func testNewIngredientsMatch() {
        XCTAssertEqual(IngredientParser.ingredient("2 tbsp tahini")?.foodId, "tahini")
        XCTAssertEqual(IngredientParser.ingredient("1 tsp smoked paprika")?.foodId, "smoked-paprika")
        XCTAssertEqual(IngredientParser.ingredient("200g kale")?.foodId, "kale", "Kale is no longer spinach")
        XCTAssertEqual(IngredientParser.ingredient("1 tsp ground cumin")?.foodId, "ground-cumin")
        XCTAssertEqual(IngredientParser.ingredient("400ml vegetable stock")?.foodId, "veg-stock")
        XCTAssertEqual(IngredientParser.ingredient("1 vegetable stock cube")?.foodId, "stock-cube")
        XCTAssertEqual(IngredientParser.ingredient("2 tbsp rice wine vinegar")?.foodId, "rice-vinegar")
        XCTAssertEqual(IngredientParser.ingredient("200g black-eyed beans")?.foodId, "black-eyed-beans")
        XCTAssertEqual(IngredientParser.ingredient("1 tbsp black bean sauce")?.foodId, "black-bean-sauce")
        XCTAssertEqual(IngredientParser.ingredient("4 sprigs of fresh thyme")?.foodId, "thyme-fresh")
        XCTAssertEqual(IngredientParser.ingredient("1 tsp dried thyme")?.foodId, "dried-thyme")
        XCTAssertEqual(IngredientParser.ingredient("6 vegetarian sausages")?.foodId, "veggie-sausages")
        XCTAssertEqual(IngredientParser.ingredient("2 tbsp sun-dried tomato paste")?.foodId, "sun-dried-tomato-paste")
        XCTAssertEqual(IngredientParser.ingredient("50g goat's cheese")?.foodId, "goats-cheese")
    }

    func testCountedFoodsComeOutAsItems() {
        XCTAssertEqual(tidy("400g leeks").quantity, Quantity(2, .piece))
        XCTAssertEqual(tidy("100g aubergine").quantity, Quantity(0.5, .piece))
        XCTAssertEqual(tidy("80g celery sticks").quantity, Quantity(2, .piece))
        XCTAssertEqual(tidy("6g cinnamon sticks").quantity, Quantity(2, .piece))
    }

    func testWholeBulbOfGarlicIsTenCloves() {
        XCTAssertEqual(IngredientParser.ingredient("1 bulb of garlic")?.quantity, Quantity(10, .clove))
        XCTAssertEqual(IngredientParser.ingredient("2 heads garlic")?.quantity, Quantity(20, .clove))
        XCTAssertEqual(IngredientParser.ingredient("1 garlic bulb")?.quantity, Quantity(10, .clove))
        XCTAssertEqual(IngredientParser.ingredient("3 garlic cloves")?.quantity, Quantity(3, .piece), "Cloves aren't bulbs")
    }

    func testCupsBecomeGramsOnlyWhenThePlateKnowsTheWeight() {
        XCTAssertEqual(tidy("1 cup plain flour").quantity, Quantity(130, .g))
        XCTAssertEqual(tidy("1 cup oats").quantity, Quantity(95, .g))
        XCTAssertEqual(tidy("1 cup rocket").quantity, Quantity(19, .g))
        let unknown = tidy("1 cup tempeh")
        XCTAssertNil(unknown.convertedFrom)
    }

    func testSpoonsTinsAndCountsStay() {
        XCTAssertEqual(tidy("1 tsp cumin").quantity, Quantity(1, .tsp))
        XCTAssertEqual(tidy("1 tin butter beans").quantity, Quantity(1, .can))
        XCTAssertEqual(tidy("1 butternut squash").quantity, Quantity(1, .piece))
        XCTAssertNil(tidy("1 tsp cumin").convertedFrom)
    }

    func testLiquidsInGramsBecomeMl() {
        XCTAssertEqual(tidy("100g maple syrup").quantity, Quantity(75, .ml))
        XCTAssertEqual(tidy("8 fl oz oat cream").quantity, Quantity(225, .ml))
    }

    func testPluralsFollowTheCount() {
        XCTAssertEqual(Plural.fit("red chilli", to: 2), "red chillies")
        XCTAssertEqual(Plural.fit("onions", to: 0.5), "onion")
        XCTAssertEqual(Plural.fit("bay leaf", to: 3), "bay leaves")
        XCTAssertEqual(Plural.fit("celery", to: 3), "celery")
        XCTAssertEqual(Plural.fit("tomato", to: 2), "tomatoes")
        XCTAssertEqual(Plural.fit("cherry", to: 2), "cherries")
    }

    func testBuiltInRecipesDontShowConversions() {
        XCTAssertTrue(BuiltInRecipes.all.allSatisfy { $0.ingredients.allSatisfy { $0.convertedFrom == nil } })
    }

    // MARK: Putting a conversion right

    func recipe(_ lines: [String]) -> Recipe {
        Recipe(name: "Test", mealTypes: [.dinner], servings: 2, ingredients: UnitStandard.tidy(lines.compactMap(IngredientParser.ingredient)), steps: [])
    }

    func testUndoingAConversion() {
        let r = recipe(["30g red chillies"])
        let back = r.undoingConversion(of: r.ingredients[0].id)
        XCTAssertEqual(back.ingredients[0].quantity, Quantity(30, .g))
        XCTAssertNil(back.ingredients[0].convertedFrom)
        XCTAssertEqual(back.ingredients[0].id, r.ingredients[0].id)
    }

    func testConfirmingHidesTheNote() {
        let r = recipe(["30g red chillies"])
        let ok = r.confirming(r.ingredients[0].id)
        XCTAssertEqual(ok.ingredients[0].quantity, Quantity(2, .piece))
        XCTAssertNil(ok.ingredients[0].convertedFrom)
    }

    func testTypingANewAmount() {
        let r = recipe(["30g red chillies", "20g garlic"])
        XCTAssertEqual(r.settingAmount(of: r.ingredients[0].id, to: "3")?.ingredients[0].quantity, Quantity(3, .piece))
        XCTAssertEqual(r.settingAmount(of: r.ingredients[0].id, to: "45g")?.ingredients[0].quantity, Quantity(45, .g))
        XCTAssertEqual(r.settingAmount(of: r.ingredients[1].id, to: "6")?.ingredients[1].quantity, Quantity(6, .clove))
        XCTAssertNil(r.settingAmount(of: r.ingredients[0].id, to: "  "))
    }
}

final class GuessCheckTests: XCTestCase {
    let caption = """
    Smoky bean chilli
    Ingredients:
    1 tin black beans
    2 red onions
    smoked paprika
    a splash of oat milk
    """

    func aiRecipe(_ lines: [String], servings: Int = 4) -> Recipe {
        Recipe(name: "Smoky bean chilli", mealTypes: [.dinner], servings: servings,
               ingredients: UnitStandard.tidy(lines.compactMap(IngredientParser.ingredient)), steps: [])
    }

    /// Ethan, 14 November 2026: mark the amounts that were guessed.
    func testAmountsNotInTheCaptionAreMarkedGuessed() {
        let r = GuessCheck.check(aiRecipe(["400g black beans", "2 red onions", "2 tsp smoked paprika"]),
                                 against: caption, parsed: RecipeTextParser.parse(caption))
        XCTAssertFalse(r.ingredients[0].isGuessed, "1 tin is about 400 g, so that's the caption's amount")
        XCTAssertFalse(r.ingredients[1].isGuessed)
        XCTAssertTrue(r.ingredients[2].isGuessed, "The caption gives no amount of paprika")
        XCTAssertEqual(r.guessedCount, 1)
    }

    func testPlatesOwnReadingWinsOverAWrongAmount() {
        let r = GuessCheck.check(aiRecipe(["5 red onions"]), against: caption, parsed: RecipeTextParser.parse(caption))
        XCTAssertEqual(r.ingredients[0].quantity, Quantity(2, .piece))
        XCTAssertFalse(r.ingredients[0].isGuessed)
    }

    func testPortionsDefaultToTwoWhenTheCaptionDoesntSay() {
        let r = GuessCheck.check(aiRecipe(["2 red onions"], servings: 6), against: caption, parsed: RecipeTextParser.parse(caption))
        XCTAssertEqual(r.servings, 2)
        XCTAssertEqual(r.servingsGuessed, true)
        let parsed = RecipeTextParser.parse(caption).recipe(source: RecipeSource(kind: .manual))
        XCTAssertEqual(parsed.servings, 2)
        XCTAssertEqual(parsed.servingsGuessed, true)
    }

    func testStatedPortionsAreKept() {
        let text = caption + "\nServes 4"
        let r = GuessCheck.check(aiRecipe(["2 red onions"], servings: 4), against: text, parsed: RecipeTextParser.parse(text))
        XCTAssertEqual(r.servings, 4)
        XCTAssertNil(r.servingsGuessed)
        XCTAssertEqual(GuessCheck.servings(parsed: nil, ai: 3, text: "Makes 3 lunches").count, 3)
    }

    func testNumbersInALine() {
        XCTAssertEqual(GuessCheck.numbers(in: "1 1/2 cups and ½ tsp, 200g, two eggs").sorted(), [0.5, 1.5, 2, 200])
        XCTAssertEqual(GuessCheck.numbers(in: "1½ onions"), [1.5])
    }

    func testOldFilesStillOpen() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","name":"garlic","foodId":"garlic","quantity":{"amount":2,"unit":"clove"},"optional":false}"#
        let ing = try JSONDecoder().decode(RecipeIngredient.self, from: Data(json.utf8))
        XCTAssertNil(ing.convertedFrom)
        XCTAssertFalse(ing.isGuessed)
    }

    func testSavedRecipesAreUpgradedOnce() {
        var h = Household()
        h.recipes = [Recipe(name: "Old", mealTypes: [.dinner], servings: 1, ingredients: [
            RecipeIngredient(name: "garlic", foodId: "garlic", quantity: Quantity(3, .clove), note: "crushed; recipe said 15g"),
            RecipeIngredient(name: "tahini", foodId: nil, quantity: Quantity(2, .tbsp)),
            RecipeIngredient(name: "leeks", foodId: nil, quantity: Quantity(400, .g)),
        ], steps: [])]
        XCTAssertTrue(h.upgradeIngredientsOnce())
        let ings = h.recipes[0].ingredients
        XCTAssertEqual(ings[0].convertedFrom, Quantity(15, .g))
        XCTAssertEqual(ings[0].note, "crushed")
        XCTAssertEqual(ings[1].foodId, "tahini")
        XCTAssertEqual(ings[2].quantity, Quantity(2, .piece))
        XCTAssertEqual(ings[2].convertedFrom, Quantity(400, .g))
        XCTAssertFalse(h.upgradeIngredientsOnce())
    }
}
