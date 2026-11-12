import Foundation

/// Splits a big paste (a list of links, or several captions) into separate recipes to import one by one.
public enum BulkImport {
    public enum Item: Equatable, Sendable {
        /// A post to fetch the caption for.
        case link(URL, SocialImport.Platform)
        /// Recipe text pasted straight in (it may also mention a link).
        case caption(String, link: URL?)

        public var link: URL? {
            switch self {
            case .link(let u, _): return u
            case .caption(_, let u): return u
            }
        }
    }

    /// Lines that separate one pasted recipe from the next: "---", "***", "===", "___" and the like.
    static func isSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.count >= 3, let first = t.first, "-*=_~".contains(first) else { return false }
        return t.allSatisfy { $0 == first }
    }

    /// Every link in the text, in order, without repeats.
    public static func links(in text: String) -> [URL] {
        guard let re = try? NSRegularExpression(pattern: #"(?:https?://)?(?:www\.)?(?:[a-z0-9-]+\.)*(?:instagram\.com|instagr\.am|tiktok\.com)/[^\s<>"']+|https?://[^\s<>"']+"#,
                                                options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        var out: [URL] = []
        var seen = Set<String>()
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var raw = ns.substring(with: m.range).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)]}!?"))
            if !raw.lowercased().hasPrefix("http") { raw = "https://" + raw }
            guard let u = URL(string: raw), u.host != nil else { continue }
            if seen.insert(key(for: u)).inserted { out.append(u) }
        }
        return out
    }

    /// The same post always gives the same key, whatever tracking bits are on the end of its link.
    public static func key(for url: URL) -> String {
        let platform = SocialImport.platform(of: url)
        if platform == .instagram, let code = SocialImport.instagramCode(url) { return "instagram:\(code)" }
        if platform == .tiktok, let id = tiktokVideoId(url) { return "tiktok:\(id)" }
        let host = (url.host ?? "").lowercased().replacingOccurrences(of: "www.", with: "")
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        return host + path
    }

    static func tiktokVideoId(_ url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        if let i = parts.firstIndex(of: "video"), i + 1 < parts.count { return parts[i + 1] }
        return nil
    }

    /// Reads a paste into recipes to import.
    ///
    /// - A list of links (one per line, or mixed in with a few words each) gives one item per link.
    /// - Recipe text gives one item per block, with blocks split by lines such as "---".
    /// - A block that's mostly a link with a short title ("Chicken orzo https://…") counts as the link.
    public static func items(in text: String) -> [Item] {
        var blocks: [[String]] = [[]]
        for line in text.components(separatedBy: .newlines) {
            if isSeparator(line) { blocks.append([]) } else { blocks[blocks.count - 1].append(line) }
        }
        var out: [Item] = []
        var seen = Set<String>()
        func add(_ item: Item) {
            if let u = item.link {
                guard seen.insert(key(for: u)).inserted else { return }
            }
            out.append(item)
        }
        for block in blocks {
            let body = block.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            let found = links(in: body)
            if looksLikeRecipe(body) {
                add(.caption(body, link: found.first))
                continue
            }
            // Not recipe text: take each link, and skip lines with no link (headings, names, "Everything !").
            for u in found { add(.link(u, SocialImport.platform(of: u))) }
        }
        return out
    }

    /// Whether some text has enough of a recipe in it to read without fetching anything.
    public static func looksLikeRecipe(_ text: String) -> Bool {
        let parsed = RecipeTextParser.parse(text)
        return parsed.ingredients.count >= 2
    }

    /// Drops the items already saved, judged by their link.
    public static func notYetImported(_ items: [Item], existingLinks: [String]) -> [Item] {
        let have = Set(existingLinks.compactMap { URL(string: $0) }.map(key(for:)))
        return items.filter { item in
            guard let u = item.link else { return true }
            return !have.contains(key(for: u))
        }
    }
}
