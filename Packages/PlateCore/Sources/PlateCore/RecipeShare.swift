import Foundation

/// Sharing a recipe as a link. Plate has no server, so the whole recipe travels inside the link itself, after the
/// "#": that part of an address is never sent to the website, so nobody but the person you send it to sees it.
/// The link opens a small page (docs/r in this repository, served by GitHub Pages) that shows the recipe to anyone
/// and hands it to Plate on a phone that has it. Pasting the link into Plate's import works too, with no internet.
public enum RecipeShare {
    /// Where the page lives.
    public static let page = "https://randomedp.github.io/Plate/r/"
    /// The address the page uses to hand the recipe to the app.
    public static let appLink = "plate://recipe"

    /// The recipe as it travels: short names keep the link short. `l` is the ingredient as a person reads it
    /// ("2 cloves garlic"), which is what the web page shows.
    struct Payload: Codable {
        var v = 1
        var n: String
        var s: String?
        var m: [String]
        var p: Int
        var t: Int?
        var i: [Item]
        var d: [String]
        var g: [String]?
        var k: String?
        var u: String?
        var a: String?
        var x: [Double]?
        var b: Bool?

        struct Item: Codable {
            var l: String
            var n: String
            var f: String?
            var q: Double?
            var u: String?
            var o: String?
            var z: Bool?
        }
    }

    static func payload(_ r: Recipe) -> Payload {
        Payload(
            n: r.name, s: r.summary.isEmpty ? nil : r.summary, m: r.mealTypes.map(\.rawValue), p: r.servings, t: r.minutes,
            i: r.ingredients.map { ing in
                Payload.Item(l: line(ing), n: ing.name, f: ing.foodId, q: ing.quantity?.amount, u: ing.quantity?.unit.rawValue,
                             o: ing.note, z: ing.optional ? true : nil)
            },
            d: r.steps, g: r.tags.isEmpty ? nil : r.tags,
            // A built-in recipe, or one you wrote, arrives as the other person's own.
            k: r.source.kind == .builtIn ? nil : r.source.kind.rawValue, u: r.source.url, a: r.source.author,
            x: r.statedPerServing.map { [$0.kcal, $0.protein, $0.carbs, $0.fat, $0.fibre] },
            b: r.mealPrepFriendly ? true : nil)
    }

    /// "2 cloves garlic, crushed".
    static func line(_ ing: RecipeIngredient) -> String {
        let amount = ing.quantity.map { Format.quantity($0) + " " } ?? ""
        return amount + ing.name + (ing.note.map { ", " + $0 } ?? "")
    }

    /// The recipe packed into text that's safe inside a link.
    public static func code(for recipe: Recipe) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload(recipe)) else { return nil }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The link to send.
    public static func link(for recipe: Recipe) -> URL? {
        code(for: recipe).flatMap { URL(string: page + "#" + $0) }
    }

    /// What goes in the message: the dish's name and the link.
    public static func message(for recipe: Recipe) -> String? {
        link(for: recipe).map { "\(recipe.name)\n\($0.absoluteString)" }
    }

    /// Unpacks a recipe. It arrives as a new recipe of the receiver's own: no rating, photo or favourite.
    public static func recipe(fromCode code: String) -> Recipe? {
        var b64 = code.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), let p = try? JSONDecoder().decode(Payload.self, from: data),
              p.v == 1, !p.n.trimmingCharacters(in: .whitespaces).isEmpty, !p.i.isEmpty else { return nil }
        let ingredients = p.i.map { item -> RecipeIngredient in
            var quantity: Quantity?
            if let q = item.q, let unit = item.u.flatMap(MeasureUnit.init(rawValue:)) { quantity = Quantity(q, unit) }
            // A food this version of Plate doesn't know is matched again by name. One the sender's Plate didn't
            // recognise is left alone.
            let food = item.f.flatMap { FoodDatabase.food($0)?.id ?? FoodMatcher.match(item.n)?.id }
            return RecipeIngredient(name: item.n, foodId: food, quantity: quantity, note: item.o, optional: item.z ?? false)
        }
        let meals = p.m.compactMap(MealType.init(rawValue:))
        var macros: Macros?
        if let x = p.x, x.count >= 4 {
            macros = Macros(kcal: x[0], protein: x[1], carbs: x[2], fat: x[3], fibre: x.count > 4 ? x[4] : 0)
        }
        let kind = p.k.flatMap(RecipeSourceKind.init(rawValue:)) ?? .manual
        return Recipe(name: p.n, summary: p.s ?? "", mealTypes: meals.isEmpty ? [.dinner] : meals, servings: p.p,
                      ingredients: ingredients, steps: p.d, minutes: p.t, tags: p.g ?? [],
                      source: RecipeSource(kind: kind == .builtIn ? .manual : kind, url: p.u, author: p.a),
                      statedPerServing: macros, mealPrepFriendly: p.b ?? false)
    }

    /// The packed recipe in a Plate link, whether it's the web page's address or the app's own. Nil for any other link.
    public static func code(in url: URL) -> String? {
        let text = url.absoluteString
        if text.lowercased().hasPrefix(page.lowercased()) || text.lowercased().hasPrefix(appLink) {
            if let hash = text.firstIndex(of: "#") {
                let code = String(text[text.index(after: hash)...])
                if !code.isEmpty { return code }
            }
            if let d = URLComponents(string: text)?.queryItems?.first(where: { $0.name == "d" })?.value, !d.isEmpty { return d }
        }
        return nil
    }

    public static func recipe(from url: URL) -> Recipe? {
        code(in: url).flatMap(recipe(fromCode:))
    }

    /// Finds a Plate link anywhere in some text (a pasted message, say) and unpacks it.
    public static func recipe(in text: String) -> Recipe? {
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            let w = String(word)
            guard w.lowercased().hasPrefix(page.lowercased()) || w.lowercased().hasPrefix(appLink) else { continue }
            if let url = URL(string: w), let r = recipe(from: url) { return r }
        }
        return nil
    }
}

extension Household {
    /// A recipe you already have that's the same as one arriving: the same post, or the same name and ingredients.
    public func copy(of incoming: Recipe) -> Recipe? {
        func key(_ r: Recipe) -> String {
            ([r.name] + r.ingredients.map(\.name)).joined(separator: "|").lowercased()
        }
        if let url = incoming.source.url, let match = recipes.first(where: { $0.source.url == url }) { return match }
        let k = key(incoming)
        return recipes.first { key($0) == k }
    }
}
