import XCTest
@testable import PlateCore

final class RecipeShareTests: XCTestCase {
    func recipe() -> Recipe {
        var r = Recipe(name: "Crème fraîche chicken & leeks 🍗", summary: "Quick midweek dinner", mealTypes: [.dinner, .lunch], servings: 4,
                       ingredients: [
                           RecipeIngredient(name: "chicken breast", foodId: "chicken-breast", quantity: Quantity(600, .g), note: "diced"),
                           RecipeIngredient(name: "garlic", foodId: FoodMatcher.match("garlic")?.id, quantity: Quantity(2, .clove)),
                           RecipeIngredient(name: "crème fraîche", foodId: nil, quantity: Quantity(1.5, .tbsp)),
                           RecipeIngredient(name: "chilli flakes", foodId: nil, quantity: nil, note: "to taste", optional: true),
                       ],
                       steps: ["Fry the chicken.", "Add the rest & simmer for 10 minutes?"], minutes: 25, tags: ["highprotein"],
                       source: RecipeSource(kind: .instagram, url: "https://www.instagram.com/reel/ABC123/", author: "cook"),
                       statedPerServing: Macros(kcal: 480, protein: 42, carbs: 12, fat: 28, fibre: 3), mealPrepFriendly: true)
        r.isFavourite = true
        r.rating = 5
        r.photo = RecipePhoto(file: "mine.jpg", origin: .own)
        return r
    }

    func testTheRecipeComesOutOfTheLinkAsItWentIn() throws {
        let sent = recipe()
        let link = try XCTUnwrap(RecipeShare.link(for: sent))
        let got = try XCTUnwrap(RecipeShare.recipe(from: link))
        XCTAssertEqual(got.name, sent.name)
        XCTAssertEqual(got.summary, sent.summary)
        XCTAssertEqual(got.mealTypes, sent.mealTypes)
        XCTAssertEqual(got.servings, 4)
        XCTAssertEqual(got.minutes, 25)
        XCTAssertEqual(got.steps, sent.steps)
        XCTAssertEqual(got.tags, sent.tags)
        XCTAssertEqual(got.source, sent.source)
        XCTAssertEqual(got.statedPerServing, sent.statedPerServing)
        XCTAssertTrue(got.mealPrepFriendly)
        XCTAssertEqual(got.ingredients.map(\.name), sent.ingredients.map(\.name))
        XCTAssertEqual(got.ingredients.map(\.foodId), sent.ingredients.map(\.foodId))
        XCTAssertEqual(got.ingredients.map(\.quantity), sent.ingredients.map(\.quantity))
        XCTAssertEqual(got.ingredients.map(\.note), sent.ingredients.map(\.note))
        XCTAssertEqual(got.ingredients.map(\.optional), sent.ingredients.map(\.optional))
    }

    func testItArrivesAsANewRecipeWithoutTheSendersRatingPhotoOrFavourite() throws {
        let sent = recipe()
        let got = try XCTUnwrap(RecipeShare.link(for: sent).flatMap(RecipeShare.recipe(from:)))
        XCTAssertNotEqual(got.id, sent.id)
        XCTAssertNil(got.rating)
        XCTAssertNil(got.photo)
        XCTAssertFalse(got.isFavourite)
    }

