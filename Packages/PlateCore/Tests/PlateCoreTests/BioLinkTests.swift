import XCTest
@testable import PlateCore

/// "Recipe in bio" captions: Plate follows the creator's bio link to find the recipe (Ethan, 28 November 2026).
final class BioLinkTests: XCTestCase {
    func testSpotsBioMentions() {
        for yes in ["Recipe in bio!", "Full recipe linked in my bio 🔗", "Sign up to the cookbook in bio", "Written recipe on my blog, link in bio",
                    "Recipe on the website (link in profile)", "#linkinbio #vegan", "Grab the ebook via my bio", "Recipe 🔗 in bio"] {
            XCTAssertTrue(BioLink.mentionsBio(yes), yes)
        }
        for no in ["Comment RECIPE and I'll DM it to you", "Biology teacher's favourite pasta", "Smoky tofu tacos, ready in 20 mins",
                   "Follow for more"] {
            XCTAssertFalse(BioLink.mentionsBio(no), no)
        }
    }

    func testProfileURLs() {
        XCTAssertEqual(BioLink.profileURL(platform: .instagram, post: nil, author: "surelynotvegan")?.absoluteString,
                       "https://www.instagram.com/surelynotvegan/")
        XCTAssertNil(BioLink.profileURL(platform: .instagram, post: nil, author: "Kel Meredith"), "a display name isn't a username")
        let post = URL(string: "https://www.tiktok.com/@kelcooks/video/7312345678901234567")!
        XCTAssertEqual(BioLink.profileURL(platform: .tiktok, post: post, author: "Kel")?.absoluteString, "https://www.tiktok.com/@kelcooks")
    }

    func testInstagramBioLinkFromDrawnProfile() {
        let html = """
        <div><a href="https://l.instagram.com/?u=https%3A%2F%2Flinktr.ee%2Fkelcooks&amp;e=AT0abc" rel="me nofollow noopener noreferrer" target="_blank">linktr.ee/kelcooks</a>
        <a href="https://l.instagram.com/?u=https%3A%2F%2Fwww.tiktok.com%2F%40kelcooks&amp;e=AT0def">tiktok</a></div>
        """
        XCTAssertEqual(BioLink.instagramBioLinks(html).map(\.absoluteString), ["https://linktr.ee/kelcooks"], "social links aren't followed")
    }

    func testTikTokBioLink() {
        let html = #"{"user":{"uniqueId":"kelcooks","signature":"Easy vegan food 🌱\nRecipes: www.kelcooks.com/recipes\nkel@outlook.com","bioLink":{"link":"https://beacons.ai/kelcooks","risk":0}}}"#
        XCTAssertEqual(BioLink.tiktokBioLinks(html).map(\.absoluteString),
                       ["https://beacons.ai/kelcooks", "https://www.kelcooks.com/recipes"])
        XCTAssertTrue(BioLink.urls(inText: "email me: kel@outlook.com").isEmpty, "an email address isn't a link")
        XCTAssertEqual(BioLink.urls(inText: "all my links: linktr.ee/kel").map(\.absoluteString), ["https://linktr.ee/kel"])
    }

    let linktree = """
    <html><body><h1>Kel Cooks</h1>
    <a href="https://www.kelcooks.com/smoky-mango-tofu-tacos/" data-testid="LinkButton"><p>Smoky Mango Tofu Tacos 🌮</p></a>
    <a href="https://www.kelcooks.com/creamy-pesto-gnocchi/"><p>Creamy pesto gnocchi</p></a>
    <a href="https://stan.store/kelcooks/p/cookbook"><p>My vegan cookbook</p></a>
    <a href="https://www.kelcooks.com/"><p>All my recipes</p></a>
    <a href="https://www.instagram.com/kelcooks/">Instagram</a>
    <a href="mailto:kel@outlook.com">Email</a>
    <a href="#top">Top</a>
    </body></html>
    """

