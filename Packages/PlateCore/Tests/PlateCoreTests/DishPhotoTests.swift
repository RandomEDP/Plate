import XCTest
@testable import PlateCore

final class DishPhotoTests: XCTestCase {
    func frame(_ time: Double, text: Double = 0, bright: Double = 0.5, colour: Double = 0.4, sharp: Double = 0.5) -> DishFrame.Candidate {
        DishFrame.Candidate(time: time, textArea: text, brightness: bright, colour: colour, sharpness: sharp)
    }

    // MARK: Choosing the still

    func testTheFinishedDishAtTheEndWinsOverAnEquallyGoodFrameEarlier() {
        let picked = DishFrame.pick([frame(5), frame(20), frame(55)], duration: 60)
        XCTAssertEqual(picked?.time, 55)
    }

    func testAnEndCardCoveredInWritingLosesToTheDishJustBeforeIt() {
        // "Follow for more recipes" over the last two seconds.
        let picked = DishFrame.pick([frame(50), frame(57), frame(59, text: 0.35)], duration: 60)
        XCTAssertEqual(picked?.time, 57)
    }

    func testAFadeToBlackAtTheEndIsSkipped() {
        let picked = DishFrame.pick([frame(40), frame(56), frame(59.5, bright: 0.03, colour: 0.01, sharp: 0.01)], duration: 60)
        XCTAssertEqual(picked?.time, 56)
    }

    func testAWhiteTitleCardIsSkipped() {
        let picked = DishFrame.pick([frame(54), frame(59, bright: 0.97, colour: 0.02, sharp: 0.1)], duration: 60)
        XCTAssertEqual(picked?.time, 54)
    }

    func testAColourfulCrispFrameBeatsADullBlurredOneNearTheEnd() {
        let picked = DishFrame.pick([frame(52, colour: 0.5, sharp: 0.7), frame(58, colour: 0.05, sharp: 0.05)], duration: 60)
        XCTAssertEqual(picked?.time, 52)
    }

    func testAnEarlyFrameIsStillBetterThanNothingGoodLater() {
        // Everything from halfway on is a black screen with credits.
        let late = (31...59).map { frame(Double($0), text: 0.4, bright: 0.05, colour: 0, sharp: 0.1) }
        let picked = DishFrame.pick([frame(12, colour: 0.5, sharp: 0.6)] + late, duration: 60)
        XCTAssertEqual(picked?.time, 12)
    }

    func testNoFramesGivesNoPicture() {
        XCTAssertNil(DishFrame.pick([], duration: 60))
    }

    func testAVideoOfUnknownLengthStillGetsAPicture() {
        XCTAssertEqual(DishFrame.pick([frame(1), frame(2)], duration: 0)?.time, 2)
    }

    // MARK: Measuring a frame

    func pixels(_ width: Int, _ height: Int, _ colour: (Int, Int) -> (UInt8, UInt8, UInt8)) -> [UInt8] {
        var out: [UInt8] = []
        for y in 0..<height { for x in 0..<width { let c = colour(x, y); out += [c.0, c.1, c.2, 255] } }
        return out
    }

    func testABlackFrameIsDarkGreyAndFlat() {
        let s = FrameStats.measure(rgba: pixels(8, 8) { _, _ in (0, 0, 0) }, width: 8, height: 8)
        XCTAssertEqual(s.brightness, 0, accuracy: 0.001)
        XCTAssertEqual(s.colour, 0, accuracy: 0.001)
        XCTAssertEqual(s.sharpness, 0, accuracy: 0.001)
    }

    func testAWhiteFrameIsBrightButHasNoColour() {
        let s = FrameStats.measure(rgba: pixels(8, 8) { _, _ in (255, 255, 255) }, width: 8, height: 8)
        XCTAssertEqual(s.brightness, 1, accuracy: 0.001)
        XCTAssertEqual(s.colour, 0, accuracy: 0.001)
    }

    func testAPlainRedFrameIsColourfulButFlat() {
        let s = FrameStats.measure(rgba: pixels(8, 8) { _, _ in (255, 0, 0) }, width: 8, height: 8)
        XCTAssertEqual(s.colour, 1, accuracy: 0.001)
        XCTAssertEqual(s.sharpness, 0, accuracy: 0.001)
    }

    func testAChequerboardHasMoreDetailThanAGentleFade() {
        let board = FrameStats.measure(rgba: pixels(8, 8) { x, y in (x + y) % 2 == 0 ? (255, 255, 255) : (0, 0, 0) }, width: 8, height: 8)
        let fade = FrameStats.measure(rgba: pixels(8, 8) { x, _ in (UInt8(100 + x), UInt8(100 + x), UInt8(100 + x)) }, width: 8, height: 8)
        XCTAssertGreaterThan(board.sharpness, 0.9)
        XCTAssertLessThan(fade.sharpness, 0.1)
    }

