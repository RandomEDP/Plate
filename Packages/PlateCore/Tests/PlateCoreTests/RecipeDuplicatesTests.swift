import XCTest
@testable import PlateCore

final class RecipeDuplicatesTests: XCTestCase {
    let caption = """
    Creamy chicken orzo 🍗
    Ingredients:
    2 chicken breasts
    200g orzo
    1 onion
    3 garlic cloves
    500ml chicken stock
    100ml double cream
    Method:
    1. Brown the chicken.
    2. Add everything else and simmer for 15 minutes.
    """

    func recipe(_ text: String, link: String? = nil) -> Recipe {
        let kind: RecipeSourceKind = link == nil ? .manual : .instagram
        return RecipeTextParser.parse(text).recipe(source: RecipeSource(kind: kind, url: link))
    }

    func testSameReelSharedTwiceIsCaught() {
        let saved = recipe(caption, link: "https://www.instagram.com/reel/ABC123/?igsh=one")
        let again = recipe("No recipe in this one, it's in the video", link: "https://instagram.com/reels/ABC123")
        let m = RecipeDuplicates.match(for: again, in: [saved])
        XCTAssertEqual(m?.recipe.id, saved.id)
        XCTAssertEqual(m?.reason, .sameLink)
        XCTAssertEqual(m?.message, "You already saved this post as “\(saved.name)”.")
    }

    func testSameTikTokWithDifferentTrackingIsCaught() {
        let saved = recipe(caption, link: "https://www.tiktok.com/@cook/video/7301234567890?is_from_webapp=1")
        let again = recipe(caption, link: "https://tiktok.com/@cook/video/7301234567890")
        XCTAssertEqual(RecipeDuplicates.match(for: again, in: [saved])?.reason, .sameLink)
    }

    func testSamePastedTextIsCaught() {
        let saved = recipe(caption)
        let again = recipe(caption)
        let m = RecipeDuplicates.match(for: again, in: [saved])
        XCTAssertEqual(m?.recipe.id, saved.id)
        XCTAssertEqual(m?.reason, .sameRecipe)
    }

    func testPastedTextMatchesTheSameRecipeSavedFromAReel() {
        let saved = recipe(caption, link: "https://www.instagram.com/reel/ABC123/")
        XCTAssertEqual(RecipeDuplicates.match(for: recipe(caption), in: [saved])?.reason, .sameRecipe)
    }

    func testRenamedButSameIngredientsIsCaught() {
        let saved = recipe(caption)
        let renamed = recipe(caption.replacingOccurrences(of: "Creamy chicken orzo 🍗", with: "One pot orzo"))
        XCTAssertEqual(RecipeDuplicates.match(for: renamed, in: [saved])?.recipe.id, saved.id)
    }

    func testNameAndPunctuationDoNotMatter() {
        XCTAssertEqual(RecipeDuplicates.normalisedName("Creamy Chicken Orzo! 🍗"), "creamy chicken orzo")
        XCTAssertEqual(RecipeDuplicates.normalisedName("  Crème brûlée  "), "creme brulee")
    }

    func testSameNameButDifferentFoodIsNotADuplicate() {
        let saved = recipe(caption)
        let other = recipe("""
        Creamy chicken orzo
        Ingredients:
        1 courgette
        2 peppers
        200g feta
        1 lemon
        """)
        XCTAssertNil(RecipeDuplicates.match(for: other, in: [saved]))
    }

    func testTwoDifferentPostsAreNeverCalledTheSame() {
        let saved = recipe(caption, link: "https://www.instagram.com/reel/ABC123/")
        let other = recipe(caption, link: "https://www.instagram.com/reel/XYZ789/")
        XCTAssertNil(RecipeDuplicates.match(for: other, in: [saved]))
    }

    func testARecipeDoesNotMatchItself() {
        let saved = recipe(caption, link: "https://www.instagram.com/reel/ABC123/")
        XCTAssertNil(RecipeDuplicates.match(for: saved, in: [saved]))
    }

    func testNothingSavedMeansNoMatch() {
        XCTAssertNil(RecipeDuplicates.match(for: recipe(caption), in: []))
    }

    func testOstaLinksMatchWithOrWithoutTheTrailingSlash() {
        let saved = recipe(caption, link: "https://ostarecipes.com/s/recipes/90O8KHerNFowwPp4ZIFP/")
        let again = recipe("x", link: "ostarecipes.com/s/recipes/90O8KHerNFowwPp4ZIFP")
        XCTAssertEqual(RecipeDuplicates.match(for: again, in: [saved])?.reason, .sameLink)
    }

    func testLinkKeyIgnoresJunk() {
        XCTAssertNil(RecipeDuplicates.linkKey(""))
        XCTAssertNil(RecipeDuplicates.linkKey("   "))
        XCTAssertEqual(RecipeDuplicates.linkKey("https://www.instagram.com/p/ABC123/?utm_source=ig"), "instagram:ABC123")
    }
}

final class InboxSummaryTests: XCTestCase {
    func testOneSaved() {
        XCTAssertEqual(InboxSummary.text(saved: ["Chicken orzo"], updated: [], repeats: []), "Saved Chicken orzo.")
    }

    func testMixed() {
        XCTAssertEqual(InboxSummary.text(saved: ["A", "B"], updated: ["C"], repeats: ["D"]),
                       "Saved 2 recipes. Updated C. You already had D, so it wasn't saved twice.")
    }

    func testOnlyRepeats() {
        XCTAssertEqual(InboxSummary.text(saved: [], updated: [], repeats: ["A", "B"]), "2 you already had weren't saved twice.")
    }

    func testNothing() {
        XCTAssertNil(InboxSummary.text(saved: [], updated: [], repeats: []))
    }
}