    func testPicksTheDishOnALinkPage() {
        let base = URL(string: "https://linktr.ee/kelcooks")!
        let links = BioLink.links(inHTML: linktree, base: base)
        XCTAssertEqual(links.count, 5, "mailto and in-page links are left out")
        XCTAssertEqual(links.first?.text, "Smoky Mango Tofu Tacos 🌮")
        let caption = "Got the gravy ick? 😅 Smoky mango tofu tacos, really easy. Full recipe in bio!"
        let keywords = BioLink.keywords(title: RecipeTextParser.parse(caption).name, caption: caption)
        let ranked = BioLink.rank(links, keywords: keywords)
        XCTAssertEqual(ranked.first?.absoluteString, "https://www.kelcooks.com/smoky-mango-tofu-tacos/")
        XCTAssertTrue(ranked.contains(URL(string: "https://www.kelcooks.com/")!), "the creator's recipes page is worth a look")
        XCTAssertFalse(ranked.contains { BioLink.isShop($0) || BioLink.isSocial($0) })
        XCTAssertFalse(ranked.contains(URL(string: "https://www.kelcooks.com/creamy-pesto-gnocchi/")!), "a different dish isn't followed")
        XCTAssertTrue(BioLink.isLinkPage(base))
        XCTAssertTrue(BioLink.isShop(URL(string: "https://stan.store/kelcooks/p/cookbook")!))
    }

    func testSiteSearch() {
        let keywords = BioLink.keywords(title: "Smoky mango tofu tacos", caption: "")
        let url = BioLink.searchURL(site: URL(string: "https://www.kelcooks.com/about/")!, keywords: keywords)
        XCTAssertEqual(url?.host, "www.kelcooks.com")
        XCTAssertEqual(URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "mango smoky taco tofu")
    }

    let recipePage = """
    <html><head><script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"WebPage","name":"Smoky Mango Tofu Tacos - Kel Cooks"},
    {"@type":"Recipe","name":"Smoky Mango Tofu Tacos","image":["https://www.kelcooks.com/wp-content/tacos.jpg"],"recipeYield":["4","4 tacos"],
    "totalTime":"PT25M","recipeIngredient":["1 block (280g) smoked tofu","1 tsp smoked paprika","1 tbsp maple syrup","1 mango","8 soft taco shells","Juice of 1/2 lime"],
    "recipeInstructions":[{"@type":"HowToSection","name":"Tofu","itemListElement":[{"@type":"HowToStep","text":"Crumble the tofu and toss it in the spices &amp; syrup."},{"@type":"HowToStep","text":"Air fry at 180°C for 12 minutes."}]},
    {"@type":"HowToStep","text":"Fill the tacos."}],
    "nutrition":{"@type":"NutritionInformation","calories":"410 kcal","proteinContent":"18 g","carbohydrateContent":"52 g","fatContent":"14 g"}}]}</script></head>
    <body><h1>Smoky Mango Tofu Tacos</h1></body></html>
    """

    func testReadsTheRecipeCard() throws {
        let card = try XCTUnwrap(RecipeSchema.card(inHTML: recipePage))
        XCTAssertEqual(card.name, "Smoky Mango Tofu Tacos")
        XCTAssertEqual(card.image?.absoluteString, "https://www.kelcooks.com/wp-content/tacos.jpg")
        let r = RecipeTextParser.parse(card.text)
        XCTAssertEqual(r.name, "Smoky Mango Tofu Tacos")
        XCTAssertEqual(r.servings, 4)
        XCTAssertEqual(r.minutes, 25)
        XCTAssertEqual(r.ingredients.count, 6, r.ingredients.map(\.name).joined(separator: " | "))
        XCTAssertTrue(r.ingredients.contains { $0.foodId == "tofu" })
        XCTAssertEqual(r.steps, ["Crumble the tofu and toss it in the spices & syrup.", "Air fry at 180°C for 12 minutes.", "Fill the tacos."])
        XCTAssertEqual(r.statedPerServing?.kcal, 410)
        XCTAssertEqual(r.statedPerServing?.protein, 18)
        // It's the dish the caption named.
        let keywords = BioLink.keywords(title: "Smoky mango tofu tacos", caption: "")
        XCTAssertTrue(BioLink.isMatch(BioLink.score(card.name, url: nil, keywords: keywords), keywords: keywords))
        XCTAssertFalse(BioLink.isMatch(BioLink.score("Creamy pesto gnocchi", url: nil, keywords: keywords), keywords: keywords))
    }

    func testNoCardWithoutIngredients() {
        XCTAssertNil(RecipeSchema.card(inHTML: #"<script type="application/ld+json">{"@type":"Recipe","name":"Tacos","recipeIngredient":["tofu"]}</script>"#))
        XCTAssertNil(RecipeSchema.card(inHTML: "<html><body>No card here</body></html>"))
        XCTAssertEqual(RecipeSchema.minutes("PT1H20M"), 80)
    }
}
