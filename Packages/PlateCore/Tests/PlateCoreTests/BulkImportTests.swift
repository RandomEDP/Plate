import XCTest
@testable import PlateCore

final class BulkImportTests: XCTestCase {
    func testListOfLinksGivesOneItemEach() {
        let text = """
        https://www.instagram.com/reel/ABC123/?igsh=xyz
        https://www.tiktok.com/@cook/video/7301234567890

        instagram.com/p/DEF456/
        """
        let items = BulkImport.items(in: text)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map { $0.link.map(BulkImport.key(for:)) }, ["instagram:ABC123", "tiktok:7301234567890", "instagram:DEF456"])
        if case .link(_, let p) = items[1] { XCTAssertEqual(p, .tiktok) } else { XCTFail("Expected a link") }
    }

    func testRepeatedPostsAreImportedOnce() {
        let text = """
        Chicken orzo https://www.instagram.com/reel/ABC123/?igsh=one
        Same again https://instagram.com/reel/ABC123
        https://www.instagram.com/reels/ABC123/
        """
        XCTAssertEqual(BulkImport.items(in: text).count, 1)
    }

    func testTitlesNextToLinksAreIgnored() {
        let text = """
        Everything !
        Creamy chicken orzo - https://www.instagram.com/reel/ABC123/
        Protein pancakes: https://www.tiktok.com/@chef/video/111
        """
        let items = BulkImport.items(in: text)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { if case .link = $0 { return true } else { return false } })
    }

    func testSeveralCaptionsSplitByDashes() {
        let text = """
        Garlic butter chicken
        Ingredients:
        500g chicken thighs
        2 tbsp butter
        3 garlic cloves
        Method: fry it all.
        ---
        Overnight oats
        50g oats
        150ml milk
        1 tbsp honey
        https://www.tiktok.com/@oats/video/222
        """
        let items = BulkImport.items(in: text)
        XCTAssertEqual(items.count, 2)
        guard case .caption(let first, let firstLink) = items[0], case .caption(let second, let secondLink) = items[1] else {
            return XCTFail("Expected two captions, got \(items)")
        }
        XCTAssertTrue(first.hasPrefix("Garlic butter chicken"))
        XCTAssertNil(firstLink)
        XCTAssertTrue(second.contains("50g oats"))
        XCTAssertEqual(secondLink.map(BulkImport.key(for:)), "tiktok:222")
    }

    func testSeparatorLines() {
        XCTAssertTrue(BulkImport.isSeparator("---"))
        XCTAssertTrue(BulkImport.isSeparator("  *****  "))
        XCTAssertTrue(BulkImport.isSeparator("==="))
        XCTAssertFalse(BulkImport.isSeparator("--"))
        XCTAssertFalse(BulkImport.isSeparator("- 2 eggs"))
        XCTAssertFalse(BulkImport.isSeparator("-=-"))
    }

    func testLinksAlreadySavedAreSkipped() {
        let items = BulkImport.items(in: """
        https://www.instagram.com/reel/ABC123/?igsh=new
        https://www.instagram.com/reel/NEW999/
        """)
        let left = BulkImport.notYetImported(items, existingLinks: ["https://instagram.com/reel/ABC123/"])
        XCTAssertEqual(left.map { $0.link.map(BulkImport.key(for:)) }, ["instagram:NEW999"])
    }

    func testOtherSitesAreKeptAsLinks() {
        let items = BulkImport.items(in: "https://www.bbcgoodfood.com/recipes/chilli-con-carne/")
        XCTAssertEqual(items.count, 1)
        if case .link(_, let p) = items[0] { XCTAssertEqual(p, .web) } else { XCTFail("Expected a link") }
        XCTAssertEqual(BulkImport.key(for: items[0].link!), "bbcgoodfood.com/recipes/chilli-con-carne")
    }

    func testNothingUsefulGivesNothing() {
        XCTAssertTrue(BulkImport.items(in: "Join my folder on Osta!\n\n---\n").isEmpty)
    }
}
