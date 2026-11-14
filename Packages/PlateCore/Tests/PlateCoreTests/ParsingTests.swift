import XCTest
@testable import PlateCore

final class IngredientParserTests: XCTestCase {
    func check(_ line: String, _ amount: Double?, _ unit: MeasureUnit?, food: String?, file: StaticString = #filePath, line l: UInt = #line) {
        let r = IngredientParser.parse(line)
        XCTAssertNotNil(r, "Couldn't read “\(line)”", file: file, line: l)
        if let amount {
            XCTAssertEqual(r?.quantity?.amount ?? -1, amount, accuracy: 0.01, "amount for “\(line)”", file: file, line: l)
        } else {
            XCTAssertNil(r?.quantity, "“\(line)” should have no amount", file: file, line: l)
        }
        if let unit { XCTAssertEqual(r?.quantity?.unit, unit, "unit for “\(line)”", file: file, line: l) }
        XCTAssertEqual(r?.food?.id, food, "food for “\(line)”", file: file, line: l)
    }

    func testCommonLines() {
        check("200g chicken breast, diced", 200, .g, food: "chicken-breast")
        check("- 2 tbsp olive oil", 2, .tbsp, food: "olive-oil")
        check("• 1 tin chopped tomatoes", 1, .can, food: "chopped-tomatoes")
        check("2 x 400g tins chopped tomatoes", 800, .g, food: "chopped-tomatoes")
        check("1/2 tsp chilli flakes", 0.5, .tsp, food: "chilli-flakes")
        check("1½ cups milk", 1.5, .cup, food: "milk")
        check("1 1/2 cups rolled oats", 1.5, .cup, food: "oats")
        check("3 garlic cloves, minced", 3, .piece, food: "garlic")
        check("2 cloves garlic", 2, .clove, food: "garlic")
        check("1-2 red chillies", 2, .piece, food: "chilli")
        check("3 large eggs", 3, .piece, food: "eggs")
        check("Salt and pepper to taste", nil, nil, food: "salt")
        check("Chicken thighs: 500g", 500, .g, food: "chicken-thigh")
        check("Oats (40g)", 40, .g, food: "oats")
        check("1kg sweet potatoes", 1, .kg, food: "sweet-potato")
        check("250ml coconut milk", 250, .ml, food: "coconut-milk")
        check("2 scoops vanilla protein powder", 2, .piece, food: "protein-powder")
        check("a pinch of salt", 1, .pinch, food: "salt")
        check("handful of fresh coriander", 1, .handful, food: "coriander")
        check("half a lemon, juiced", 0.5, .piece, food: "lemon")
        check("2 red onions", 2, .piece, food: "red-onion")
        check("1 tbsp peanut butter", 1, .tbsp, food: "peanut-butter")
        check("100g cream cheese", 100, .g, food: "cream-cheese")
        check("1 tsp sesame oil", 1, .tsp, food: "sesame-oil")
        check("400g 5% beef mince", 400, .g, food: "beef-mince")
        check("150g 0% greek yoghurt", 150, .g, food: "greek-yoghurt")
        check("2 chicken stock cubes", 2, .piece, food: "stock-cube")
        check("1 tbsp sweet chilli sauce", 1, .tbsp, food: "sweet-chilli")
        check("2 spring onions", 2, .piece, food: "spring-onion")
        check("1 x 400ml tin light coconut milk", 400, .ml, food: "coconut-milk")
        check("80g cheddar cheese, grated", 80, .g, food: "cheddar")
        check("1 red pepper", 1, .piece, food: "pepper")
        check("Juice of 1 lime", nil, nil, food: "lime")
        check("2 pouches microwave rice", 2, .pack, food: "microwave-rice")
        check("1lb lean ground beef", 1, .lb, food: "beef-mince")
        check("4oz cheddar", 4, .oz, food: "cheddar")
    }

    func testOptionalAndNotes() {
        let r = IngredientParser.parse("50g feta (optional)")
        XCTAssertEqual(r?.optional, true)
        XCTAssertEqual(r?.food?.id, "feta")
        let n = IngredientParser.parse("2 peppers, thinly sliced")
        XCTAssertEqual(n?.note, "thinly sliced")
        XCTAssertEqual(n?.name, "peppers")
    }

    func testNotIngredients() {
        XCTAssertNil(IngredientParser.parse("This is honestly the best thing I've ever made"))
        XCTAssertNil(IngredientParser.parse(""))
    }

