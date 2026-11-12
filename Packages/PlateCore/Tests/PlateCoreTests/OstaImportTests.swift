import XCTest
@testable import PlateCore

final class OstaImportTests: XCTestCase {
    func testRecognisesRecipeAndFolderLinks() {
        XCTAssertEqual(OstaImport.kind(of: URL(string: "https://ostarecipes.com/s/recipes/90O8KHerNFowwPp4ZIFP")!),
                       .recipe(id: "90O8KHerNFowwPp4ZIFP"))
        XCTAssertEqual(OstaImport.kind(of: URL(string: "https://ostarecipes.com/sharefolder?folderId=Folder123&token=abc")!),
                       .folder(id: "Folder123"))
        XCTAssertNil(OstaImport.kind(of: URL(string: "https://ostarecipes.com/")!))
        XCTAssertNil(OstaImport.kind(of: URL(string: "https://www.instagram.com/reel/ABC/")!))
    }

    func testOstaLinksInABulkPasteStayLinks() {
        let items = BulkImport.items(in: """
        Creamy pasta https://ostarecipes.com/s/recipes/AAAAAAAAAA
        https://ostarecipes.com/s/recipes/BBBBBBBBBB
        https://ostarecipes.com/s/recipes/AAAAAAAAAA
        """)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.compactMap { $0.link.flatMap(OstaImport.kind(of:)) }, [.recipe(id: "AAAAAAAAAA"), .recipe(id: "BBBBBBBBBB")])
    }

    func testFolderPageLinksBecomeRecipeLinks() {
        let found = [
            "https://ostarecipes.com/s/recipes/AAAAAAAAAA",
            "https://ostarecipes.com/",
            "/recipes/BBBBBBBBBB?from=folder",
            "https://ostarecipes.com/s/recipes/AAAAAAAAAA",
            "https://apps.apple.com/app/id6739286231",
        ]
        XCTAssertEqual(OstaImport.recipeLinks(in: found).map(\.absoluteString), [
            "https://ostarecipes.com/s/recipes/AAAAAAAAAA",
            "https://ostarecipes.com/s/recipes/BBBBBBBBBB",
        ])
    }

    /// Laid out as the page appears in Safari (12 November 2026): photo and creator, title, times, the start of the
    /// caption, servings and Share, the app banner, Save, then the ingredients with amounts apart from names, then
    /// the numbered method.
    let page = OstaImport.Page(title: "Creamy Sun Dried Tomato Pasta", text: """
    phitzee
    Creamy Sun Dried Tomato…
    Prep : 0 min
    Cook : 1 min
    This is what I cook when I want to impress someone 😍🍽️ It's a creamy sun dried tomato...
    6
    Share
    View in the Osta app
    Open app
    Save this recipe
    pasta of choice
    2 cloves
    garlic
    1/2
    red onion
    200g
    sun dried tomatoes
    100 ml
    double cream
    1
    Using a hand blender or high speed blender, blend together the garlic, onion and tomatoes.
    2
    Cook the pasta in salted water until al dente.
    3
    Stir the sauce through the pasta with a splash of pasta water.
    """, links: ["https://ostarecipes.com/", "https://www.instagram.com/reel/C1xYz/"])

    func testReadsTheRecipePage() throws {
        let x = try XCTUnwrap(OstaImport.extract(page))
        XCTAssertEqual(x.author, "phitzee")
        XCTAssertEqual(x.original?.absoluteString, "https://www.instagram.com/reel/C1xYz/")
        XCTAssertTrue(x.caption.hasPrefix("Creamy Sun Dried Tomato Pasta\nServes 6\nReady in 1 minutes"), x.caption)
        XCTAssertTrue(x.caption.contains("- 2 cloves garlic"), x.caption)
        XCTAssertTrue(x.caption.contains("- 1/2 red onion"), x.caption)
        XCTAssertTrue(x.caption.contains("- 200g sun dried tomatoes"), x.caption)
        XCTAssertTrue(x.caption.contains("- 100 ml double cream"), x.caption)
        XCTAssertTrue(x.caption.contains("3. Stir the sauce"), x.caption)
        XCTAssertFalse(x.caption.contains("impress someone"), "The cut-off caption isn't an ingredient")
        XCTAssertFalse(x.caption.lowercased().contains("open app"))

        // And Plate's own reader makes a proper recipe of it.
        let parsed = RecipeTextParser.parse(x.caption)
        XCTAssertEqual(parsed.name, "Creamy Sun Dried Tomato Pasta")
        XCTAssertEqual(parsed.servings, 6)
        XCTAssertEqual(parsed.ingredients.count, 5)
        XCTAssertEqual(parsed.steps.count, 3)
        XCTAssertEqual(parsed.ingredients.first { $0.name.lowercased().contains("garlic") }?.foodId, "garlic")
    }

    func testStepsNumberedOnTheSameLine() throws {
        let p = OstaImport.Page(title: "Overnight oats", text: """
        Save this recipe
        50g
        oats
        150 ml
        milk
        1. Put the oats and milk in a jar and stir well.
        2. Leave in the fridge overnight and eat cold.
        """)
        let x = try XCTUnwrap(OstaImport.extract(p))
        let parsed = RecipeTextParser.parse(x.caption)
        XCTAssertEqual(parsed.ingredients.count, 2)
        XCTAssertEqual(parsed.steps, ["Put the oats and milk in a jar and stir well.", "Leave in the fridge overnight and eat cold."])
    }

    func testAPageStillLoadingGivesNothing() {
        XCTAssertNil(OstaImport.extract(.init(title: "Osta Recipes", text: "View in the Osta app\nOpen app")))
        XCTAssertNil(OstaImport.extract(.init(title: "", text: "")))
    }

    /// A private or missing recipe lands on Osta's home page. Its blurbs used to be saved as "ingredients", and the
    /// AI then made up a recipe for them (Ethan, 12 November 2026).
    func testOstasHomePageIsNotARecipe() {
        let home = """
        Osta
        Save recipes from Instagram, TikTok and anywhere else
        Plan your week in minutes
        Join 100,000 home cooks
        Get the app
        2 minutes to set up
        """
        XCTAssertNil(OstaImport.extract(.init(title: "Osta Recipes", text: home)))
        XCTAssertNil(OstaImport.extract(.init(title: "Osta: Save & Share Recipes", text: "Save this recipe\n" + home)))
    }

    func testARecipePageWithoutRealIngredientsGivesNothing() {
        let page = """
        Save this recipe
        Prep 10 mins
        A lovely summer favourite
        Perfect for sharing with friends
        """
        XCTAssertNil(OstaImport.extract(.init(title: "Summer favourite", text: page)))
    }

    func testSaysWhatAPageWithNoRecipeWasShowing() {
        XCTAssertEqual(OstaImport.miss(.init(title: "", text: "")), .empty)
        XCTAssertEqual(OstaImport.miss(.init(title: "Osta Recipes", text: "Save recipes from anywhere\nGet the app\nJoin 100,000 home cooks")), .notARecipe)
        XCTAssertEqual(OstaImport.miss(.init(title: "Summer favourite", text: "Save this recipe\nPrep 10 mins\nA lovely summer favourite")), .unreadable)
    }

    func testAmountOnlyLines() {
        for s in ["2 cloves", "1/2", "200g", "100 ml", "½", "1 tbsp", "2 x"] { XCTAssertTrue(OstaImport.isAmountOnly(s), s) }
        for s in ["2 cloves garlic", "garlic", "1 red onion", "Using a hand blender"] { XCTAssertFalse(OstaImport.isAmountOnly(s), s) }
    }
}
