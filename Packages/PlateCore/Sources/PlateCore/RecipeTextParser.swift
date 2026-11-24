import Foundation

/// A recipe read from free text, such as an Instagram or TikTok caption.
public struct ParsedRecipe: Equatable, Sendable {
    public var name: String
    public var servings: Int?
    public var ingredients: [RecipeIngredient]
    public var steps: [String]
    public var minutes: Int?
    public var statedPerServing: Macros?
    public var mealTypes: [MealType]
    public var tags: [String]

    public init(name: String, servings: Int?, ingredients: [RecipeIngredient], steps: [String], minutes: Int?,
                statedPerServing: Macros?, mealTypes: [MealType], tags: [String]) {
        self.name = name; self.servings = servings; self.ingredients = ingredients; self.steps = steps
        self.minutes = minutes; self.statedPerServing = statedPerServing; self.mealTypes = mealTypes; self.tags = tags
    }

    /// Enough was found to call it a recipe.
    public var looksLikeRecipe: Bool { ingredients.count >= 2 }

    /// Portions assumed when a recipe doesn't say (Ethan, 14 November 2026: "assume a portion makes 2").
    public static let assumedServings = 2

    public func recipe(source: RecipeSource) -> Recipe {
        // A "#sauce" hashtag alone doesn't make it one ("Creamy chicken pasta #sauce"): the name decides.
        var r = Recipe(name: name, mealTypes: mealTypes, servings: servings ?? Self.assumedServings, ingredients: UnitStandard.tidy(ingredients),
                       steps: steps, minutes: minutes, tags: tags.filter { $0 != Sauces.tag }, source: source, statedPerServing: statedPerServing,
                       mealPrepFriendly: (servings ?? 1) >= 3 || tags.contains { $0.contains("mealprep") })
        if servings == nil { r.servingsGuessed = true }
        Sauces.mark(&r)
        return r
    }
}

public enum RecipeTextParser {
    enum Section { case intro, ingredients, method }

    static let ingredientHeaders = ["ingredients", "ingredient list", "you'll need", "you will need", "what you need", "what you'll need", "shopping list", "for the recipe", "ingredients needed"]
    static let methodHeaders = ["method", "instructions", "directions", "steps", "how to make it", "how to make", "how to", "recipe steps", "preparation", "prep", "to make", "method:", "cooking instructions", "instruction"]
    static let callToAction = ["view all", "p.s.", "follow", "save this", "save for", "comment", "link in bio", "like this", "share this", "tag a", "tag someone", "dm me", "full recipe", "turn on notifications", "subscribe", "check out", "my cookbook", "ebook", "use code", "discount", "sponsored", "ad |", "#ad"]
    static let cookingVerbs = ["add", "mix", "stir", "cook", "bake", "fry", "boil", "simmer", "heat", "preheat", "pour", "place", "combine", "whisk", "season", "serve", "chop", "slice", "dice", "blend", "transfer", "remove", "top", "spread", "cover", "leave", "let", "toss", "marinate", "air fry", "airfry", "roast", "grill", "microwave", "drain", "layer", "fold", "assemble", "melt", "sprinkle", "garnish", "flip", "put", "in a", "once", "meanwhile", "finally", "then", "next", "start", "first", "divide", "portion", "store", "enjoy", "rinse", "pat", "coat", "brush", "spray", "bring", "reduce", "return", "squeeze", "shred", "wrap", "fill", "roll"]

