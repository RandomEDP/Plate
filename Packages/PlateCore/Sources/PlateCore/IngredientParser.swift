import Foundation

/// Finds the built-in food that an ingredient's name refers to ("2 large chicken breasts, diced" → chicken breast).
public enum FoodMatcher {
    struct Alias { let tokens: [String]; let foodId: String; let length: Int }

    static let aliases: [Alias] = {
        var out: [Alias] = []
        for food in FoodDatabase.all {
            var seen = Set<String>()
            for raw in [food.name] + food.aliases {
                let t = tokens(raw)
                let key = t.joined(separator: " ")
                if t.isEmpty || seen.contains(key) { continue }
                seen.insert(key)
                out.append(Alias(tokens: t, foodId: food.id, length: key.count))
            }
        }
        return out
    }()

    /// Words that describe how something is prepared or how big it is, ignored when matching.
    static let fillerWords: Set<String> = [
        "fresh", "large", "medium", "small", "big", "chopped", "diced", "sliced", "minced", "grated", "finely", "roughly",
        "thinly", "crushed", "peeled", "deseeded", "halved", "quartered", "cubed", "shredded", "cooked", "uncooked", "raw",
        "frozen", "tinned", "canned", "dried", "ripe", "organic", "boneless", "skinless", "of", "a", "an", "the", "and", "or",
        "about", "approx", "approximately", "roughly", "packed", "heaped", "level", "few", "some", "optional", "x", "lean",
    ]

    static func singular(_ w: String) -> String {
        if w.count <= 3 || w.hasSuffix("ss") || w.hasSuffix("us") { return w }
        if w.hasSuffix("llies") { return String(w.dropLast(2)) }  // chillies → chilli
        if w.hasSuffix("ies") { return String(w.dropLast(3)) + "y" }
        if w.hasSuffix("oes") { return String(w.dropLast(2)) }
        if w.hasSuffix("ves") { return String(w.dropLast(3)) + "f" }
        if w.hasSuffix("ches") || w.hasSuffix("shes") { return String(w.dropLast(2)) }
        if w.hasSuffix("s") { return String(w.dropLast()) }
        return w
    }

    static func tokens(_ s: String) -> [String] {
        let lowered = s.lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_GB"))
            .replacingOccurrences(of: "’", with: "'")
        var words: [String] = []
        var current = ""
        for ch in lowered {
            if ch.isLetter || ch == "'" || ch == "%" || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                words.append(current); current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.map { singular($0.replacingOccurrences(of: "'", with: "")) }
    }

    /// The best match, preferring the longest alias found anywhere in the name. An alias found word for word beats
    /// one that only matches once words like "chopped" or "frozen" are ignored.
    public static func match(_ name: String) -> Food? {
        let raw = tokens(name)
        let filtered = raw.filter { !fillerWords.contains($0) }
        guard !filtered.isEmpty else { return nil }
        var best: (score: Int, length: Int, id: String)?
        for a in aliases {
            var score: Int?
            if contains(raw, a.tokens) {
                score = a.tokens.count * 10
            } else {
                let af = a.tokens.filter { !fillerWords.contains($0) }
                if !af.isEmpty, contains(filtered, af) { score = af.count * 10 - (a.tokens.count - af.count) }
            }
            guard let sc = score else { continue }
            if best == nil || sc > best!.score || (sc == best!.score && a.length < best!.length) {
                best = (sc, a.length, a.foodId)
            }
        }
        return best.flatMap { FoodDatabase.byId[$0.id] }
    }

    static func contains(_ hay: [String], _ needle: [String]) -> Bool {
        if needle.count > hay.count { return false }
        for i in 0...(hay.count - needle.count) where Array(hay[i..<(i + needle.count)]) == needle { return true }
        return false
    }

    /// Foods whose name or alias starts with the text, for search boxes.
    public static func search(_ text: String, limit: Int = 30) -> [Food] {
        let q = text.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return Array(FoodDatabase.all.prefix(limit)) }
        var scored: [(Int, Food)] = []
        for food in FoodDatabase.all {
            let names = [food.name.lowercased()] + food.aliases
            var score = Int.max
            for (i, n) in names.enumerated() {
                if n == q { score = min(score, 0) }
                else if n.hasPrefix(q) { score = min(score, 1 + (i == 0 ? 0 : 1)) }
                else if n.contains(" " + q) { score = min(score, 3) }
                else if n.contains(q) { score = min(score, 4) }
            }
            if score < Int.max { scored.append((score, food)) }
        }
        return scored.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.name < $1.1.name }.prefix(limit).map(\.1)
    }
}

