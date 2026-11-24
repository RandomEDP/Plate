import XCTest
@testable import PlateCore

/// Captions that list each part of the dish on one line ("SMOKY TOFU: 1 block smoked tofu, …"). Ethan's reel of
/// smoky mango tofu tacos (24 November 2026) was saved as "Got the gravy ick" with almost no ingredients and 7 kcal.
final class CaptionSectionsTests: XCTestCase {
    let tacos = """
    Got the gravy ick? 😅 The feed is full of potatoes and gravy right now, so here’s an injection of flavour instead. Smoky mango tofu tacos, really easy and ready in 20 mins 🌮🥭

    SMOKY TOFU: 1 block smoked tofu (crumbled), 1 tsp each of smoked paprika, onion granules, garlic granules, oregano and cumin, 1 tbsp maple or golden syrup, 1 tbsp soy sauce, drizzle of olive oil

    MANGO SALSA: 1 mango, handful of coriander, 1/2 tomato, 1/2 red pepper, 2 garlic cloves, juice of 1/2 lime, 1/3 red onion, handful of jalapeños, salt, sprinkle of sugar

    AVOCADO CREMA: 1 avocado, 1 large garlic clove, handful of coriander, juice of 1/2 lime, 1 heaped tbsp vegan yoghurt, salt & pepper

    PICO DE GALLO: 1 large tomato, 1/2 red onion, chopped jalapeños, coriander, salt, pepper, olive oil, squeeze of lime

    To serve: shop-bought soft taco shells

    1. Toss the crumbled tofu in all the seasonings, then air fry at 180°C for 12-15 mins, shaking halfway.
    2. Blitz the salsa ingredients together.
    3. Blitz the crema ingredients together.
    4. Finely chop the pico ingredients and mix together.
    5. Load up your tacos with tofu, salsa, crema and pico.

    P.S. I made some quick mini soft breads for mine but didn’t measure a thing, and this one’s meant to be quickkk, so shop-bought is perfect 🙌

    Follow along for some delishhhhh vegan recipes, comfort and packed full of flavour… a girl that can do both 😉

    #vegantacos #tofutacos #plantbased #veganrecipes #quickdinner
    """

    func ingredient(_ r: ParsedRecipe, _ foodId: String) -> RecipeIngredient? { r.ingredients.first { $0.foodId == foodId } }

    func testTacoReel() {
        let r = RecipeTextParser.parse(tacos)
        XCTAssertEqual(r.name, "Smoky mango tofu tacos")
        XCTAssertEqual(r.minutes, 20)
        XCTAssertNil(r.servings)
        XCTAssertGreaterThanOrEqual(r.ingredients.count, 22, r.ingredients.map(\.name).joined(separator: " | "))
        let ids = Set(r.ingredients.compactMap(\.foodId))
        for id in ["tofu", "onion-powder", "garlic-powder", "dried-oregano", "soy-sauce", "olive-oil", "mango", "coriander",
                   "tomato", "pepper", "garlic", "lime", "red-onion", "salt", "sugar", "avocado", "coconut-yoghurt", "taco-shells"] {
            XCTAssertTrue(ids.contains(id), "missing \(id)")
        }
        // "1 tsp each of" shared out to all five spices.
        for name in ["smoked paprika", "onion granules", "garlic granules", "oregano", "cumin"] {
            let ing = r.ingredients.first { $0.name.lowercased() == name }
            XCTAssertEqual(ing?.quantity, Quantity(1, .tsp), name)
        }
        XCTAssertEqual(ingredient(r, "tofu")?.quantity?.unit, .pack)
        XCTAssertEqual(ingredient(r, "mango")?.quantity, Quantity(1, .piece))
        XCTAssertEqual(ingredient(r, "lime")?.quantity, Quantity(0.5, .piece))
        XCTAssertEqual(ingredient(r, "lime")?.note, "juice")
        XCTAssertEqual(ingredient(r, "coconut-yoghurt")?.quantity, Quantity(1, .tbsp))
        XCTAssertEqual(ingredient(r, "pepper")?.quantity, Quantity(0.5, .piece))
        XCTAssertTrue(ids.contains("black-pepper"), "a bare \"pepper\" is black pepper")
        // The method, without the P.S. or the sign-off.
        XCTAssertEqual(r.steps.count, 5, r.steps.joined(separator: " | "))
        XCTAssertTrue(r.steps[0].hasPrefix("Toss the crumbled tofu"))
        XCTAssertFalse(r.ingredients.contains { $0.name.lowercased().contains("toss") })
        XCTAssertTrue(r.tags.contains("vegantacos"))
        // Saved, it has real macros, not 7 kcal.
        let recipe = r.recipe(source: RecipeSource(kind: .instagram, url: "https://www.instagram.com/reel/x/"))
        XCTAssertTrue(recipe.servingsGuessed)
        XCTAssertGreaterThan(Nutrition.perServing(recipe).kcal, 150)
        XCTAssertFalse(ImportRepair.looksThin(recipe))
    }

