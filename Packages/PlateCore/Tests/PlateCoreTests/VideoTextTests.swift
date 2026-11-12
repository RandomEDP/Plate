import XCTest
@testable import PlateCore

final class VideoTextTests: XCTestCase {
    func testScreenTextIsKeptOnceInOrder() {
        let frames = [
            ["@chefjo", "Garlic butter pasta", "TikTok"],
            ["Garlic butter pasta", "200g spaghetti"],
            ["200g spaghetti.", "3 cloves garlic"],
            ["3 cloves garlic", "50g butter", "Follow"],
            ["50g butter"],
        ]
        XCTAssertEqual(VideoText.screenLines(frames), ["Garlic butter pasta", "200g spaghetti", "3 cloves garlic", "50g butter"])
    }

    func testTextTypedOutWordByWordKeepsTheWholeLine() {
        let frames = [["2 tbsp"], ["2 tbsp olive"], ["2 tbsp olive oil"], ["1 lemon"]]
        XCTAssertEqual(VideoText.screenLines(frames), ["2 tbsp olive oil", "1 lemon"])
    }

    func testAVideoWithTheRecipeOnScreenReadsAsARecipe() {
        let text = VideoText.combine(screen: [
            ["Garlic butter pasta"], ["200g spaghetti"], ["3 cloves garlic"], ["50g butter"], ["Parmesan to serve"],
        ], speech: "Get your pasta on, then melt the butter with the garlic and toss it all together.")
        let parsed = RecipeTextParser.parse(text)
        XCTAssertGreaterThanOrEqual(parsed.ingredients.count, 3)
        XCTAssertTrue(text.contains("What they say in the video:"))
    }

    func testTheAIIsCheckedAgainstWhatWasSaid() {
        let text = VideoText.combine(screen: [], speech: "So you want two hundred grams of feta, a roasted red pepper and a spoon of Greek yoghurt, blitz it.")
        XCTAssertTrue(AIGuard.faithful(ingredients: ["200 g feta", "1 roasted red pepper", "1 tbsp Greek yoghurt"], to: text))
        XCTAssertFalse(AIGuard.faithful(ingredients: ["1 tin chickpeas", "1 courgette", "1 lemon"], to: text))
    }

    func testNothingFoundGivesNoText() {
        XCTAssertEqual(VideoText.combine(screen: [["TikTok"], ["@someone"]], speech: "  "), "")
    }
}