    func testTooFewBytesMeasuresAsNothingRatherThanCrashing() {
        XCTAssertEqual(FrameStats.measure(rgba: [1, 2, 3], width: 8, height: 8), FrameStats(brightness: 0, colour: 0, sharpness: 0))
    }

    // MARK: Which picture stays

    func testYourOwnPhotoIsNeverSwappedForOneFromTheVideo() {
        let own = RecipePhoto(file: "a.jpg", origin: .own)
        XCTAssertFalse(RecipePhoto.shouldReplace(own, with: .video))
        XCTAssertFalse(RecipePhoto.shouldReplace(own, with: .post))
        XCTAssertTrue(RecipePhoto.shouldReplace(own, with: .own))
    }

    func testAStillFromTheVideoReplacesThePostsCoverButNotTheOtherWayRound() {
        XCTAssertTrue(RecipePhoto.shouldReplace(RecipePhoto(file: "a.jpg", origin: .post), with: .video))
        XCTAssertFalse(RecipePhoto.shouldReplace(RecipePhoto(file: "a.jpg", origin: .video), with: .post))
        XCTAssertTrue(RecipePhoto.shouldReplace(nil, with: .post))
    }

    // MARK: Keeping them with the recipe

    func recipe(_ name: String = "Lemon chicken") -> Recipe {
        Recipe(name: name, mealTypes: [.dinner], servings: 2,
               ingredients: [RecipeIngredient(name: "chicken breast", foodId: "chicken-breast", quantity: Quantity(400, .g)),
                             RecipeIngredient(name: "lemon", foodId: nil, quantity: Quantity(1, .piece))],
               steps: ["Cook it."])
    }

    func testRatingARecipeOfYourOwn() {
        var h = Household()
        let r = recipe()
        h.recipes = [r]
        XCTAssertTrue(h.rate(r.id, stars: 4))
        XCTAssertEqual(h.recipes[0].rating, 4)
        XCTAssertTrue(h.rate(r.id, stars: nil))
        XCTAssertNil(h.recipes[0].rating)
    }

    func testARatingOutsideOneToFiveClearsIt() {
        var h = Household()
        let r = recipe()
        h.recipes = [r]
        h.rate(r.id, stars: 5)
        h.rate(r.id, stars: 9)
        XCTAssertNil(h.recipes[0].rating)
    }

    func testRatingAndPhotographingABuiltInRecipe() {
        var h = Household()
        let builtIn = BuiltInRecipes.all[0], other = BuiltInRecipes.all[1]
        XCTAssertTrue(h.rate(builtIn.id, stars: 5))
        XCTAssertTrue(h.setPhoto(RecipePhoto(file: "mine.jpg", origin: .own), for: builtIn.id))
        XCTAssertTrue(h.recipes.isEmpty, "a built-in recipe isn't copied just to rate it")
        XCTAssertEqual(h.dressed(builtIn).rating, 5)
        XCTAssertEqual(h.dressed(builtIn).photo?.file, "mine.jpg")
        XCTAssertEqual(h.dressed(builtIn).photo?.origin, .own)
        XCTAssertEqual(h.photo(of: builtIn.id)?.file, "mine.jpg")
        XCTAssertNil(h.dressed(other).rating)
        XCTAssertNil(h.dressed(other).photo)
        h.rate(builtIn.id, stars: nil)
        h.setPhoto(nil, for: builtIn.id)
        XCTAssertNil(h.dressed(builtIn).rating)
        XCTAssertNil(h.dressed(builtIn).photo)
    }

    func testRatingARecipeThatHasGoneDoesNothing() {
        var h = Household()
        XCTAssertFalse(h.rate(UUID(), stars: 3))
        XCTAssertFalse(h.setPhoto(RecipePhoto(file: "x.jpg", origin: .video), for: UUID()))
    }

    func testPicturesNoRecipeUsesAreFoundForTidyingAway() {
        var h = Household()
        var r = recipe()
        r.photo = RecipePhoto(file: "kept.jpg", origin: .video)
        h.recipes = [r]
        h.setPhoto(RecipePhoto(file: "builtin.jpg", origin: .own), for: BuiltInRecipes.all[0].id)
        XCTAssertEqual(RecipePhoto.orphans(files: ["kept.jpg", "old.jpg", "builtin.jpg"], in: h), ["old.jpg"])
        h.deleteRecipes([r.id])
        XCTAssertEqual(RecipePhoto.orphans(files: ["kept.jpg", "builtin.jpg"], in: h), ["kept.jpg"])
    }