    func testTheLinkIsAPlainWebAddressWithTheRecipeAfterTheHash() throws {
        let link = try XCTUnwrap(RecipeShare.link(for: recipe())).absoluteString
        XCTAssertTrue(link.hasPrefix("https://randomedp.github.io/Plate/r/#"))
        let code = String(link.dropFirst("https://randomedp.github.io/Plate/r/#".count))
        XCTAssertFalse(code.isEmpty)
        // Only letters, digits, "-" and "_": nothing a messaging app would cut the link at.
        XCTAssertTrue(code.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }, code)
    }

    func testTheMessageIsTheNameThenTheLinkAndIsFoundAgainInAPastedMessage() throws {
        let sent = recipe()
        let message = try XCTUnwrap(RecipeShare.message(for: sent))
        XCTAssertTrue(message.hasPrefix(sent.name + "\nhttps://"))
        XCTAssertEqual(RecipeShare.recipe(in: "Try this one!\n" + message + "\nso good")?.name, sent.name)
    }

    func testTheAppsOwnLinkCarriesTheSameRecipe() throws {
        let sent = recipe()
        let code = try XCTUnwrap(RecipeShare.code(for: sent))
        // The web page hands the recipe over either way.
        XCTAssertEqual(RecipeShare.recipe(from: try XCTUnwrap(URL(string: "plate://recipe#" + code)))?.name, sent.name)
        XCTAssertEqual(RecipeShare.recipe(from: try XCTUnwrap(URL(string: "plate://recipe?d=" + code)))?.name, sent.name)
    }

    func testTheWebPageShowsEachIngredientAsYouWouldReadIt() {
        let lines = RecipeShare.payload(recipe()).i.map(\.l)
        XCTAssertEqual(lines[0], Format.quantity(Quantity(600, .g)) + " chicken breast, diced")
        XCTAssertEqual(lines[3], "chilli flakes, to taste")
    }

    func testOtherLinksAndRubbishAreNotRecipes() throws {
        XCTAssertNil(RecipeShare.recipe(from: try XCTUnwrap(URL(string: "https://www.instagram.com/reel/ABC123/"))))
        XCTAssertNil(RecipeShare.recipe(from: try XCTUnwrap(URL(string: "https://randomedp.github.io/Plate/r/"))))
        XCTAssertNil(RecipeShare.recipe(from: try XCTUnwrap(URL(string: "https://randomedp.github.io/Plate/r/#not-a-recipe"))))
        XCTAssertNil(RecipeShare.recipe(from: try XCTUnwrap(URL(string: "plate://wall"))))
        XCTAssertNil(RecipeShare.recipe(fromCode: ""))
        XCTAssertNil(RecipeShare.recipe(fromCode: "e30"), "an empty object has no name")
        XCTAssertNil(RecipeShare.recipe(in: "no link in here"))
    }

    func testALinkFromANewerVersionIsRefusedRatherThanHalfRead() throws {
        var p = RecipeShare.payload(recipe())
        p.v = 2
        let code = try JSONEncoder().encode(p).base64EncodedString()
        XCTAssertNil(RecipeShare.recipe(fromCode: code))
    }

    func testAFoodThisPhoneDoesNotKnowIsMatchedAgainByName() throws {
        var p = RecipeShare.payload(recipe())
        p.i[0].f = "a-food-from-the-future"
        let code = try JSONEncoder().encode(p).base64EncodedString()
        let got = try XCTUnwrap(RecipeShare.recipe(fromCode: code))
        XCTAssertEqual(got.ingredients[0].foodId, FoodMatcher.match("chicken breast")?.id)
    }

    func testABuiltInRecipeArrivesAsOneOfYourOwn() throws {
        let got = try XCTUnwrap(RecipeShare.link(for: BuiltInRecipes.all[0]).flatMap(RecipeShare.recipe(from:)))
        XCTAssertEqual(got.source.kind, .manual)
        XCTAssertEqual(got.name, BuiltInRecipes.all[0].name)
        XCTAssertNotEqual(got.id, BuiltInRecipes.all[0].id)
    }

    func testARecipeYouAlreadyHaveIsRecognised() throws {
        var h = Household()
        let mine = recipe()
        h.recipes = [mine]
        let arriving = try XCTUnwrap(RecipeShare.link(for: mine).flatMap(RecipeShare.recipe(from:)))
        XCTAssertEqual(h.copy(of: arriving)?.id, mine.id)

        // No link to go on: the same name and ingredients will do.
        var typed = mine
        typed.source = RecipeSource(kind: .manual)
        h.recipes = [typed]
        var incoming = arriving
        incoming.source = RecipeSource(kind: .manual)
        XCTAssertEqual(h.copy(of: incoming)?.id, typed.id)

        incoming.name = "Something else"
        XCTAssertNil(h.copy(of: incoming))
    }
}