    func testUnitConversions() {
        let chicken = FoodDatabase.byId["chicken-breast"]!
        XCTAssertEqual(Units.grams(Quantity(2, .piece), food: chicken)!, 320, accuracy: 0.1)
        let eggs = FoodDatabase.byId["eggs"]!
        XCTAssertEqual(Units.amountInFoodUnit(Quantity(116, .g), food: eggs)!, 2, accuracy: 0.01)
        let tuna = FoodDatabase.byId["tuna"]!
        XCTAssertEqual(Units.grams(Quantity(2, .can), food: tuna)!, 224, accuracy: 0.1)
        let oil = FoodDatabase.byId["olive-oil"]!
        XCTAssertEqual(Units.grams(Quantity(1, .tbsp), food: oil)!, 13.65, accuracy: 0.01)
        let halloumi = FoodDatabase.byId["halloumi"]!
        XCTAssertEqual(Units.grams(Quantity(1, .pack), food: halloumi)!, 225, accuracy: 0.1)
    }

    func testFormat() {
        XCTAssertEqual(Format.amount(1500, .g), "1.5 kg")
        XCTAssertEqual(Format.amount(250, .g), "250 g")
        XCTAssertEqual(Format.amount(0.5, .piece), "½")
        XCTAssertEqual(Format.amount(2272, .ml), "2.27 l")
        XCTAssertEqual(Format.money(3.5), "£3.50")
    }

    func testFoodDatabaseIsConsistent() {
        XCTAssertEqual(Set(FoodDatabase.all.map(\.id)).count, FoodDatabase.all.count, "Duplicate food ids")
        for f in FoodDatabase.all {
            if f.unit == .piece { XCTAssertNotNil(f.gramsPerPiece, "\(f.id) is counted but has no weight per piece") }
            for p in f.packs { XCTAssertGreaterThan(p.size, 0); XCTAssertGreaterThan(p.price, 0) }
            if !f.isStaple && f.id != "water" { XCTAssertFalse(f.packs.isEmpty, "\(f.id) has no packs to buy") }
            // Macros roughly add up (4/4/9), allowing for fibre and rounding.
            let est = f.per100.protein * 4 + f.per100.carbs * 4 + f.per100.fat * 9
            if f.per100.kcal > 50, !IngredientCatalogue.alcoholic.contains(f.id) { XCTAssertEqual(est, f.per100.kcal, accuracy: f.per100.kcal * 0.3 + 15, "\(f.id) macros don't add up") }
        }
    }

    func testEveryAliasFindsItsOwnFood() {
        for f in FoodDatabase.all {
            for a in f.aliases {
                let found = FoodMatcher.match(a)?.id
                // A handful of aliases are shared words; they just need to land somewhere sensible.
                if found != f.id { XCTFail("Alias “\(a)” matched \(found ?? "nothing") instead of \(f.id)") }
            }
        }
    }
}

final class RecipeTextParserTests: XCTestCase {
    let tiktok = """
    High Protein Chicken Fajita Bowls 🌯🔥 Only 520 cals!

    Ingredients (makes 4):
    - 600g chicken breast
    - 2 tbsp fajita seasoning
    - 3 peppers, sliced
    - 1 red onion
    - 250g basmati rice (uncooked)
    - 1 tin black beans
    - 150g 0% greek yoghurt
    - Juice of 1 lime

    Method:
    1. Season the chicken and air fry at 200C for 15 mins.
    2. Fry the peppers and onion.
    3. Cook the rice, then divide everything between 4 boxes.

    Macros per serving: 520 kcal | 48g protein | 62g carbs | 7g fat

    Follow @mealprepmike for more! #mealprep #highprotein #fajitas
    """

    func testStructuredCaption() {
        let r = RecipeTextParser.parse(tiktok)
        XCTAssertEqual(r.name, "High Protein Chicken Fajita Bowls")
        XCTAssertEqual(r.servings, 4)
        XCTAssertEqual(r.ingredients.count, 8)
        XCTAssertEqual(r.ingredients.compactMap(\.foodId), ["chicken-breast", "fajita-seasoning", "pepper", "red-onion", "rice", "black-beans", "greek-yoghurt", "lime"])
        XCTAssertEqual(r.steps.count, 3)
        XCTAssertEqual(r.steps.first, "Season the chicken and air fry at 200C for 15 mins.")
        XCTAssertEqual(r.statedPerServing?.kcal, 520)
        XCTAssertEqual(r.statedPerServing?.protein, 48)
        XCTAssertEqual(r.statedPerServing?.carbs, 62)
        XCTAssertEqual(r.statedPerServing?.fat, 7)
        XCTAssertTrue(r.tags.contains("mealprep"))
        XCTAssertTrue(r.looksLikeRecipe)
        let recipe = r.recipe(source: RecipeSource(kind: .tiktok))
        XCTAssertTrue(recipe.mealPrepFriendly)
        XCTAssertEqual(Nutrition.perServing(recipe).kcal, 520)
    }