    public static func parse(_ text: String, fallbackTitle: String? = nil) -> ParsedRecipe {
        let lines = splitLines(text)
        var tags: [String] = []
        var intro: [String] = []
        var ingredients: [RecipeIngredient] = []
        var steps: [String] = []
        var section = Section.intro
        var sawIngredientHeader = false
        var stated: Macros?
        var servings: Int?
        var minutes: Int?

        for rawLine in lines {
            let (line, lineTags) = stripHashtags(rawLine)
            tags.append(contentsOf: lineTags)
            let cleaned = IngredientParser.clean(line)
            if cleaned.isEmpty { continue }
            let lowered = cleaned.lowercased()

            if let m = macros(in: cleaned) {
                stated = merge(stated, m)
                if servings == nil { servings = servingsCount(in: cleaned) }
                continue
            }
            if servings == nil, let n = servingsCount(in: cleaned) { servings = n }
            if minutes == nil, let n = minutesCount(in: cleaned), section != .ingredients { minutes = n }

            // Section headers, possibly with content after a colon ("Ingredients: 200g oats, 1 banana").
            if let (kind, remainder) = header(cleaned) {
                if kind == .ingredients { sawIngredientHeader = true }
                section = kind
                if let remainder, !remainder.isEmpty {
                    if kind == .ingredients {
                        ingredients.append(contentsOf: parseParts(splitInline(remainder)))
                    } else {
                        let step = stripStepNumber(remainder)
                        if !step.isEmpty { steps.append(step) }
                    }
                }
                continue
            }
            // A part of the recipe with its ingredients after a colon, all on one line
            // ("SMOKY TOFU: 1 block smoked tofu, 1 tsp each of paprika and cumin, drizzle of olive oil").
            if section != .method, let items = inlineList(cleaned, inIngredients: section == .ingredients) {
                sawIngredientHeader = true
                section = .ingredients
                ingredients.append(contentsOf: items)
                continue
            }
            // A sub-heading like "For the sauce:" or "Marinade" inside the ingredient list.
            if section == .ingredients, cleaned.hasSuffix(":"), cleaned.split(separator: " ").count <= 5 { continue }

            switch section {
            case .ingredients:
                // "1. Toss the tofu…" reads as one of something, so numbered steps are checked first.
                if looksLikeNumberedStep(cleaned) || (looksLikeStep(cleaned) && IngredientParser.parse(cleaned)?.quantity == nil) {
                    section = .method
                    steps.append(stripStepNumber(cleaned))
                } else {
                    let found = parseParts([cleaned])
                    if !found.isEmpty { ingredients.append(contentsOf: found) }
                }
            case .method:
                if isCallToAction(lowered) { continue }
                let step = stripStepNumber(cleaned)
                if !step.isEmpty { steps.append(step) }
            case .intro:
                if isCallToAction(lowered) { continue }
                // No header yet: decide line by line.
                if !sawIngredientHeader, let parsed = IngredientParser.parse(cleaned), parsed.quantity != nil, parsed.food != nil || startsWithAmount(cleaned),
                   isShortIngredientLine(cleaned), !looksLikeStep(cleaned) {
                    if let ing = IngredientParser.ingredient(cleaned) { ingredients.append(ing) }
                } else if looksLikeNumberedStep(cleaned) || (!ingredients.isEmpty && looksLikeStep(cleaned)) {
                    steps.append(stripStepNumber(cleaned))
                    if !ingredients.isEmpty { section = .method }
                } else {
                    intro.append(line)
                }
            }
        }

        let name = title(from: intro, fallback: fallbackTitle)
        let mealTypes = guessMealTypes(name: name, tags: tags, ingredients: ingredients, text: text)
        return ParsedRecipe(name: name, servings: servings, ingredients: dedupe(ingredients), steps: steps,
                            minutes: minutes, statedPerServing: stated, mealTypes: mealTypes,
                            tags: Array(NSOrderedSet(array: tags.map { $0.lowercased() })) as? [String] ?? tags)
    }

    // MARK: Lines

    static func splitLines(_ text: String) -> [String] {
        var out: [String] = []
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
        for line in normalised.components(separatedBy: "\n") {
            // Inline bullets: "• 200g oats • 1 banana"
            let bullets = ["•", "▪️", "▪", "◦", "‣", "✔️", "✅", "➡️", "👉", "🔸", "🔹", "▫️"]
            var parts = [line]
            for b in bullets {
                parts = parts.flatMap { $0.components(separatedBy: b) }
            }
            out.append(contentsOf: parts)
        }
        // Numbered steps run together: "1. Do this. 2. Do that."
        return out.flatMap(splitRunTogetherSteps)
    }

