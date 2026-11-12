import Foundation

/// Reads recipes from Osta (ostarecipes.com) share links. Osta has no export, and its pages draw the recipe with
/// JavaScript, so the app opens the page out of sight in a web view and hands the page's text here. This part is plain
/// text handling so it can be tested.
public enum OstaImport {
    public enum LinkKind: Equatable, Sendable {
        case recipe(id: String)
        case folder(id: String)
    }

    public static func isOsta(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host == "ostarecipes.com" || host.hasSuffix(".ostarecipes.com")
    }

    /// What an Osta link points at: one recipe (ostarecipes.com/s/recipes/ID) or a shared folder
    /// (ostarecipes.com/sharefolder?folderId=ID).
    public static func kind(of url: URL) -> LinkKind? {
        guard isOsta(url) else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        if let i = parts.firstIndex(where: { $0.lowercased() == "recipes" || $0.lowercased() == "recipe" }), i + 1 < parts.count {
            return .recipe(id: parts[i + 1])
        }
        if parts.last?.lowercased().contains("folder") == true,
           let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "folderId" })?.value {
            return .folder(id: id)
        }
        return nil
    }

    /// The tidy link for a recipe id.
    public static func recipeURL(id: String) -> URL {
        URL(string: "https://ostarecipes.com/s/recipes/\(id)")!
    }

    /// Recipe links found on a folder page. The page's own links come first: when it has any, they're the only ones
    /// used, because "recipes/ID" in the page's code also matches ids that aren't share links (Ethan's import, 12
    /// November 2026, saved links that open Osta's "Recipe not found"). The code is only searched when the page has no
    /// recipe links at all.
    public static func recipeLinks(in found: [String]) -> [URL] {
        var linked: [String] = []
        var inCode: [String] = []
        let re = try? NSRegularExpression(pattern: #"recipes?/([A-Za-z0-9_-]{8,40})"#)
        for s in found {
            if let u = URL(string: s), case .recipe(let rid)? = kind(of: u) {
                linked.append(rid)
            } else if let re, let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) {
                inCode.append((s as NSString).substring(with: m.range(at: 1)))
            }
        }
        var seen = Set<String>()
        return (linked.isEmpty ? inCode : linked).filter { seen.insert($0).inserted }.map(recipeURL(id:))
    }

    /// The page as the web view saw it.
    public struct Page: Equatable, Sendable {
        public var title: String
        public var text: String
        public var links: [String]
        public init(title: String, text: String, links: [String] = []) {
            self.title = title; self.text = text; self.links = links
        }
    }

    /// What the page gave: recipe text laid out the way Plate's caption reader expects, plus where it came from.
    public struct Extract: Equatable, Sendable {
        public var caption: String
        public var author: String?
        /// The original Instagram or TikTok post, when the page links to it.
        public var original: URL?
    }

    /// Words on Osta's pages that are buttons and banners, not recipe.
    static let chrome: Set<String> = [
        "view in the osta app", "open app", "open in app", "save this recipe", "save recipe", "share", "get the app",
        "download the app", "osta", "osta recipes", "ingredients", "instructions", "method", "steps", "directions",
        "notes", "servings", "serves", "nutrition", "join", "log in", "sign in", "sign up", "see more", "read more", "more",
    ]

    static let unitWords: Set<String> = [
        "g", "kg", "mg", "ml", "l", "litre", "litres", "liter", "liters", "tsp", "tbsp", "teaspoon", "teaspoons",
        "tablespoon", "tablespoons", "cup", "cups", "oz", "lb", "lbs", "pinch", "pinches", "clove", "cloves", "can", "cans",
        "tin", "tins", "slice", "slices", "handful", "handfuls", "bunch", "pack", "packs", "scoop", "scoops", "x",
    ]

    /// A line that's only an amount ("2 cloves", "1/2", "200 g"), which Osta shows apart from the food's name.
    static func isAmountOnly(_ line: String) -> Bool {
        let words = line.lowercased().split(separator: " ").map(String.init)
        guard let first = words.first, words.count <= 3,
              first.first.map({ $0.isNumber || "½¼¾⅓⅔⅛".contains($0) }) == true else { return false }
        let amountChars = CharacterSet(charactersIn: "0123456789/.,-½¼¾⅓⅔⅛")
        for (i, w) in words.enumerated() {
            if w.unicodeScalars.allSatisfy({ amountChars.contains($0) }) { continue }
            // "200g" or "2tbsp"
            let digits = w.prefix { $0.isNumber || $0 == "." || $0 == "/" }
            let rest = String(w.dropFirst(digits.count))
            if i == 0, !digits.isEmpty, unitWords.contains(rest) { continue }
            if i > 0, unitWords.contains(w) { continue }
            return false
        }
        return true
    }

    static func isTimeLine(_ line: String) -> Bool {
        let l = line.lowercased()
        return (l.hasPrefix("prep") || l.hasPrefix("cook") || l.hasPrefix("total")) && (l.contains("min") || l.contains("hr") || l.contains("hour"))
    }

    static func minutes(in line: String) -> Int {
        let l = line.lowercased()
        let n = Int(l.filter(\.isNumber)) ?? 0
        return l.contains("h") && !l.contains("min") ? n * 60 : n
    }

    static func isWholeNumber(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: ". )"))
        guard !t.isEmpty, t.count <= 2, t.allSatisfy(\.isNumber) else { return nil }
        return Int(t)
    }

    /// Titles that mean the page isn't a recipe (Osta's home page, or a recipe it wouldn't show).
    static let genericTitles: Set<String> = ["", "osta", "osta recipe", "osta recipes", "osta: save & share recipes", "home"]

    /// Whether the page is one of Osta's recipe pages: it has the "Save this recipe" button or prep and cook times.
    /// Osta's home page (where a private or missing recipe lands) has neither.
    public static func isRecipePage(_ page: Page) -> Bool {
        page.text.components(separatedBy: .newlines).contains { line in
            let l = line.trimmingCharacters(in: .whitespaces).lowercased()
            return l == "save this recipe" || isTimeLine(l)
        }
    }

    /// What a page that gave no recipe was showing, so the app can say what went wrong.
    public enum Miss: Equatable, Sendable {
        /// Nothing drawn yet (still loading, or the connection dropped).
        case empty
        /// Osta's "Recipe not found": nothing is shared at this link.
        case notFound
        /// Not a recipe page: Osta's home page or a "get the app" page, which is where a private or removed recipe lands.
        case notARecipe
        /// A recipe page, but Plate couldn't pick out at least two ingredients from it.
        case unreadable
    }

    public static func miss(_ page: Page) -> Miss {
        if page.text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 { return .empty }
        if page.text.lowercased().contains("recipe not found") { return .notFound }
        let title = page.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !isRecipePage(page) || genericTitles.contains(title) { return .notARecipe }
        return .unreadable
    }

    /// Turns the text of an Osta recipe page into recipe text. Nil when the page hasn't got a recipe on it (still
    /// loading, a private recipe, Osta's home page, or a "get the app" page).
    public static func extract(_ page: Page) -> Extract? {
        guard isRecipePage(page),
              !genericTitles.contains(page.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else { return nil }
        var lines = page.text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let title = page.title.trimmingCharacters(in: .whitespacesAndNewlines)
        // The title may be cut short on screen ("Creamy Sun Dried Tomato…"), so drop any line that starts it.
        if !title.isEmpty {
            let stem = String(title.prefix(12)).lowercased()
            lines.removeAll { $0.lowercased().hasPrefix(stem) && $0.count <= title.count + 3 }
        }

        // The method: "1" on its own line then the step, or "1. Step" on one line, numbered from 1 in order.
        var steps: [String] = []
        var stepStart: Int?
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if let n = isWholeNumber(line), n == steps.count + 1, i + 1 < lines.count,
               isWholeNumber(lines[i + 1]) == nil, lines[i + 1].split(separator: " ").count >= 3 {
                if stepStart == nil { stepStart = i }
                steps.append(lines[i + 1])
                i += 2
                continue
            }
            if let dot = line.firstIndex(where: { $0 == "." || $0 == ")" }), let n = isWholeNumber(String(line[..<dot])),
               n == steps.count + 1, line[line.index(after: dot)...].split(separator: " ").count >= 3 {
                if stepStart == nil { stepStart = i }
                steps.append(line[line.index(after: dot)...].trimmingCharacters(in: .whitespaces))
                i += 1
                continue
            }
            if stepStart != nil, !steps.isEmpty {
                // A long line straight after a step carries on the step (Osta wraps long steps).
                if isWholeNumber(line) == nil, !chrome.contains(line.lowercased()), line.split(separator: " ").count >= 3,
                   steps.count > 0, i > 0, isWholeNumber(lines[i - 1]) == nil, lines[i - 1] == steps.last {
                    steps[steps.count - 1] += " " + line
                }
            }
            i += 1
        }

        // Everything before the method, after the buttons and banners, is the ingredients.
        let end = stepStart ?? lines.count
        var start = 0
        var servings: Int?
        var minutes = 0
        var author: String?
        for (j, line) in lines[..<end].enumerated() {
            let l = line.lowercased()
            if isTimeLine(line) { minutes += Self.minutes(in: line); start = max(start, j + 1); continue }
            if l == "save this recipe" || l == "open app" || l == "view in the osta app" || l == "share" {
                start = max(start, j + 1)
                // A lone number just before Share is how many it serves.
                if l == "share", j > 0, let n = isWholeNumber(lines[j - 1]), n > 0 { servings = n }
            }
        }
        // The creator's name sits under the photo, before the title's details.
        if let first = lines.first, first.split(separator: " ").count == 1, first.count <= 30, !chrome.contains(first.lowercased()),
           isWholeNumber(first) == nil, !isTimeLine(first) {
            author = first
        }

        var ingredients: [String] = []
        var pendingAmount: String?
        for line in lines[min(start, end)..<end] {
            let l = line.lowercased()
            if chrome.contains(l) || isTimeLine(line) || isWholeNumber(line) != nil || l.hasSuffix("…") || l.hasSuffix("...") { continue }
            if isAmountOnly(line) { pendingAmount = (pendingAmount.map { $0 + " " } ?? "") + line; continue }
            if let amount = pendingAmount { ingredients.append(amount + " " + line); pendingAmount = nil } else { ingredients.append(line) }
        }

        // Real ingredients have an amount or a food Plate knows; headings and blurbs have neither.
        let real = ingredients.filter { line in
            guard let r = IngredientParser.parse(line) else { return false }
            return r.quantity != nil || r.food != nil
        }
        guard real.count >= 2 else { return nil }
        var out = [title.isEmpty ? "Osta recipe" : title]
        if let servings { out.append("Serves \(servings)") }
        if minutes > 0 { out.append("Ready in \(minutes) minutes") }
        out.append("")
        out.append("Ingredients:")
        out += ingredients.map { "- " + $0 }
        if !steps.isEmpty {
            out.append("")
            out.append("Method:")
            out += steps.enumerated().map { "\($0.offset + 1). \($0.element)" }
        }
        let original = page.links.compactMap(URL.init(string:)).first {
            let p = SocialImport.platform(of: $0)
            return (p == .instagram && SocialImport.instagramCode($0) != nil) || (p == .tiktok && $0.path.contains("/video/"))
        }
        return Extract(caption: out.joined(separator: "\n"), author: author, original: original)
    }
}