    func testCaptionWithoutHeaders() {
        let text = """
        Creamy garlic tuscan salmon pasta 😍 Ready in 20 minutes and serves 2

        200g pasta
        2 salmon fillets
        3 garlic cloves
        100g sun dried tomatoes
        60g spinach
        150ml double cream
        30g parmesan

        Cook the pasta. Pan fry the salmon skin side down for 4 mins each side and set aside. Fry the garlic and tomatoes, add the cream and parmesan, then stir in the spinach and pasta. Flake the salmon on top.

        Save this for later!
        """
        let r = RecipeTextParser.parse(text)
        XCTAssertEqual(r.name, "Creamy garlic tuscan salmon pasta")
        XCTAssertEqual(r.servings, 2)
        XCTAssertEqual(r.minutes, 20)
        XCTAssertEqual(r.ingredients.compactMap(\.foodId), ["pasta", "salmon", "garlic", "sun-dried-tomatoes", "spinach", "double-cream", "parmesan"])
        XCTAssertEqual(r.steps.count, 1)
        XCTAssertTrue(r.steps[0].hasPrefix("Cook the pasta"))
        XCTAssertNil(r.statedPerServing)
    }

    func testInlineIngredientsAndRunTogetherSteps() {
        let text = "PB banana overnight oats\nIngredients: 50g oats, 150ml milk, 1 banana, 1 tbsp peanut butter\nMethod: 1. Mix everything in a jar. 2. Leave overnight. 3. Top with banana.\nP: 20g C: 70g F: 14g 480 calories"
        let r = RecipeTextParser.parse(text)
        XCTAssertEqual(r.ingredients.compactMap(\.foodId), ["oats", "milk", "banana", "peanut-butter"])
        XCTAssertEqual(r.steps.count, 3)
        XCTAssertEqual(r.statedPerServing?.kcal, 480)
        XCTAssertEqual(r.statedPerServing?.protein, 20)
        XCTAssertEqual(r.mealTypes, [.breakfast])
    }

    func testEmojiStepsAndSubheadings() {
        let text = """
        Teriyaki salmon bowls 🍣
        You'll need:
        For the salmon:
        2 salmon fillets
        3 tbsp soy sauce
        1 tbsp honey
        For the bowl:
        150g rice
        1 avocado
        Instructions
        1️⃣ Cook the rice
        2️⃣ Glaze the salmon and bake for 12 mins
        3️⃣ Build your bowls
        """
        let r = RecipeTextParser.parse(text)
        XCTAssertEqual(r.ingredients.compactMap(\.foodId), ["salmon", "soy-sauce", "honey", "rice", "avocado"])
        XCTAssertEqual(r.steps, ["Cook the rice", "Glaze the salmon and bake for 12 mins", "Build your bowls"])
    }

    func testBuiltInRecipesAllParse() {
        XCTAssertGreaterThanOrEqual(BuiltInRecipes.all.count, 35)
        for (recipe, spec) in zip(BuiltInRecipes.all, BuiltInRecipes.specs) {
            XCTAssertEqual(recipe.ingredients.count, spec.ingredients.count, "\(recipe.name): a line didn't parse")
            for (ing, line) in zip(recipe.ingredients, spec.ingredients) {
                XCTAssertNotNil(ing.foodId, "\(recipe.name): “\(line)” matched no food")
                if !line.contains("to taste") { XCTAssertNotNil(ing.quantity, "\(recipe.name): “\(line)” has no amount") }
            }
            let (_, coverage) = Nutrition.computed(recipe)
            XCTAssertEqual(coverage, 1, accuracy: 0.001, "\(recipe.name): some ingredients couldn't be counted")
            let kcal = Nutrition.perServing(recipe).kcal
            XCTAssertTrue((100...1100).contains(kcal), "\(recipe.name): \(Int(kcal)) kcal a serving looks wrong")
        }
    }

    func testSpecificNutrition() {
        let oats = BuiltInRecipes.all.first { $0.name == "Protein overnight oats" }!
        let m = Nutrition.perServing(oats)
        XCTAssertEqual(m.kcal, 410, accuracy: 60)
        XCTAssertEqual(m.protein, 25, accuracy: 6)
    }
}

