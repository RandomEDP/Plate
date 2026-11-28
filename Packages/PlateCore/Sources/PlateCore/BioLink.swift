import Foundation

/// When a caption says "recipe in bio", Plate follows the creator's bio link (a Linktree page or their own website)
/// and looks for the recipe there (Ethan, 28 November 2026). This is the pure part: spotting the phrase, pulling the
/// bio link out of a profile page, picking the right link on the creator's page, and reading a recipe card.
/// The app does the fetching (`App/BioFinder.swift`). Only the creator's public pages are requested.
public enum BioLink {
    // MARK: Does the caption point at the bio?

    /// "Recipe in bio", "full recipe linked in my bio", "sign up to the cookbook in bio", "#linkinbio".
    public static func mentionsBio(_ caption: String) -> Bool {
        let patterns = [
            #"\b(?:link|links|linked|recipe|recipes|cookbook|cook book|e-?book|blog|website|site|method|details|newsletter)\b[^.!?\n]{0,40}?\b(?:in|on|at|via)\s+(?:my\s+|the\s+|our\s+)?(?:bio|profile)\b"#,
            #"\bbio\s*link\b"#,
            #"#linkinbio\b"#,
            #"🔗\s*(?:in\s+)?(?:my\s+)?bio\b"#,
        ]
        return patterns.contains { caption.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    // MARK: The creator's profile and its bio link

    /// The creator's public profile page: Instagram from the username, TikTok from the post's address.
    public static func profileURL(platform: SocialImport.Platform, post: URL?, author: String?) -> URL? {
        switch platform {
        case .instagram:
            guard let name = author?.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")),
                  name.range(of: #"^[A-Za-z0-9._]{1,30}$"#, options: .regularExpression) != nil else { return nil }
            return URL(string: "https://www.instagram.com/\(name)/")
        case .tiktok:
            if let post, let user = post.path.split(separator: "/").first(where: { $0.hasPrefix("@") && $0.count > 1 }) {
                return URL(string: "https://www.tiktok.com/\(user)")
            }
            guard let name = author?.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")),
                  name.range(of: #"^[A-Za-z0-9._]{2,24}$"#, options: .regularExpression) != nil else { return nil }
            return URL(string: "https://www.tiktok.com/@\(name)")
        case .youtube, .web:
            return nil
        }
    }

    /// Bio links on an Instagram profile page, once its script has drawn it: Instagram sends them through its
    /// `l.instagram.com/?u=` redirect.
    public static func instagramBioLinks(_ html: String) -> [URL] {
        var out: [URL] = []
        let raw = html.replacingOccurrences(of: "&amp;", with: "&")
        for m in matches(#"l\.instagram\.com/?\?u=([^&"'\s<>]+)"#, in: raw) {
            if let s = m.first?.removingPercentEncoding, let url = webURL(s), !out.contains(url) { out.append(url) }
        }
        return out.filter { !isSocial($0) }
    }

    /// Bio links on a TikTok profile page: the "bioLink" in the page's data, then any web address in the bio text.
    public static func tiktokBioLinks(_ html: String) -> [URL] {
        var out: [URL] = []
        for m in matches(#""bioLink"\s*:\s*\{[^}]*?"link"\s*:\s*"([^"]+)""#, in: html) {
            if let s = m.first.map(unescapeJSON), let url = webURL(s), !out.contains(url) { out.append(url) }
        }
        for m in matches(#""signature"\s*:\s*"((?:[^"\\]|\\.)*)""#, in: html) {
            for url in urls(inText: unescapeJSON(m.first ?? "")) where !out.contains(url) { out.append(url) }
        }
        return out.filter { !isSocial($0) }
    }

    /// Web addresses written in a bio: "linktr.ee/kel", "www.kelcooks.com/recipes". Email addresses don't count.
    public static func urls(inText text: String) -> [URL] {
        var out: [URL] = []
        let pattern = #"(?<![@\w.])((?:https?://)?(?:www\.)?[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,6}(?:/[^\s"'<>]*)?)"#
        for m in matches(pattern, in: text, caseInsensitive: true) {
            guard var s = m.first else { continue }
            s = s.trimmingCharacters(in: CharacterSet(charactersIn: ".,!)"))
            let lower = s.lowercased()
            // A bare "word.word" is often just a sentence ("done.Next"): only addresses that clearly are one.
            let clear = lower.hasPrefix("http") || lower.hasPrefix("www.") || lower.contains("/") || linkPageHosts.contains { lower.hasPrefix($0) }
            if clear, let url = webURL(s), !out.contains(url) { out.append(url) }
        }
        return out
    }

    // MARK: The creator's page

    public struct Link: Equatable, Sendable {
        public var text: String
        public var url: URL
        public init(text: String, url: URL) { self.text = text; self.url = url }
    }

    /// Every link on a page with its words, made absolute. Script links, emails and in-page jumps are left out.
    public static func links(inHTML html: String, base: URL) -> [Link] {
        var out: [Link] = []
        var seen = Set<String>()
        for m in matches(#"<a\b([^>]*)>(.*?)</a>"#, in: html, dotAll: true) {
            guard m.count == 2, let href = attribute("href", in: m[0]) else { continue }
            let h = SocialImport.decodeEntities(href).trimmingCharacters(in: .whitespaces)
            let lower = h.lowercased()
            if lower.hasPrefix("#") || lower.hasPrefix("mailto:") || lower.hasPrefix("tel:") || lower.hasPrefix("javascript:") { continue }
            guard let url = URL(string: h, relativeTo: base)?.absoluteURL, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
            var text = stripTags(m[1])
            for extra in ["aria-label", "title"] where text.isEmpty { text = attribute(extra, in: m[0]).map(SocialImport.decodeEntities) ?? "" }
            let key = url.absoluteString
            if seen.insert(key).inserted { out.append(Link(text: text, url: url)) }
        }
        return out
    }

    /// Link-in-bio services: a page that's only a list of links.
    static let linkPageHosts = ["linktr.ee", "beacons.ai", "lnk.bio", "linkin.bio", "msha.ke", "campsite.bio", "tap.bio",
                                "bio.link", "solo.to", "hoo.be", "komi.io", "linkpop.com", "carrd.co", "flow.page",
                                "allmylinks.com", "snipfeed.co", "milkshake.app", "url.bio", "later.com", "linkbio.co"]

    public static func isLinkPage(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return linkPageHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Shops: a cookbook or e-book for sale, which Plate can't read.
    static let shopHosts = ["stan.store", "gumroad.com", "payhip.com", "etsy.com", "amazon.co.uk", "amazon.com", "amzn.to",
                            "shopify.com", "teachable.com", "kajabi.com", "podia.com", "patreon.com", "ko-fi.com", "buymeacoffee.com",
                            "waterstones.com", "bookshop.org", "lemonsqueezy.com", "sellfy.com", "thinkific.com", "substack.com"]

    public static func isShop(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        if shopHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return true }
        let path = url.path.lowercased()
        return ["/products/", "/product/", "/checkout", "/cart", "/shop"].contains { path.contains($0) }
    }

    static let socialHosts = ["instagram.com", "tiktok.com", "youtube.com", "youtu.be", "facebook.com", "fb.com", "x.com",
                              "twitter.com", "threads.net", "pinterest.com", "pinterest.co.uk", "spotify.com", "snapchat.com",
                              "whatsapp.com", "wa.me", "t.me", "twitch.tv", "apple.com", "linkedin.com", "google.com", "goo.gl"]

    public static func isSocial(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return socialHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // MARK: Choosing the link

    static let stopWords: Set<String> = [
        "the", "and", "with", "for", "you", "your", "this", "that", "from", "into", "out", "its", "it's", "are", "was", "but",
        "all", "get", "got", "how", "make", "made", "making", "easy", "quick", "best", "ever", "recipe", "recipes", "full",
        "link", "bio", "here", "now", "today", "new", "my", "our", "just", "really", "so", "too", "very", "only", "one",
        "minute", "minutes", "mins", "min", "ready", "under", "day", "week", "home", "free", "follow", "save", "share",
        "comment", "high", "protein", "low", "calorie", "calories", "healthy", "delicious", "tasty", "vegan", "veggie",
        "vegetarian", "plant", "based", "dinner", "lunch", "breakfast", "meal", "prep", "what", "when", "who", "why",
    ]

    /// The words that pick out this dish: the title's words count fully, words from the caption's opening half.
    public static func keywords(title: String, caption: String) -> [String: Double] {
        var out: [String: Double] = [:]
        func words(_ s: String) -> [String] {
            FoodMatcher.tokens(s).filter { $0.count >= 3 && !stopWords.contains($0) && !$0.allSatisfy(\.isNumber) }
        }
        for w in words(String(caption.prefix(300))) { out[w] = 0.5 }
        for w in words(title) { out[w] = 1 }
        return out
    }

    /// How well a link (its words and its address) matches the dish.
    public static func score(_ text: String, url: URL?, keywords: [String: Double]) -> Double {
        var hay = Set(FoodMatcher.tokens(text))
        if let url {
            hay.formUnion(FoodMatcher.tokens(url.path.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")))
        }
        return keywords.reduce(0) { $0 + (hay.contains($1.key) ? $1.value : 0) }
    }

    /// Enough of a match to follow, or to take a recipe card as this dish.
    public static func isMatch(_ score: Double, keywords: [String: Double]) -> Bool {
        let titleWords = keywords.values.filter { $0 >= 1 }.count
        return score >= 2 || (titleWords == 1 && score >= 1) || (titleWords == 0 && score >= 1.5)
    }

    /// Links worth opening on a creator's page, best first: ones naming the dish, then their recipe pages or website.
    public static func rank(_ links: [Link], keywords: [String: Double]) -> [URL] {
        var scored: [(Double, URL)] = []
        for link in links where !isSocial(link.url) && !isShop(link.url) {
            let s = score(link.text, url: link.url, keywords: keywords)
            if isMatch(s, keywords: keywords) {
                scored.append((10 + s, link.url))
            } else {
                let t = (link.text + " " + link.url.path).lowercased()
                if ["recipe", "blog", "website", "my site", "cook"].contains(where: t.contains) { scored.append((1, link.url)) }
            }
        }
        var seen = Set<URL>()
        return scored.sorted { $0.0 > $1.0 }.map(\.1).filter { seen.insert($0).inserted }
    }

    /// The site's own search for the dish (WordPress, which most recipe blogs run on, answers `?s=`).
    public static func searchURL(site: URL, keywords: [String: Double]) -> URL? {
        let words = keywords.filter { $0.value >= 1 }.map(\.key).sorted()
        let terms = (words.isEmpty ? keywords.sorted { $0.value > $1.value }.prefix(3).map(\.key) : Array(words.prefix(4)))
        guard !terms.isEmpty, var c = URLComponents(string: "\(site.scheme ?? "https")://\(site.host ?? "")/") else { return nil }
        c.queryItems = [URLQueryItem(name: "s", value: terms.joined(separator: " "))]
        return c.url
    }

    // MARK: Helpers

    static func matches(_ pattern: String, in text: String, caseInsensitive: Bool = true, dotAll: Bool = false) -> [[String]] {
        var opts: NSRegularExpression.Options = []
        if caseInsensitive { opts.insert(.caseInsensitive) }
        if dotAll { opts.insert(.dotMatchesLineSeparators) }
        guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (1..<max(1, m.numberOfRanges)).map { i in
                m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i))
            }
        }
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        matches(#"\b"# + name + #"\s*=\s*(?:"([^"]*)"|'([^']*)')"#, in: tag).first.map { $0.first(where: { !$0.isEmpty }) ?? "" }
    }

    static func stripTags(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        s = SocialImport.decodeEntities(s)
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func unescapeJSON(_ s: String) -> String {
        guard let data = "\"\(s)\"".data(using: .utf8), let out = try? JSONDecoder().decode(String.self, from: data) else {
            return s.replacingOccurrences(of: "\\u002F", with: "/").replacingOccurrences(of: "\\/", with: "/")
        }
        return out
    }

    static func webURL(_ s: String) -> URL? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if !t.lowercased().hasPrefix("http") { t = "https://" + t }
        guard let url = URL(string: t), let host = url.host, host.contains(".") else { return nil }
        return url
    }
}

/// Reads the recipe card that recipe websites put in their pages for search engines (schema.org "Recipe" in
/// JSON-LD: WP Recipe Maker, Tasty Recipes and most others), and lays it out as caption text for `RecipeTextParser`.
public enum RecipeSchema {
    public struct Card: Equatable, Sendable {
        public var name: String
        public var text: String
        public var image: URL?
    }

    public static func card(inHTML html: String) -> Card? {
        for m in BioLink.matches(#"<script[^>]*application/ld\+json[^>]*>(.*?)</script>"#, in: html, dotAll: true) {
            guard let raw = m.first, let data = raw.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let recipe = findRecipe(json), let card = card(from: recipe) { return card }
        }
        return nil
    }

    static func findRecipe(_ json: Any) -> [String: Any]? {
        if let dict = json as? [String: Any] {
            let type = dict["@type"]
            if (type as? String) == "Recipe" || (type as? [String])?.contains("Recipe") == true { return dict }
            for key in ["@graph", "mainEntity", "itemListElement"] {
                if let inner = dict[key], let found = findRecipe(inner) { return found }
            }
        } else if let list = json as? [Any] {
            for item in list { if let found = findRecipe(item) { return found } }
        }
        return nil
    }

    static func text(_ any: Any?) -> String? {
        if let s = any as? String { return BioLink.stripTags(s) }
        if let n = any as? NSNumber { return n.stringValue }
        if let list = any as? [Any] { return list.compactMap { text($0) }.first }
        if let dict = any as? [String: Any] { return text(dict["text"] ?? dict["name"] ?? dict["@value"]) }
        return nil
    }

    static func steps(_ any: Any?) -> [String] {
        if let s = any as? String {
            return s.components(separatedBy: CharacterSet.newlines).map(BioLink.stripTags).filter { !$0.isEmpty }
        }
        if let list = any as? [Any] { return list.flatMap { steps($0) } }
        if let dict = any as? [String: Any] {
            if let items = dict["itemListElement"] { return steps(items) }  // a HowToSection
            if let t = text(dict["text"] ?? dict["name"]) { return [t] }
        }
        return []
    }

    /// "PT1H20M" → 80.
    static func minutes(_ iso: String?) -> Int? {
        guard let iso, iso.hasPrefix("P") else { return nil }
        let h = BioLink.matches(#"(\d+)H"#, in: iso).first?.first.flatMap(Int.init) ?? 0
        let m = BioLink.matches(#"(\d+)M"#, in: iso).first?.first.flatMap(Int.init) ?? 0
        let total = h * 60 + m
        return total > 0 ? total : nil
    }

    static func card(from r: [String: Any]) -> Card? {
        guard let name = text(r["name"]), !name.isEmpty else { return nil }
        let ingredients = ((r["recipeIngredient"] ?? r["ingredients"]) as? [Any] ?? []).compactMap { text($0) }.filter { !$0.isEmpty }
        guard ingredients.count >= 2 else { return nil }
        var lines = [name]
        if let y = text(r["recipeYield"]), let n = BioLink.matches(#"(\d{1,2})"#, in: y).first?.first { lines.append("Serves \(n)") }
        if let m = minutes(text(r["totalTime"])) ?? minutes(text(r["cookTime"])) { lines.append("Ready in \(m) minutes") }
        lines.append("")
        lines.append("Ingredients:")
        lines.append(contentsOf: ingredients)
        let method = steps(r["recipeInstructions"])
        if !method.isEmpty {
            lines.append("")
            lines.append("Method:")
            lines.append(contentsOf: method.enumerated().map { "\($0.offset + 1). \($0.element)" })
        }
        if let n = r["nutrition"] as? [String: Any] {
            func num(_ key: String) -> String? {
                text(n[key]).flatMap { BioLink.matches(#"(\d+(?:\.\d+)?)"#, in: $0).first?.first }
            }
            var parts: [String] = []
            if let k = num("calories") { parts.append("\(k) kcal") }
            if let p = num("proteinContent") { parts.append("\(p)g protein") }
            if let c = num("carbohydrateContent") { parts.append("\(c)g carbs") }
            if let f = num("fatContent") { parts.append("\(f)g fat") }
            if parts.count >= 2 { lines.append(""); lines.append("Macros per serving: " + parts.joined(separator: " | ")) }
        }
        var image: URL?
        if let i = r["image"] {
            let s = (i as? String) ?? (i as? [Any])?.compactMap({ ($0 as? String) ?? (($0 as? [String: Any])?["url"] as? String) }).first
                ?? ((i as? [String: Any])?["url"] as? String)
            image = s.flatMap(URL.init(string:))
        }
        return Card(name: name, text: lines.joined(separator: "\n"), image: image)
    }
}
