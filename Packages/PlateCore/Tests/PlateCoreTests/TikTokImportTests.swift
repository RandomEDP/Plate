import XCTest
@testable import PlateCore

/// TikTok share links failed with "it may be private" on public posts (Ethan, 14 November 2026): oEmbed can't read
/// vm.tiktok.com links, so Plate now follows them to the post and reads the post page if oEmbed has nothing.
final class TikTokImportTests: XCTestCase {
    func testShortLinksAreRecognised() {
        XCTAssertTrue(SocialImport.isTikTokShortLink(URL(string: "https://vm.tiktok.com/ZN85mJkYq/")!))
        XCTAssertTrue(SocialImport.isTikTokShortLink(URL(string: "https://vt.tiktok.com/ZSabc/")!))
        XCTAssertTrue(SocialImport.isTikTokShortLink(URL(string: "https://www.tiktok.com/t/ZT8abc/")!))
        XCTAssertFalse(SocialImport.isTikTokShortLink(URL(string: "https://www.tiktok.com/@chef/video/7301234567890")!))
        XCTAssertNil(SocialImport.tiktokPostURL(URL(string: "https://vm.tiktok.com/ZN85mJkYq/")!),
                     "A share link names no post, so it has to be followed first")
    }

    func testPostAddressFromWhereAShareLinkLands() {
        let landed = URL(string: "https://www.tiktok.com/@chefsam/video/7436512345678901234?_r=1&_t=ZN-8abc&is_from_webapp=1&sender_device=pc")!
        XCTAssertEqual(SocialImport.tiktokPostURL(landed)?.absoluteString, "https://www.tiktok.com/@chefsam/video/7436512345678901234")
        let mobile = URL(string: "https://m.tiktok.com/v/7436512345678901234.html?u_code=abc")!
        XCTAssertEqual(SocialImport.tiktokVideoID(mobile), "7436512345678901234")
        let photo = URL(string: "https://www.tiktok.com/@chefsam/photo/7436512345678901234")!
        XCTAssertEqual(SocialImport.tiktokPostURL(photo)?.absoluteString, "https://www.tiktok.com/@chefsam/photo/7436512345678901234")
        XCTAssertNil(SocialImport.tiktokPostURL(URL(string: "https://www.tiktok.com/login?redirect_url=x")!))
        XCTAssertNil(SocialImport.tiktokPostURL(URL(string: "https://www.instagram.com/p/7436512345678901234/")!))
    }

    func testOEmbedAnswers() {
        XCTAssertEqual(SocialImport.readTikTokOEmbed(Data(#"{"title":"","author_name":"Sam"}"#.utf8)), .noCaption(author: "Sam"))
        XCTAssertEqual(SocialImport.readTikTokOEmbed(Data(#"{"code":400,"message":"Something went wrong"}"#.utf8)), .unreadable)
        XCTAssertEqual(SocialImport.readTikTokOEmbed(Data("<html>blocked</html>".utf8)), .unreadable)
        XCTAssertEqual(SocialImport.readTikTokOEmbed(Data(#"{"title":"Chicken wraps","author_name":"Sam"}"#.utf8)),
                       .caption(.init(text: "Chicken wraps", author: "Sam")))
    }

    func testCaptionFromThePostPage() {
        let html = """
        <html><head><meta property="og:description" content="TikTok - trends start here."></head><body>
        <script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">{"__DEFAULT_SCOPE__":{"webapp.app-context":{"language":"en"},"webapp.video-detail":{"itemInfo":{"itemStruct":{"id":"7436512345678901234","desc":"High protein chicken wraps 🌯\\nIngredients:\\n200g chicken breast\\n2 wraps\\n#mealprep","author":{"uniqueId":"chefsam","nickname":"Chef Sam"}}},"statusCode":0,"statusMsg":""}}}</script>
        </body></html>
        """
        guard case .caption(let c) = SocialImport.readTikTokPage(html) else { return XCTFail("Expected a caption") }
        XCTAssertEqual(c.author, "Chef Sam")
        XCTAssertTrue(c.text.hasPrefix("High protein chicken wraps"))
        XCTAssertTrue(RecipeTextParser.parse(c.text).ingredients.compactMap(\.foodId).contains("chicken-breast"))
    }

    func testPrivateOrRemovedPostPage() {
        let html = """
        <script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">{"__DEFAULT_SCOPE__":{"webapp.video-detail":{"statusCode":10216,"statusMsg":"author_secret"}}}</script>
        """
        XCTAssertEqual(SocialImport.readTikTokPage(html), .unavailable)
    }

    func testPostWithNoCaption() {
        let html = """
        <script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">{"__DEFAULT_SCOPE__":{"webapp.video-detail":{"itemInfo":{"itemStruct":{"id":"1","desc":"  ","author":{"uniqueId":"chefsam"}}},"statusCode":0}}}</script>
        """
        XCTAssertEqual(SocialImport.readTikTokPage(html), .noCaption(author: "chefsam"))
    }

    func testOlderPageLayout() {
        let html = """
        <script id="SIGI_STATE" type="application/json">{"ItemModule":{"7436512345678901234":{"id":"7436512345678901234","desc":"Overnight oats: 50g oats, 150ml milk","author":"oatqueen"}}}</script>
        """
        XCTAssertEqual(SocialImport.readTikTokPage(html), .caption(.init(text: "Overnight oats: 50g oats, 150ml milk", author: "oatqueen")))
    }

    func testDescriptionTagFallback() {
        let html = """
        <meta name="description" content="1.2K Likes, 30 Comments. TikTok video from Chef Sam (@chefsam): &quot;Garlic butter pasta. 200g spaghetti, 2 garlic cloves&quot;. original sound - chefsam.">
        """
        XCTAssertEqual(SocialImport.readTikTokPage(html), .caption(.init(text: "Garlic butter pasta. 200g spaghetti, 2 garlic cloves", author: "Chef Sam")))
        // TikTok's own blurb on a page it won't show is not a caption.
        XCTAssertEqual(SocialImport.readTikTokPage(#"<meta property="og:description" content="TikTok - trends start here. On a device or on the web">"#), .unreadable)
    }
}