final class SocialImportTests: XCTestCase {
    func testLinks() {
        let (u, p) = SocialImport.link(in: "Check this out https://www.instagram.com/reel/C9xYz123AbC/?igsh=abc")!
        XCTAssertEqual(p, .instagram)
        XCTAssertEqual(SocialImport.instagramCode(u), "C9xYz123AbC")
        XCTAssertEqual(SocialImport.instagramEmbedURL(for: u)?.absoluteString, "https://www.instagram.com/p/C9xYz123AbC/embed/captioned/")
        let (t, tp) = SocialImport.link(in: "https://vm.tiktok.com/ZMabc123/")!
        XCTAssertEqual(tp, .tiktok)
        XCTAssertTrue(SocialImport.tiktokOEmbedURL(for: t)!.absoluteString.hasPrefix("https://www.tiktok.com/oembed?url=https"))
        XCTAssertEqual(SocialImport.link(in: "tiktok.com/@chef/video/123")?.1, .tiktok)
        XCTAssertNil(SocialImport.link(in: "no link here"))
    }

    func testTikTokOEmbed() {
        let json = #"{"version":"1.0","type":"video","title":"Easy chicken wraps 🌯 Ingredients: 200g chicken breast, 2 wraps #fyp","author_name":"Chef Sam"}"#
        let c = SocialImport.captionFromTikTokOEmbed(Data(json.utf8))
        XCTAssertEqual(c?.author, "Chef Sam")
        XCTAssertTrue(c?.text.hasPrefix("Easy chicken wraps") ?? false)
        let r = RecipeTextParser.parse(c!.text)
        XCTAssertEqual(r.ingredients.compactMap(\.foodId), ["chicken-breast", "wraps"])
    }

    func testInstagramEmbedHTML() {
        let html = """
        <div class="Caption"><a class="CaptionUsername" href="https://www.instagram.com/fitfoodie/" target="_blank">fitfoodie</a><br /><br />Garlic butter steak bites &#x1f525;<br /><br />Ingredients:<br />500g sirloin steak<br />2 tbsp butter<br />4 garlic cloves<br /><br />Method:<br />1. Sear the steak<br />2. Add butter and garlic<br /><div class="CaptionComments">
        """
        let c = SocialImport.captionFromInstagramHTML(html)
        XCTAssertEqual(c?.author, "fitfoodie")
        let r = RecipeTextParser.parse(c!.text)
        XCTAssertEqual(r.name, "Garlic Butter Steak Bites".lowercased() == r.name.lowercased() ? r.name : "Garlic butter steak bites")
        XCTAssertEqual(r.ingredients.compactMap(\.foodId), ["steak", "butter", "garlic"])
        XCTAssertEqual(r.steps.count, 2)
    }

    func testInstagramMetaDescription() {
        let html = #"<meta property="og:description" content="1,234 likes, 56 comments - fitfoodie on May 1, 2026: &quot;Protein brownies&#10;100g oats&#10;30g protein powder&quot;. ">"#
        let c = SocialImport.captionFromInstagramHTML(html)
        XCTAssertEqual(c?.author, "fitfoodie")
        XCTAssertEqual(c?.text, "Protein brownies\n100g oats\n30g protein powder")
    }
}

final class OpenFoodFactsTests: XCTestCase {
    func testParsesAProduct() {
        let json = #"{"code":"5000128104517","product":{"brands":"Sainsbury's","product_name":"Semi Skimmed Milk","quantity":"2.272 l","nutriments":{"energy-kcal_100g":47,"proteins_100g":3.6,"carbohydrates_100g":4.8,"fat_100g":1.7}},"status":1}"#
        let p = OpenFoodFacts.parse(Data(json.utf8), barcode: "5000128104517")!
        XCTAssertEqual(p.name, "Semi Skimmed Milk")
        XCTAssertEqual(p.brand, "Sainsbury's")
        XCTAssertEqual(p.food?.id, "milk")
        XCTAssertEqual(p.unit, .ml)
        XCTAssertEqual(p.size ?? 0, 2272, accuracy: 0.5)
        XCTAssertEqual(p.per100?.kcal, 47)
    }

    func testGramsAndMissingNutrition() {
        let json = #"{"product":{"product_name":"Basmati Rice","quantity":"1kg"}}"#
        let p = OpenFoodFacts.parse(Data(json.utf8), barcode: "1")!
        XCTAssertEqual(p.size, 1000)
        XCTAssertEqual(p.unit, .g)
        XCTAssertNil(p.per100)
        XCTAssertEqual(p.food?.id, "rice")
        XCTAssertNil(OpenFoodFacts.parse(Data(#"{"status":0}"#.utf8), barcode: "1"))
    }
}