    func testReimportingKeepsYourRatingAndPhoto() {
        var old = recipe()
        old.rating = 4
        old.photo = RecipePhoto(file: "mine.jpg", origin: .own)
        let again = old.refreshed(from: recipe("Lemon chicken, read again"))
        XCTAssertEqual(again.rating, 4)
        XCTAssertEqual(again.photo?.file, "mine.jpg")
        XCTAssertEqual(again.name, "Lemon chicken, read again")
    }

    func testRatingAndPhotoSurviveSavingAndOldFilesStillOpen() throws {
        var r = recipe()
        r.rating = 3
        r.photo = RecipePhoto(file: "a.jpg", origin: .video)
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(Recipe.self, from: data)
        XCTAssertEqual(back.rating, 3)
        XCTAssertEqual(back.photo, r.photo)

        // A recipe saved before ratings and photos existed.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["rating"] = nil
        object["photo"] = nil
        let old = try JSONDecoder().decode(Recipe.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.rating)
        XCTAssertNil(old.photo)
    }

    func testAPictureOfAKindThisVersionDoesNotKnowStillOpens() throws {
        let json = #"{"file":"a.jpg","origin":"hologram","updatedAt":0}"#
        let photo = try JSONDecoder().decode(RecipePhoto.self, from: Data(json.utf8))
        XCTAssertEqual(photo.origin, .post)
    }

    // MARK: The planner

    func testThePlannerLikesWellRatedDishesAndAvoidsPoorOnes() {
        var loved = recipe(), hated = recipe(), unrated = recipe()
        loved.rating = 5
        hated.rating = 1
        unrated.rating = nil
        func score(_ r: Recipe) -> Double {
            Planner.score(r, servings: 2, stock: [:], expiring: [], picked: [:], batch: false, kcalTarget: nil)
        }
        XCTAssertGreaterThan(score(loved), score(unrated))
        XCTAssertLessThan(score(hated), score(unrated))
    }

    // MARK: Cover pictures from posts

    func testTikTokCoverPicture() {
        let json = #"{"title":"Creamy pasta\n200g pasta\n100ml cream","author_name":"cook","thumbnail_url":"https://p16.tiktokcdn.com/obj/cover.jpeg?x=1&y=2"}"#
        let caption = SocialImport.captionFromTikTokOEmbed(Data(json.utf8))
        XCTAssertEqual(caption?.thumbnail?.absoluteString, "https://p16.tiktokcdn.com/obj/cover.jpeg?x=1&y=2")
    }

    func testTikTokWithoutACoverStillGivesTheCaption() {
        let json = #"{"title":"Creamy pasta with cream and garlic","author_name":"cook"}"#
        let caption = SocialImport.captionFromTikTokOEmbed(Data(json.utf8))
        XCTAssertNotNil(caption)
        XCTAssertNil(caption?.thumbnail)
    }

    func testInstagramEmbedCoverPicture() {
        let html = """
        <div class="EmbeddedMedia"><img class="EmbeddedMediaImage" alt="Reel" src="https://scontent.cdninstagram.com/v/t51/cover.jpg?stp=dst-jpg&amp;oh=abc" /></div>
        <div class="Caption"><a class="CaptionUsername" href="/cook/">cook</a> Lemon chicken: 400g chicken, 1 lemon, 2 cloves garlic<div class="CaptionComments">
        """
        let caption = SocialImport.captionFromInstagramHTML(html)
        XCTAssertEqual(caption?.thumbnail?.absoluteString, "https://scontent.cdninstagram.com/v/t51/cover.jpg?stp=dst-jpg&oh=abc")
    }

    func testInstagramLinkPreviewPicture() {
        let html = """
        <meta property="og:image" content="https://scontent.cdninstagram.com/preview.jpg" />
        <meta property="og:description" content="12 likes, 1 comments - cook on May 1, 2026: &quot;Lemon chicken with garlic and herbs&quot;. " />
        """
        XCTAssertEqual(SocialImport.captionFromInstagramHTML(html)?.thumbnail?.absoluteString, "https://scontent.cdninstagram.com/preview.jpg")
    }

    func testOnlyHttpsPicturesAreFetched() {
        XCTAssertNil(SocialImport.webImage("http://example.com/a.jpg"))
        XCTAssertNil(SocialImport.webImage("file:///etc/passwd"))
        XCTAssertNil(SocialImport.webImage("data:image/png;base64,AAAA"))
        XCTAssertNotNil(SocialImport.webImage(" https://example.com/a.jpg "))
    }
}