/// Reads one ingredient line, as people write them in captions and recipe cards.
public enum IngredientParser {
    public struct Result: Equatable {
        public var name: String
        public var quantity: Quantity?
        public var note: String?
        public var optional: Bool
        public var food: Food?
    }

    static let unitWords: [String: (MeasureUnit, Double)] = [
        "g": (.g, 1), "gr": (.g, 1), "gram": (.g, 1), "grams": (.g, 1), "grammes": (.g, 1), "gms": (.g, 1),
        "kg": (.kg, 1), "kgs": (.kg, 1), "kilo": (.kg, 1), "kilos": (.kg, 1), "kilogram": (.kg, 1), "kilograms": (.kg, 1),
        "mg": (.mg, 1),
        "ml": (.ml, 1), "mls": (.ml, 1), "millilitre": (.ml, 1), "millilitres": (.ml, 1), "milliliter": (.ml, 1), "milliliters": (.ml, 1),
        "l": (.l, 1), "litre": (.l, 1), "litres": (.l, 1), "liter": (.l, 1), "liters": (.l, 1), "ltr": (.l, 1),
        "tsp": (.tsp, 1), "tsps": (.tsp, 1), "teaspoon": (.tsp, 1), "teaspoons": (.tsp, 1), "tspn": (.tsp, 1),
        "tbsp": (.tbsp, 1), "tbsps": (.tbsp, 1), "tablespoon": (.tbsp, 1), "tablespoons": (.tbsp, 1), "tbs": (.tbsp, 1), "tbl": (.tbsp, 1), "tblsp": (.tbsp, 1),
        "cup": (.cup, 1), "cups": (.cup, 1), "c": (.cup, 1),
        "oz": (.oz, 1), "ounce": (.oz, 1), "ounces": (.oz, 1),
        "lb": (.lb, 1), "lbs": (.lb, 1), "pound": (.lb, 1), "pounds": (.lb, 1),
        "floz": (.floz, 1),
        "pinch": (.pinch, 1), "pinches": (.pinch, 1),
        "clove": (.clove, 1), "cloves": (.clove, 1),
        "slice": (.slice, 1), "slices": (.slice, 1), "rasher": (.piece, 1), "rashers": (.piece, 1),
        "can": (.can, 1), "cans": (.can, 1), "tin": (.can, 1), "tins": (.can, 1),
        "pack": (.pack, 1), "packs": (.pack, 1), "packet": (.pack, 1), "packets": (.pack, 1), "bag": (.pack, 1), "bags": (.pack, 1), "pot": (.pack, 1), "tub": (.pack, 1), "jar": (.pack, 1),
        "bunch": (.bunch, 1), "bunches": (.bunch, 1),
        "handful": (.handful, 1), "handfuls": (.handful, 1),
        "scoop": (.piece, 1), "scoops": (.piece, 1),
        "piece": (.piece, 1), "pieces": (.piece, 1), "fillet": (.piece, 1), "fillets": (.piece, 1), "breast": (.piece, 1), "breasts": (.piece, 1),
        "knob": (.g, 10), "splash": (.ml, 10), "drizzle": (.ml, 5), "dash": (.ml, 1), "sprinkle": (.pinch, 1),
        "sprig": (.g, 2), "sprigs": (.g, 2), "stick": (.piece, 1), "sticks": (.piece, 1), "head": (.piece, 1), "heads": (.piece, 1), "bulb": (.piece, 1), "bulbs": (.piece, 1),
        "pouch": (.pack, 1), "pouches": (.pack, 1), "block": (.pack, 1), "ball": (.piece, 1), "balls": (.piece, 1),
    ]

