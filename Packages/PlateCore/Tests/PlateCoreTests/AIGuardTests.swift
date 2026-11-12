import XCTest
@testable import PlateCore

final class AIGuardTests: XCTestCase {
    /// What an Osta page with no recipe on it gave Apple's AI, and what the AI made up (Ethan, 12 November 2026).
    let junk = """
    Osta Recipes
    Save, organise and share recipes from anywhere
    Get the app
    Join 100,000 home cooks
    """
    let madeUp = ["1 tin chickpeas", "1 courgette", "2 tbsp olive oil", "1 lemon", "Handful of fresh parsley"]

    func testAMadeUpRecipeIsRefused() {
        XCTAssertFalse(AIGuard.faithful(ingredients: madeUp, to: junk))
        XCTAssertFalse(AIGuard.faithful(name: "Chickpea & Courgette Salad", to: junk))
    }

    func testATidiedRealRecipeIsAccepted() {
        let caption = """
        Creamy Tirokafteri
        200g feta
        1 roasted red pepper
        2 tbsp Greek yoghurt
        1 garlic clove
        Chilli flakes
        """
        let tidy = ["200 g feta cheese", "1 roasted red pepper", "2 tbsp Greek yogurt", "1 clove garlic", "pinch of chilli flakes", "salt"]
        XCTAssertTrue(AIGuard.faithful(ingredients: tidy, to: caption))
        XCTAssertTrue(AIGuard.faithful(name: "Creamy Tirokafteri Dip", to: caption))
    }

    func testNoIngredientsIsNotFaithful() {
        XCTAssertFalse(AIGuard.faithful(ingredients: [], to: "anything"))
    }
}
