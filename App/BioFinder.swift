import Foundation
import PlateCore

/// Follows a creator's bio link to find a recipe their caption says is "in bio" (Ethan, 28 November 2026).
/// Opens the creator's public profile, takes the bio link (a Linktree-style page or their website), and looks for a
/// link naming the dish, the site's own search, and the recipe card on the page. Nothing is sent but page requests.
@MainActor
enum BioFinder {
    enum Failure: LocalizedError {
        case noProfile
        case noBioLink(String)
        case forSale(String)
        case notFound(String)

        var errorDescription: String? {
            switch self {
            case .noProfile:
                return "The caption says the recipe is in the creator's bio, but Plate couldn't tell whose post it is. Open their profile, follow the bio link, and paste the recipe page's link or text here."
            case .noBioLink(let who):
                return "The caption says the recipe is in \(who)'s bio, but Plate couldn't see a link there (it may only show when you're signed in). Open their profile, follow the link, and paste the recipe page's link or text here."
            case .forSale(let who):
                return "\(who)'s bio link goes to a shop, so the recipe looks like it's in a cookbook or guide for sale, which Plate can't read. If you have it, paste the recipe's text here."
            case .notFound(let who):
                return "Plate followed \(who)'s bio link but couldn't find this recipe there. Open the link yourself; when you find it, share the page to Plate or paste its link or text here."
            }
        }
    }

    struct Found {
        var text: String
        var page: URL
        var image: URL?
    }

    static func find(caption: String, post: URL, author: String?, platform: SocialImport.Platform) async throws -> Found {
        let keywords = BioLink.keywords(title: RecipeTextParser.parse(caption).name, caption: caption)
        var postURL = post
        if platform == .tiktok, SocialImport.tiktokPostURL(post) == nil, let resolved = try? await CaptionFetcher.resolveTikTok(post) {
            postURL = resolved
        }
        guard let profile = BioLink.profileURL(platform: platform, post: postURL, author: author) else { throw Failure.noProfile }
        let who = "@" + profile.lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: "@"))

        // The bio link: Instagram draws it with its script; TikTok has it in the page's data.
        var bio: [URL] = []
        if platform == .instagram {
            if let html = try? await OstaReader.html(profile, seconds: 12, ready: { !BioLink.instagramBioLinks($0).isEmpty }) {
                bio = BioLink.instagramBioLinks(html)
            }
        } else if let data = try? await CaptionFetcher.get(profile, userAgent: CaptionFetcher.browserAgent) {
            bio = BioLink.tiktokBioLinks(String(decoding: data, as: UTF8.self))
        }
        guard !bio.isEmpty else { throw Failure.noBioLink(who) }

        var queue: [(url: URL, depth: Int)] = bio.map { ($0, 0) }
        var visited = Set<String>()
        var searched = Set<String>()
        var sawShop = bio.contains(where: BioLink.isShop)
        var pages = 0
        while !queue.isEmpty, pages < 12 {
            let (url, depth) = queue.removeFirst()
            if BioLink.isShop(url) || BioLink.isSocial(url) { continue }
            guard visited.insert(url.absoluteString).inserted else { continue }
            pages += 1
            guard let html = await page(url) else { continue }
            if let card = RecipeSchema.card(inHTML: html),
               BioLink.isMatch(BioLink.score(card.name, url: url, keywords: keywords), keywords: keywords) {
                return Found(text: card.text, page: url, image: card.image)
            }
            guard depth < 2 else { continue }
            let links = BioLink.links(inHTML: html, base: url)
            if depth == 0, links.contains(where: { BioLink.isShop($0.url) && ($0.text + $0.url.path).lowercased().contains("book") }) {
                sawShop = true
            }
            // The best links are looked at next; the site's own search after the creator's other links.
            queue.insert(contentsOf: BioLink.rank(links, keywords: keywords).prefix(6).map { ($0, depth + 1) }, at: 0)
            if !BioLink.isLinkPage(url), let host = url.host, searched.insert(host).inserted,
               let search = BioLink.searchURL(site: url, keywords: keywords) {
                queue.append((search, depth + 1))
            }
            // A Linktree-style page with no links in its HTML is drawn by script: read it as a browser would.
            if BioLink.isLinkPage(url), links.count < 2, let drawn = try? await OstaReader.html(url, seconds: 8, ready: { BioLink.links(inHTML: $0, base: url).count >= 3 }) {
                queue.insert(contentsOf: BioLink.rank(BioLink.links(inHTML: drawn, base: url), keywords: keywords).prefix(6).map { ($0, depth + 1) }, at: 0)
            }
        }
        throw sawShop ? Failure.forSale(who) : Failure.notFound(who)
    }

    /// A page's HTML, as a phone's browser would get it. Nil when it won't load.
    static func page(_ url: URL) async -> String? {
        guard let data = try? await CaptionFetcher.get(url, userAgent: CaptionFetcher.browserAgent), data.count < 8_000_000 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