    static func splitRunTogetherSteps(_ line: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"(?<=[.!)])\s+(?=(?:\d{1,2}[.)]|Step \d)\s)"#) else { return [line] }
        let ns = line as NSString
        var pieces: [String] = []
        var start = 0
        for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            pieces.append(ns.substring(with: NSRange(location: start, length: m.range.location - start)))
            start = m.range.location + m.range.length
        }
        pieces.append(ns.substring(from: start))
        return pieces
    }

    /// Splits "a, b; c" into its parts, leaving commas inside brackets alone ("1 onion (red, or white)").
    static func splitInline(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for ch in text {
            if ch == "(" { depth += 1 } else if ch == ")" { depth = max(0, depth - 1) }
            if depth == 0, ch == "," || ch == ";" {
                parts.append(current); current = ""
            } else {
                current.append(ch)
            }
        }
        parts.append(current)
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Headings before a colon that are never a list of ingredients.
    static let notListHeads = ["serves", "serving", "portion", "makes", "yield", "time", "prep", "cook", "macro", "nutrition",
                               "calorie", "kcal", "method", "instruction", "step", "tip", "note", "p.s", "ps", "song", "music", "credit"]

    /// The ingredients in a line like "MANGO SALSA: 1 mango, handful of coriander, juice of 1/2 lime", or nil when the
    /// line isn't one. Needs a short heading and a list that mostly reads as ingredients; a single item counts only once
    /// the ingredients have started ("To serve: soft taco shells").
    static func inlineList(_ line: String, inIngredients: Bool) -> [RecipeIngredient]? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let head = line[..<colon].trimmingCharacters(in: .whitespaces)
        let rest = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !head.isEmpty, !rest.isEmpty, head.split(separator: " ").count <= 5,
              head.contains(where: \.isLetter), !head.contains(where: \.isNumber) else { return nil }
        let lowHead = head.lowercased()
        if notListHeads.contains(where: { lowHead.hasPrefix($0) || lowHead.contains(" " + $0) }) && lowHead != "to serve" { return nil }
        let parts = expandEach(splitInline(rest))
        let read = parts.filter { !looksLikeStep($0) }.compactMap(IngredientParser.ingredient)
        if parts.count >= 2 {
            guard read.count >= 2, Double(read.count) >= Double(parts.count) * 0.5 else { return nil }
        } else {
            guard inIngredients, read.count == 1, !looksLikeStep(rest) else { return nil }
        }
        return read.flatMap(splitPair)
    }

    /// Reads list parts as ingredients, sharing out "1 tsp each of" amounts.
    static func parseParts(_ parts: [String]) -> [RecipeIngredient] {
        expandEach(parts).compactMap(IngredientParser.ingredient).flatMap(splitPair)
    }

    /// "chopped jalapeños and coriander" with no amount is two ingredients ("salt & pepper" stays one). Lines with an amount
    /// are left to `IngredientSplit` when the recipe is built.
    static func splitPair(_ ing: RecipeIngredient) -> [RecipeIngredient] {
        guard ing.quantity == nil, let parts = IngredientSplit.parts(of: ing.name) else { return [ing] }
        return parts.map { RecipeIngredient(name: $0.name, foodId: $0.food.id, quantity: nil, note: ing.note, optional: ing.optional) }
    }

    /// Shares out "1 tsp each of smoked paprika, onion granules, oregano and cumin": the parts after the one saying
    /// "each" that have no amount of their own get the same amount, up to and including one joined with "and".
    static func expandEach(_ parts: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < parts.count {
            guard let (amount, first) = eachSplit(parts[i]) else { out.append(parts[i]); i += 1; continue }
            var foods = andSplit(first)
            var j = i + 1
            if foods.count == 1 {
                while j < parts.count, IngredientParser.parse(parts[j])?.quantity == nil, !startsWithAmount(parts[j]) {
                    let pieces = andSplit(parts[j])
                    foods.append(contentsOf: pieces)
                    j += 1
                    if pieces.count > 1 { break }
                }
            }
            out.append(contentsOf: foods.map { amount + " " + $0 })
            i = j
        }
        return out
    }

    /// "1 tsp each of paprika" → ("1 tsp", "paprika"). Nil when there's no amount before "each".
    static func eachSplit(_ part: String) -> (String, String)? {
        guard let re = try? NSRegularExpression(pattern: #"^(.+?)\s+each(?:\s+of)?\s+(.+)$"#, options: [.caseInsensitive]) else { return nil }
        let ns = part as NSString
        guard let m = re.firstMatch(in: part, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let amount = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        let rest = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
        guard IngredientParser.leadingNumber(Substring(amount)) != nil || IngredientParser.leadingUnit(Substring(amount)) != nil,
              amount.split(separator: " ").count <= 3 else { return nil }
        return (amount, rest)
    }

    static func andSplit(_ s: String) -> [String] {
        s.components(separatedBy: " and ").flatMap { $0.components(separatedBy: " & ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func splitSentences(_ text: String) -> [String] {
        text.components(separatedBy: ". ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func stripHashtags(_ line: String) -> (String, [String]) {
        var tags: [String] = []
        var words: [String] = []
        for word in line.split(separator: " ", omittingEmptySubsequences: false) {
            if word.hasPrefix("#"), word.count > 1 {
                tags.append(String(word.dropFirst()).trimmingCharacters(in: .punctuationCharacters))
            } else if word.hasPrefix("@"), word.count > 1 {
                continue
            } else {
                words.append(String(word))
            }
        }
        return (words.joined(separator: " "), tags)
    }

    static func header(_ line: String) -> (Section, String?)? {
        let lowered = line.lowercased()
        let head: String
        let remainder: String?
        if let colon = lowered.firstIndex(of: ":") {
            head = String(lowered[..<colon]).trimmingCharacters(in: .whitespaces)
            let rest = String(line[line.index(after: line.firstIndex(of: ":")!)...]).trimmingCharacters(in: .whitespaces)
            remainder = rest.isEmpty ? nil : rest
        } else {
            head = lowered.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
            remainder = nil
        }
        let words = head.split(separator: " ").count
        guard words <= 5 else { return nil }
        let bare = head.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces).union(.symbols))
        func matches(_ list: [String]) -> Bool {
            list.contains { bare == $0 || bare.hasPrefix($0 + " (") || bare.hasPrefix($0 + " for") || bare.hasSuffix(" " + $0) }
        }
        if matches(ingredientHeaders) || bare.hasPrefix("ingredients") { return (.ingredients, remainder) }
        if matches(methodHeaders) || bare.hasPrefix("method") || bare.hasPrefix("instructions") { return (.method, remainder) }
        return nil
    }

    static func startsWithAmount(_ line: String) -> Bool {
        guard let f = line.first else { return false }
        return (f.isASCII && f.isNumber) || IngredientParser.unicodeFractions[f] != nil
    }

    static func isCallToAction(_ lowered: String) -> Bool { callToAction.contains { lowered.contains($0) } }

    static func looksLikeNumberedStep(_ line: String) -> Bool {
        let l = line.lowercased()
        if l.hasPrefix("step ") { return true }
        guard let re = try? NSRegularExpression(pattern: #"^\d{1,2}\s*[.)\-:]\s+\S"#) else { return false }
        guard re.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil else { return false }
        // "2. 200g chicken" is a numbered ingredient, not a step.
        let body = stripStepNumber(line)
        if let p = IngredientParser.parse(body), p.quantity != nil, isShortIngredientLine(body), !looksLikeStep(body) { return false }
        return true
    }

    static func looksLikeStep(_ line: String) -> Bool {
        let body = stripStepNumber(line).lowercased()
        let words = body.split(separator: " ")
        if words.count >= 9 { return true }
        return cookingVerbs.contains { body.hasPrefix($0 + " ") || body.hasPrefix($0 + ",") }
    }

    static func isShortIngredientLine(_ line: String) -> Bool {
        line.count <= 70 && line.split(separator: " ").count <= 10 && !line.hasSuffix("?")
    }

    public static func stripStepNumber(_ line: String) -> String {
        var s = line
        if let re = try? NSRegularExpression(pattern: #"^(?:step\s*)?\d{1,2}\s*[.):\-]?\s*"#, options: [.caseInsensitive]) {
            let ns = s as NSString
            if let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
                // Keep "200g ..." intact: only strip when what's left doesn't start with a unit.
                let rest = ns.substring(from: m.range.length)
                if IngredientParser.leadingUnit(Substring(rest)) == nil { s = rest }
            }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Numbers in the text

    static func firstInt(_ pattern: String, in text: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        for i in 1..<m.numberOfRanges where m.range(at: i).location != NSNotFound {
            if let v = Int(ns.substring(with: m.range(at: i))) { return v }
        }
        return nil
    }

    static func firstDouble(_ pattern: String, in text: String) -> Double? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        for i in 1..<m.numberOfRanges where m.range(at: i).location != NSNotFound {
            if let v = Double(ns.substring(with: m.range(at: i)).replacingOccurrences(of: ",", with: ".")) { return v }
        }
        return nil
    }

    static func servingsCount(in line: String) -> Int? {
        let n = firstInt(#"(?:serves|servings?:?|portions?:?|makes|yields?:?)\s*(\d{1,2})\b|(\d{1,2})\s*(?:servings|portions|serves|meal preps?|meals)\b"#, in: line)
        return n.flatMap { (1...40).contains($0) ? $0 : nil }
    }

    static func minutesCount(in line: String) -> Int? {
        let n = firstInt(#"(\d{1,3})\s*(?:mins?|minutes)\b"#, in: line)
        return n.flatMap { (1...600).contains($0) ? $0 : nil }
    }

    /// Macro lines like "520 cals | 45g protein | 50g carbs | 12g fat" or "Calories: 450, P: 40g, C: 30g, F: 10g".
    static func macros(in line: String) -> Macros? {
        let l = line.lowercased()
        let num = #"(\d+(?:[.,]\d+)?)"#
        let kcal = firstDouble(num + #"\s*(?:kcals?|cals?|calories)\b"#, in: l) ?? firstDouble(#"(?:kcals?|cals?|calories|energy)\s*[:\-=]?\s*"# + num, in: l)
        let protein = firstDouble(num + #"\s*g?\s*(?:of\s+)?(?:protein|prot|pro)\b"#, in: l) ?? firstDouble(#"(?:protein|prot|\bp)\s*[:\-=]?\s*"# + num, in: l)
        let carbs = firstDouble(num + #"\s*g?\s*(?:of\s+)?(?:carbs?|carbohydrates?)\b"#, in: l) ?? firstDouble(#"(?:carbs?|carbohydrates?|\bc)\s*[:\-=]?\s*"# + num, in: l)
        let fat = firstDouble(num + #"\s*g?\s*(?:of\s+)?fats?\b"#, in: l) ?? firstDouble(#"(?:fats?|\bf)\s*[:\-=]?\s*"# + num, in: l)
        let found = [kcal, protein, carbs, fat].compactMap { $0 }.count
        // Needs calories plus one macro, or three macros, so "20g protein powder" isn't read as a macro line.
        guard (kcal != nil && found >= 2) || found >= 3 else { return nil }
        if found < 3 && IngredientParser.parse(line)?.food != nil && kcal == nil { return nil }
        return Macros(kcal: kcal ?? ((protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9), protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0)
    }

    static func merge(_ a: Macros?, _ b: Macros) -> Macros {
        guard let a else { return b }
        return Macros(kcal: a.kcal > 0 ? a.kcal : b.kcal, protein: a.protein > 0 ? a.protein : b.protein,
                      carbs: a.carbs > 0 ? a.carbs : b.carbs, fat: a.fat > 0 ? a.fat : b.fat, fibre: a.fibre)
    }

    // MARK: Title and type

    /// Words that name a dish, used to pick the dish out of a chatty opening ("Got the gravy ick? … Smoky mango
    /// tofu tacos, really easy" is "Smoky Mango Tofu Tacos", not "Got the gravy ick": Ethan, 24 November 2026).
    static let dishWords: Set<String> = [
        "taco", "tacos", "curry", "pasta", "salad", "bowl", "bowls", "soup", "stew", "wrap", "wraps", "burger", "burgers",
        "pizza", "noodles", "noodle", "stir", "fry", "chilli", "sandwich", "toastie", "bites", "traybake", "bake", "pie",
        "risotto", "lasagne", "lasagna", "burrito", "burritos", "quesadilla", "quesadillas", "fajitas", "nachos", "gnocchi",
        "dhal", "dal", "daal", "ramen", "pancakes", "oats", "cake", "cookies", "brownies", "bars", "smoothie", "omelette",
        "frittata", "shakshuka", "tikka", "masala", "korma", "katsu", "biryani", "orzo", "dumplings", "gyoza", "kebab",
        "kebabs", "skewers", "salsa", "dip", "hummus", "houmous", "pesto", "sauce", "dressing", "rolls", "tart", "muffins",
        "granola", "porridge", "toast", "bagel", "flatbread", "flatbreads", "fritters", "patties", "meatballs", "falafel",
        "enchiladas", "tostadas", "poke", "buddha", "rice", "casserole", "hash", "jacket", "loaded", "fries", "wings",
        "nuggets", "goujons", "sliders", "bao", "pad", "laksa", "pho", "tagine", "gumbo", "jambalaya", "paella", "ragu",
        "bolognese", "carbonara", "mac", "cheesecake", "crumble", "pudding", "flapjacks", "energy", "protein",
    ]

    /// The opening split into its sentences, each cut down to the part that could be a name.
    static func titleCandidates(_ intro: [String]) -> [(text: String, question: Bool)] {
        var out: [(String, Bool)] = []
        for raw in intro {
            // Emoji and sentence ends both close a candidate ("Chicken fajita bowls 🌯 Only 520 cals").
            var current = ""
            func close(question: Bool) {
                var t = IngredientParser.clean(current)
                current = ""
                for sep in [" | ", " – ", " - ", ", "] {
                    guard let r = t.range(of: sep), t.distance(from: t.startIndex, to: r.lowerBound) >= 8 else { continue }
                    // "Halloumi, pepper and rice bowl" keeps its comma; "Smoky mango tofu tacos, really easy" loses the chat.
                    if sep == ", ", t[..<r.lowerBound].split(separator: " ").count < 2 { continue }
                    t = String(t[..<r.lowerBound])
                }
                t = t.trimmingCharacters(in: CharacterSet(charactersIn: " !.:-–*\"'"))
                if !t.isEmpty { out.append((t, question)) }
            }
            let chars = Array(raw)
            for (i, ch) in chars.enumerated() {
                if ch.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x2000) }) {
                    if current.trimmingCharacters(in: .whitespaces).count >= 3 { close(question: false) } else { current = "" }
                    continue
                }
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                if ch == "?" { current.append(ch); close(question: true); continue }
                if (ch == "!" || ch == "."), next == " ", current.trimmingCharacters(in: .whitespaces).count >= 8 {
                    close(question: false); continue
                }
                current.append(ch)
            }
            close(question: false)
        }
        return out.map { (text: $0.0, question: $0.1) }
    }

    static func title(from intro: [String], fallback: String?) -> String {
        let candidates = titleCandidates(intro).filter { c in
            c.text.count >= 3 && c.text.count <= 70 && !isCallToAction(c.text.lowercased())
        }
        func words(_ t: String) -> [String] { FoodMatcher.tokens(t) }
        // First choice: a short sentence that names a dish. Then the first sentence that isn't a question hook.
        let dish = candidates.first { c in
            !c.question && words(c.text).count <= 8 && c.text.lowercased().split(separator: " ").contains { dishWords.contains(String($0)) }
        }
        if let pick = dish ?? candidates.first(where: { !$0.question }) ?? candidates.first {
            let t = pick.text.trimmingCharacters(in: CharacterSet(charactersIn: " ?"))
            if t.count >= 3 { return titleCase(t) }
        }
        if let fallback, !fallback.isEmpty { return fallback }
        return "Imported recipe"
    }

    /// Whether a name is the caption's opening question rather than the dish ("Got the gravy ick?"), so an AI's
    /// name taken from it can be swapped for Plate's own.
    public static func isHook(_ name: String, in caption: String) -> Bool {
        let n = name.trimmingCharacters(in: CharacterSet(charactersIn: " ?!.")).lowercased()
        guard n.count >= 3 else { return false }
        return titleCandidates(splitLines(caption)).contains { $0.question && $0.text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " ?")) == n }
    }

    static func titleCase(_ s: String) -> String {
        // Leave mixed case alone; tidy all-caps or all-lower titles.
        if s == s.uppercased() || s == s.lowercased() {
            let small: Set<String> = ["and", "with", "of", "the", "a", "in", "on", "for", "to", "or"]
            return s.lowercased().split(separator: " ").enumerated().map { i, w in
                i > 0 && small.contains(String(w)) ? String(w) : w.prefix(1).uppercased() + w.dropFirst()
            }.joined(separator: " ")
        }
        return s
    }

    public static func guessMealTypes(name: String, tags: [String], ingredients: [RecipeIngredient], text: String) -> [MealType] {
        let hay = (name + " " + tags.joined(separator: " ")).lowercased()
        let foods = Set(ingredients.compactMap(\.foodId))
        if ["breakfast", "brekkie", "porridge", "overnight oats", "pancake", "granola", "french toast", "smoothie", "omelette", "omelet", "bagel", "scrambled", "brunch", "shakshuka", "muffin"].contains(where: hay.contains)
            || (foods.contains("oats") && !foods.contains(where: { ["chicken-breast", "beef-mince", "salmon"].contains($0) })) {
            return [.breakfast]
        }
        if ["snack", "bites", "energy balls", "protein balls", "bars", "cookie", "brownie", "dessert", "cheesecake", "pudding", "treat", "flapjack", "mug cake", "ice cream", "fro yo"].contains(where: hay.contains) {
            return [.snack]
        }
        if ["lunch", "wrap", "sandwich", "salad", "toastie", "bowl", "quesadilla", "soup"].contains(where: hay.contains) {
            return [.lunch, .dinner]
        }
        return [.dinner, .lunch]
    }

    static func dedupe(_ list: [RecipeIngredient]) -> [RecipeIngredient] {
        var seen = Set<String>()
        return list.filter { ing in
            let key = ing.name.lowercased() + "|" + (ing.quantity.map { "\($0.amount)\($0.unit)" } ?? "")
            return seen.insert(key).inserted
        }
    }
}