    static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "twelve": 12, "half": 0.5, "quarter": 0.25, "couple": 2, "few": 3, "dozen": 12,
    ]

    static let unicodeFractions: [Character: Double] = [
        "½": 0.5, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "¼": 0.25, "¾": 0.75, "⅕": 0.2, "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875,
    ]

    /// Strips bullets, emoji and list markers from the start of a line.
    public static func clean(_ line: String) -> String {
        var s = String(String.UnicodeScalarView(line.unicodeScalars.filter { $0 != "\u{FE0F}" && $0 != "\u{20E3}" }))
        s = s.replacingOccurrences(of: "\t", with: " ")
        // Leading bullets and symbols (but keep digits and fractions).
        while let first = s.unicodeScalars.first, !(CharacterSet.alphanumerics.contains(first) || unicodeFractions.keys.contains(Character(first)) || first == "(") {
            s.unicodeScalars.removeFirst()
        }
        // Emoji anywhere.
        s = String(s.unicodeScalars.filter { !($0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x2000 && !unicodeFractions.keys.contains(Character($0)))) })
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reads a number at the start of the text: "2", "1.5", "1/2", "1 1/2", "1½", "½", "1-2" (takes the top), "two".
    static func leadingNumber(_ text: Substring) -> (Double, Substring)? {
        var s = text
        func skipSpaces() { while s.first == " " { s.removeFirst() } }
        func readPlain() -> Double? {
            var digits = ""
            while let c = s.first, (c.isASCII && c.isNumber) || c == "." || c == "," {
                if c == "," {
                    // "1,000" style thousands, or "1,5" European decimal.
                    let rest = s.dropFirst()
                    if rest.prefix(3).allSatisfy(\.isNumber), rest.count >= 3, !(rest.dropFirst(3).first?.isNumber ?? false) { s.removeFirst(); continue }
                    if rest.first?.isASCII == true, rest.first?.isNumber == true { digits.append("."); s.removeFirst(); continue }
                    break
                }
                digits.append(c); s.removeFirst()
            }
            if digits.isEmpty { return nil }
            if digits.hasSuffix(".") { digits.removeLast() }
            return Double(digits)
        }
        var value: Double?
        skipSpaces()
        if let f = s.first, let v = unicodeFractions[f] {
            s.removeFirst(); value = v
        } else if let whole = readPlain() {
            value = whole
            if let f = s.first, let v = unicodeFractions[f] { s.removeFirst(); value = whole + v }
            else if s.first == "/" {
                s.removeFirst()
                if let d = readPlain(), d != 0 { value = whole / d }
            } else {
                // "1 1/2" or "1 ½"
                let save = s
                skipSpaces()
                if let f = s.first, let v = unicodeFractions[f] { s.removeFirst(); value = whole + v }
                else if let n = readPlainFraction(&s) { value = whole + n }
                else { s = save }
            }
        } else {
            // Words: "two", "half a", "a couple of".
            let lowered = s.lowercased()
            for (word, v) in numberWords.sorted(by: { $0.key.count > $1.key.count }) {
                if lowered.hasPrefix(word + " ") {
                    s = s.dropFirst(word.count)
                    value = v
                    skipSpaces()
                    // "half a lemon", "a couple of eggs"
                    let l2 = s.lowercased()
                    if word == "half" || word == "quarter" {
                        if l2.hasPrefix("a ") { s = s.dropFirst(2) } else if l2.hasPrefix("an ") { s = s.dropFirst(3) }
                    }
                    if (word == "couple" || word == "few" || word == "a" || word == "dozen"), s.lowercased().hasPrefix("of ") { s = s.dropFirst(3) }
                    if word == "a", s.lowercased().hasPrefix("couple of ") { s = s.dropFirst(10); value = 2 }
                    if word == "a", s.lowercased().hasPrefix("few ") { s = s.dropFirst(4); value = 3 }
                    if word == "a", s.lowercased().hasPrefix("half ") { s = s.dropFirst(5); value = 0.5 }
                    return (value!, s)
                }
            }
            return nil
        }
        // Ranges: "1-2", "1 to 2", "2–3": take the larger.
        let save = s
        skipSpaces()
        if s.first == "-" || s.first == "–" || s.lowercased().hasPrefix("to ") {
            if s.lowercased().hasPrefix("to ") { s = s.dropFirst(3) } else { s.removeFirst() }
            skipSpaces()
            if let (hi, rest) = leadingNumber(s), hi >= (value ?? 0) { s = rest; value = hi } else { s = save }
        } else { s = save }
        return value.map { ($0, s) }
    }

    private static func readPlainFraction(_ s: inout Substring) -> Double? {
        // n/d
        var probe = s
        var num = ""
        while let c = probe.first, c.isASCII, c.isNumber { num.append(c); probe.removeFirst() }
        guard !num.isEmpty, probe.first == "/" else { return nil }
        probe.removeFirst()
        var den = ""
        while let c = probe.first, c.isASCII, c.isNumber { den.append(c); probe.removeFirst() }
        guard let n = Double(num), let d = Double(den), d != 0 else { return nil }
        s = probe
        return n / d
    }

    /// Reads a unit word at the start, allowing it to be stuck to the number ("200g") or followed by a full stop.
    static func leadingUnit(_ text: Substring) -> ((MeasureUnit, Double), Substring)? {
        var s = text
        while s.first == " " { s.removeFirst() }
        let lowered = s.lowercased()
        if lowered.hasPrefix("fl oz") || lowered.hasPrefix("fl. oz") {
            let drop = lowered.hasPrefix("fl oz") ? 5 : 6
            return ((.floz, 1), s.dropFirst(drop))
        }
        var word = ""
        for c in lowered { if c.isLetter { word.append(c) } else { break } }
        guard !word.isEmpty, let u = unitWords[word] else { return nil }
        // A lone "c" or "l" must be followed by a space or end to count ("l" in "lemon" mustn't).
        var rest = s.dropFirst(word.count)
        if rest.first == "." { rest.removeFirst() }
        if let next = rest.first, next.isLetter { return nil }
        if word == "a" { return nil }
        return (u, rest)
    }

    public static func parse(_ raw: String) -> Result? {
        var line = clean(raw)
        if line.isEmpty { return nil }
        var optional = false
        var notes: [String] = []
        let lowered = line.lowercased()
        for marker in ["(optional)", "optional:", ", optional", " - optional", "optional"] where lowered.contains(marker) {
            optional = true
            if let r = line.range(of: marker, options: .caseInsensitive) { line.removeSubrange(r) }
            break
        }
        for marker in ["to taste", "to serve", "for garnish", "to garnish", "for serving", "for topping", "as needed"] {
            if let r = line.range(of: marker, options: .caseInsensitive) {
                notes.append(marker); line.removeSubrange(r)
                if marker != "as needed" { optional = optional || marker != "to taste" }
            }
        }
        // "Ingredient: 200g" or "Ingredient - 200g" → move the quantity to the front.
        line = moveTrailingQuantityToFront(line)

        var rest = Substring(line.trimmingCharacters(in: .whitespaces))
        var quantity: Quantity?
        if let (n, afterNumber) = leadingNumber(rest) {
            var amount = n
            var after = afterNumber
            // "2 x 400g tin chopped tomatoes" / "2x 400g"
            var probe = after
            while probe.first == " " { probe.removeFirst() }
            if probe.first == "x" || probe.first == "×" {
                probe.removeFirst()
                if let (n2, after2) = leadingNumber(probe) {
                    amount *= n2; after = after2
                } else if probe.first == " " { after = probe }
            }
            if let ((unit, mult), afterUnit) = leadingUnit(after) {
                quantity = Quantity(amount * mult, unit)
                after = afterUnit
                // "400g tin of", "2 cans of": drop a container word after the unit.
                var p2 = after
                while p2.first == " " { p2.removeFirst() }
                if let ((u2, _), afterContainer) = leadingUnit(p2), [.can, .pack, .piece].contains(u2), unit.base != .piece {
                    after = afterContainer
                }
            } else {
                quantity = Quantity(amount, .piece)
            }
            rest = after
        } else if let ((unit, mult), afterUnit) = leadingUnit(rest), afterUnit.lowercased().hasPrefix(" of ") {
            // "pinch of salt", "handful of spinach": one of the unit.
            quantity = Quantity(mult, unit)
            rest = afterUnit
        }
        var name = String(rest).trimmingCharacters(in: CharacterSet(charactersIn: " .:-–,"))
        if name.lowercased().hasPrefix("of ") { name = String(name.dropFirst(3)) }
        // Notes: after a comma, in brackets, or after " - ".
        if let r = name.range(of: "(") {
            let inside = name[r.upperBound...].split(separator: ")").first.map(String.init) ?? ""
            if !inside.isEmpty { notes.append(inside.trimmingCharacters(in: .whitespaces)) }
            name = String(name[..<r.lowerBound]) + (name.split(separator: ")", maxSplits: 1).dropFirst().first.map(String.init) ?? "")
        }
        for sep in [", ", " - ", " – ", "; "] {
            if let r = name.range(of: sep) {
                notes.append(String(name[r.upperBound...]).trimmingCharacters(in: .whitespaces))
                name = String(name[..<r.lowerBound])
            }
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " .:-–,*"))
        while name.contains("  ") { name = name.replacingOccurrences(of: "  ", with: " ") }
        if name.isEmpty { return nil }
        let food = FoodMatcher.match(name) ?? notes.lazy.compactMap { FoodMatcher.match($0) }.first
        // "salt and pepper to taste" has no amount: fine. A bare sentence with no food and no amount isn't an ingredient.
        if quantity == nil && food == nil { return nil }
        // "1 bulb of garlic", "2 heads garlic": a whole bulb is about 10 cloves, not 1.
        if let q = quantity, q.unit == .piece, let f = food, UnitStandard.cloveFoods.contains(f.id),
           lowered.range(of: #"\b(bulbs?|heads?)\b"#, options: .regularExpression) != nil {
            quantity = Quantity(q.amount * UnitStandard.clovesPerBulb, .clove)
        }
        let note = notes.filter { !$0.isEmpty }.joined(separator: ", ")
        return Result(name: tidyName(name), quantity: quantity, note: note.isEmpty ? nil : note, optional: optional, food: food)
    }

    static func tidyName(_ name: String) -> String {
        guard let first = name.first else { return name }
        return first.lowercased() + name.dropFirst()
    }

    /// "Chicken breast: 200g" → "200g Chicken breast". "Oats (40g)" → "40g Oats".
    static func moveTrailingQuantityToFront(_ line: String) -> String {
        let pattern = #"^(.*?[A-Za-z].*?)\s*(?:[:\-–]\s*|\(\s*)?((?:\d+(?:[.,/]\d+)?|[½¼¾⅓⅔])\s*(?:x\s*)?(?:g|kg|ml|l|oz|lb|tsp|tbsp|cups?|grams?|tablespoons?|teaspoons?)?)\s*\)?\s*$"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return line }
        let ns = line as NSString
        guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges >= 3 else { return line }
        let name = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        let qty = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
        // Only when the line doesn't already start with a number, and the trailing part has a unit or the name is short.
        if let f = line.first, f.isNumber || unicodeFractions.keys.contains(f) { return line }
        let hasUnit = qty.contains(where: { $0.isLetter })
        if !hasUnit && name.split(separator: " ").count > 4 { return line }
        return "\(qty) \(name)"
    }

    /// Turns a parsed line into a recipe ingredient.
    public static func ingredient(_ raw: String) -> RecipeIngredient? {
        guard let r = parse(raw) else { return nil }
        return RecipeIngredient(name: r.name, foodId: r.food?.id, quantity: r.quantity, note: r.note, optional: r.optional)
    }
}