    func testHookQuestionIsNotTheTitle() {
        XCTAssertTrue(RecipeTextParser.isHook("Got the gravy ick", in: tacos))
        XCTAssertFalse(RecipeTextParser.isHook("Smoky mango tofu tacos", in: tacos))
        let r = RecipeTextParser.parse("Want the easiest dinner ever? Creamy pesto gnocchi 😍\n200g gnocchi\n2 tbsp pesto")
        XCTAssertEqual(r.name, "Creamy pesto gnocchi")
        // A question is still used when there's nothing else.
        XCTAssertEqual(RecipeTextParser.parse("Ever tried halloumi fries?\n250g halloumi\n1 tbsp flour").name, "Ever tried halloumi fries")
    }

    func testTitleKeepsAShortCommaName() {
        let r = RecipeTextParser.parse("Halloumi, pepper and rice bowl\n250g halloumi\n1 red pepper\n100g rice")
        XCTAssertEqual(r.name, "Halloumi, pepper and rice bowl")
    }

    func testEachSharedOut() {
        XCTAssertEqual(RecipeTextParser.expandEach(["1 tsp each of paprika", "cumin", "oregano and chilli flakes", "1 tbsp oil"]),
                       ["1 tsp paprika", "1 tsp cumin", "1 tsp oregano", "1 tsp chilli flakes", "1 tbsp oil"])
        XCTAssertEqual(RecipeTextParser.expandEach(["2 tbsp each soy sauce and honey"]), ["2 tbsp soy sauce", "2 tbsp honey"])
        // No amount before "each": left alone.
        XCTAssertEqual(RecipeTextParser.expandEach(["peppers, each sliced"]), ["peppers, each sliced"])
        let r = RecipeTextParser.parse("Ingredients:\n2 tbsp each soy sauce and honey\n300g chicken breast")
        XCTAssertEqual(r.ingredients.compactMap(\.foodId), ["soy-sauce", "honey", "chicken-breast"])
        XCTAssertEqual(r.ingredients.first?.quantity, Quantity(2, .tbsp))
    }

    func testInlineListsNeedToBeIngredients() {
        XCTAssertNil(RecipeTextParser.inlineList("Tip: add a splash of water, then stir", inIngredients: true))
        XCTAssertNil(RecipeTextParser.inlineList("Serves: 4", inIngredients: true))
        XCTAssertNil(RecipeTextParser.inlineList("Prep time: 10 mins, cook time: 20 mins", inIngredients: false))
        XCTAssertNil(RecipeTextParser.inlineList("Honestly: this is the best thing I've made all year, no joke", inIngredients: false))
        // A single item only once the ingredients have started.
        XCTAssertNil(RecipeTextParser.inlineList("To serve: soft taco shells", inIngredients: false))
        XCTAssertEqual(RecipeTextParser.inlineList("To serve: soft taco shells", inIngredients: true)?.first?.foodId, "taco-shells")
        let sauce = RecipeTextParser.inlineList("For the sauce: 2 tbsp soy sauce, 1 tbsp honey, 1 garlic clove (grated, or crushed)", inIngredients: false)
        XCTAssertEqual(sauce?.compactMap(\.foodId), ["soy-sauce", "honey", "garlic"])
        XCTAssertEqual(sauce?.last?.note, "grated, or crushed")
    }

