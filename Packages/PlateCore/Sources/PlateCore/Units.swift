import Foundation

/// Converting between what a recipe says ("2 tbsp", "1 tin", "3 cloves") and how the kitchen keeps things.
public enum Units {
    /// Grams for one piece when a food doesn't say (a slice of cheese, a scoop).
    static let fallbackPieceGrams = 20.0

    /// The quantity in the unit the food is kept in (grams, ml or pieces). Nil when it can't be worked out.
    public static func amount(_ q: Quantity, in target: BaseUnit, food: Food?) -> Double? {
        if let food {
            switch q.unit {
            case .can:
                if let size = food.canSize { return convert(q.amount * size, from: food.unit, to: target, food: food) }
            case .pack:
                if let size = food.packs.map(\.size).min() { return convert(q.amount * size, from: food.unit, to: target, food: food) }
            case .bunch:
                if food.gramsPerPiece != nil { return convert(q.amount, from: .piece, to: target, food: food) }
            default: break
            }
        }
        return convert(q.amount * q.unit.factor, from: q.unit.base, to: target, food: food)
    }

    /// The quantity in the food's own unit.
    public static func amountInFoodUnit(_ q: Quantity, food: Food) -> Double? { amount(q, in: food.unit, food: food) }

    public static func grams(_ q: Quantity, food: Food?) -> Double? { amount(q, in: .g, food: food) }

    public static func convert(_ value: Double, from: BaseUnit, to: BaseUnit, food: Food?) -> Double? {
        if from == to { return value }
        let density = food?.gramsPerMl ?? 1
        let piece = food?.gramsPerPiece
        // Everything goes through grams.
        let g: Double
        switch from {
        case .g: g = value
        case .ml: g = value * density
        case .piece:
            guard let pg = piece ?? (food == nil ? nil : fallbackPieceGrams) else { return nil }
            g = value * pg
        }
        switch to {
        case .g: return g
        case .ml: return g / density
        case .piece:
            guard let pg = piece, pg > 0 else { return nil }
            return g / pg
        }
    }

    /// Converts an amount kept in one base unit into grams (for macros).
    public static func grams(_ value: Double, _ unit: BaseUnit, food: Food?) -> Double? {
        convert(value, from: unit, to: .g, food: food)
    }
}

public enum Format {
    /// "250 g", "1.5 kg", "500 ml", "2 l", "3" (pieces).
    public static func amount(_ value: Double, _ unit: BaseUnit) -> String {
        switch unit {
        case .g:
            return value >= 1000 ? "\(number(value / 1000, places: 2, fractions: false)) kg" : "\(number(value, places: value < 10 ? 1 : 0, fractions: false)) g"
        case .ml:
            return value >= 1000 ? "\(number(value / 1000, places: 2, fractions: false)) l" : "\(number(value, places: value < 10 ? 1 : 0, fractions: false)) ml"
        case .piece:
            return number(value, places: value < 3 ? 2 : 1)
        }
    }

    /// An amount with the food's name, e.g. "3 eggs", "250 g chicken breast", "½ lemon".
    public static func amountWithName(_ value: Double, _ unit: BaseUnit, name: String) -> String {
        if unit == .piece {
            let n = number(value, places: value < 3 ? 2 : 1)
            return "\(n) × \(name)"
        }
        return "\(amount(value, unit)) \(name)"
    }

    public static func quantity(_ q: Quantity) -> String {
        let n = number(q.amount, places: 2)
        switch q.unit {
        case .piece: return n
        case .g, .kg, .mg, .ml, .l: return "\(n)\(q.unit.label)"
        default:
            let plural = q.amount > 1 && ![.oz, .lb, .tsp, .tbsp, .floz].contains(q.unit)
            return "\(n) \(q.unit.label)\(plural ? (q.unit == .bunch || q.unit == .pinch ? "es" : "s") : "")"
        }
    }

    public static func number(_ v: Double, places: Int, fractions useFractions: Bool = true) -> String {
        let fractions: [(Double, String)] = [(0.25, "¼"), (0.5, "½"), (0.75, "¾"), (1.0 / 3, "⅓"), (2.0 / 3, "⅔")]
        let whole = v.rounded(.down)
        let frac = v - whole
        if useFractions, v > 0, v < 10 {
            for (f, s) in fractions where abs(frac - f) < 0.02 {
                return whole == 0 ? s : "\(Int(whole))\(s)"
            }
        }
        var mult = 1.0
        for _ in 0..<places { mult *= 10 }
        let r = (v * mult).rounded() / mult
        if r == r.rounded() { return String(Int(r)) }
        var s = String(format: "%.\(places)f", r)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    public static func money(_ v: Double) -> String { String(format: "£%.2f", v) }

    public static func macros(_ m: Macros) -> String {
        "\(Int(m.kcal.rounded())) kcal · \(Int(m.protein.rounded()))g protein · \(Int(m.carbs.rounded()))g carbs · \(Int(m.fat.rounded()))g fat"
    }
}