    func testSplitInlineKeepsBrackets() {
        XCTAssertEqual(RecipeTextParser.splitInline("1 onion (red, or white), 2 eggs; salt"), ["1 onion (red, or white)", "2 eggs", "salt"])
    }

    func testNumberedStepsEndTheIngredients() {
        let r = RecipeTextParser.parse("Tofu tacos\nIngredients:\n1 block tofu\n2 tbsp soy sauce\n1. Fry the tofu until golden and crispy all over.\n2. Add the soy sauce.")
        XCTAssertEqual(r.ingredients.compactMap(\.foodId), ["tofu", "soy-sauce"])
        XCTAssertEqual(r.steps, ["Fry the tofu until golden and crispy all over.", "Add the soy sauce."])
    }

    func testJuiceZestAndSpoonSizes() {
        let juice = IngredientParser.parse("juice of 1/2 lime")
        XCTAssertEqual(juice?.food?.id, "lime")
        XCTAssertEqual(juice?.quantity, Quantity(0.5, .piece))
        XCTAssertEqual(juice?.note, "juice")
        let zest = IngredientParser.parse("Zest and juice of 1 lemon")
        XCTAssertEqual(zest?.quantity, Quantity(1, .piece))
        XCTAssertEqual(zest?.note, "zest and juice")
        let heaped = IngredientParser.parse("1 heaped tbsp vegan yoghurt")
        XCTAssertEqual(heaped?.quantity, Quantity(1, .tbsp))
        XCTAssertEqual(heaped?.food?.id, "coconut-yoghurt")
        XCTAssertEqual(heaped?.note, "heaped")
        // "large" before a food, not a spoon, stays with the food.
        XCTAssertEqual(IngredientParser.parse("1 large garlic clove")?.food?.id, "garlic")
        XCTAssertEqual(IngredientParser.parse("pepper")?.food?.id, "black-pepper")
        XCTAssertEqual(IngredientParser.parse("1 red pepper")?.food?.id, "pepper")
    }

    func testThinImportsAreReadAgainOnce() {
        let link = "https://www.instagram.com/reel/DgHk58YNrcI/"
        let thin = Recipe(name: "Got the gravy ick", mealTypes: [.dinner], servings: 2,
                          ingredients: [RecipeIngredient(name: "coriander", foodId: "coriander", quantity: nil),
                                        RecipeIngredient(name: "lime", foodId: "lime", quantity: Quantity(0.5, .piece))],
                          steps: [], minutes: 20, tags: [], source: RecipeSource(kind: .instagram, url: link))
        XCTAssertTrue(ImportRepair.looksThin(thin))
        var typed = thin
        typed.source = RecipeSource(kind: .manual)
        XCTAssertFalse(ImportRepair.looksThin(typed), "only imports with a link can be read again")

        let fresh = RecipeTextParser.parse(tacos).recipe(source: RecipeSource(kind: .instagram, url: link))
        XCTAssertTrue(ImportRepair.isBetter(fresh, than: thin))
        XCTAssertFalse(ImportRepair.isBetter(thin, than: fresh))

        var h = Household()
        h.recipes = [thin, fresh]
        XCTAssertEqual(h.thinImportsToReread.map(\.id), [thin.id])
        h.markThinImportsReread()
        XCTAssertTrue(h.thinImportsToReread.isEmpty)
        // Replacing keeps the id, so the plan and lists still point at it.
        var h2 = Household()
        h2.recipes = [thin]
        XCTAssertTrue(h2.replaceRecipe(thin.id, with: fresh))
        XCTAssertEqual(h2.recipes[0].id, thin.id)
        XCTAssertEqual(h2.recipes[0].name, "Smoky mango tofu tacos")
    }
}
