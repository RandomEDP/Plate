import PlateCore
import SwiftUI

extension Color {
    static let protein = Color(red: 0.86, green: 0.33, blue: 0.29)
    static let carbs = Color(red: 0.95, green: 0.65, blue: 0.20)
    static let fat = Color(red: 0.36, green: 0.55, blue: 0.86)
}

/// "Use today", "2 days", "Expired" for an expiry date, with a colour.
struct ExpiryBadge: View {
    let date: Date?
    var body: some View {
        if let date, let (text, color) = Self.describe(date) {
            Text(text)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(color.opacity(0.15), in: Capsule())
                .foregroundStyle(color)
        }
    }

    static func describe(_ date: Date, now: Date = Date()) -> (String, Color)? {
        let cal = Calendar.plate
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<0: return ("Out of date", .red)
        case 0: return ("Use today", .red)
        case 1: return ("Use tomorrow", .orange)
        case 2...3: return ("\(days) days", .orange)
        case 4...14: return ("\(days) days", .secondary)
        default: return nil
        }
    }
}

struct MacroLine: View {
    let macros: Macros
    var body: some View {
        HStack(spacing: 10) {
            Text("\(Int(macros.kcal.rounded())) kcal").fontWeight(.semibold)
            dot(.protein, "\(Int(macros.protein.rounded()))g P")
            dot(.carbs, "\(Int(macros.carbs.rounded()))g C")
            dot(.fat, "\(Int(macros.fat.rounded()))g F")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    func dot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 3) { Circle().fill(c).frame(width: 6, height: 6); Text(t) }
    }
}

/// A progress bar for one macro against its target.
struct MacroBar: View {
    let title: String
    let value: Double
    let target: Double
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                Text("\(Int(value.rounded())) / \(Int(target.rounded()))\(unit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule().fill(color)
                        .frame(width: geo.size.width * min(1, target > 0 ? value / target : 0))
                }
            }
            .frame(height: 8)
        }
    }
}

struct CalorieRing: View {
    let value: Double
    let target: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.accentColor.opacity(0.15), lineWidth: 12)
            Circle()
                .trim(from: 0, to: min(1, target > 0 ? value / target : 0))
                .stroke(value > target * 1.05 ? Color.orange : Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(max(0, target - value).rounded()))")
                    .font(.title2.weight(.bold).monospacedDigit())
                Text(value > target ? "over" : "kcal left").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 110, height: 110)
    }
}

/// How ready you are to cook something: "Ready" or "Need 2".
struct MatchBadge: View {
    let match: RecipeMatch
    var body: some View {
        if match.canCookNow {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        } else {
            Text("Need \(match.missingCount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(match.missingCount <= 2 ? .orange : .secondary)
        }
    }
}

struct RecipeRow: View {
    let recipe: Recipe
    var match: RecipeMatch?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RecipeThumb(recipe: recipe)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(recipe.name).font(.body.weight(.medium)).lineLimit(2)
                    if recipe.isFavourite { Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink) }
                }
                MacroLine(macros: Nutrition.perServing(recipe))
                HStack(spacing: 8) {
                    if let match { MatchBadge(match: match) }
                    if let m = recipe.minutes { Label("\(m) min", systemImage: "clock").font(.caption).foregroundStyle(.secondary) }
                    if let stars = recipe.rating {
                        Label("\(stars)", systemImage: "star.fill").font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel("Rated \(stars) out of 5")
                    }
                    SourceIcon(source: recipe.source)
                    if recipe.guessedCount > 0 || recipe.servingsGuessed == true {
                        Label("Check amounts", systemImage: "questionmark.circle").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct SourceIcon: View {
    let source: RecipeSource
    var body: some View {
        switch source.kind {
        case .instagram: Label("Instagram", systemImage: "camera").font(.caption).foregroundStyle(.secondary)
        case .tiktok: Label("TikTok", systemImage: "music.note").font(.caption).foregroundStyle(.secondary)
        case .ai: Label("Idea", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
        case .variation: Label("Variation", systemImage: "arrow.triangle.branch").font(.caption).foregroundStyle(.secondary)
        default: EmptyView()
        }
    }
}

/// A coloured tile with an emoji for the recipe's main ingredient, so lists are easy to scan.
struct RecipeThumb: View {
    let recipe: Recipe
    var size: CGFloat = 46

    var body: some View {
        if let photo = recipe.photo, DishPhotos.image(photo, side: size) != nil {
            // The dish's own picture, when it has one.
            DishPhotoView(photo: photo, side: size)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.26))
                .accessibilityHidden(true)
        } else {
            let (emoji, color) = Self.look(recipe)
            Text(emoji)
                .font(.system(size: size * 0.5))
                .frame(width: size, height: size)
                .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: size * 0.26))
        }
    }

    static func look(_ r: Recipe) -> (String, Color) {
        let ids = r.ingredients.compactMap(\.foodId)
        let name = r.name.lowercased()
        let table: [(String, String, Color)] = [
            ("salmon", "🐟", .pink), ("cod", "🐟", .blue), ("prawns", "🍤", .orange), ("tuna", "🐟", .blue),
            ("steak", "🥩", .red), ("beef-mince", "🍝", .red), ("lamb-mince", "🥧", .brown), ("sausages", "🌭", .brown),
            ("bacon", "🥓", .red), ("chicken-breast", "🍗", .orange), ("chicken-thigh", "🍗", .orange),
            ("turkey-mince", "🍔", .orange), ("tofu", "🥢", .green), ("chickpeas", "🫘", .yellow),
            ("red-lentils", "🥣", .orange), ("eggs", "🍳", .yellow), ("oats", "🥣", .brown), ("greek-yoghurt", "🥛", .blue),
            ("banana", "🍌", .yellow), ("apple", "🍎", .red), ("potatoes", "🥔", .brown), ("pasta", "🍝", .orange),
        ]
        if name.contains("curry") { return ("🍛", .orange) }
        if name.contains("soup") { return ("🍲", .orange) }
        if name.contains("salad") { return ("🥗", .green) }
        if name.contains("wrap") || name.contains("burrito") || name.contains("fajita") { return ("🌯", .orange) }
        if name.contains("pancake") { return ("🥞", .brown) }
        if name.contains("burger") { return ("🍔", .orange) }
        if name.contains("pie") { return ("🥧", .brown) }
        if name.contains("noodle") || name.contains("stir") { return ("🍜", .orange) }
        if name.contains("rice") { return ("🍚", .gray) }
        for (id, e, c) in table where ids.contains(id) { return (e, c) }
        return ("🍽️", .accentColor)
    }
}

extension View {
    /// Rounded card background used across the app.
    func card() -> some View {
        self.padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

extension BaseUnit {
    var pickerTitle: String {
        switch self { case .g: return "grams"; case .ml: return "ml"; case .piece: return "items" }
    }
}

extension InventoryItem {
    var amountText: String {
        unit == .piece ? "\(Format.number(amount, places: 1))" : Format.amount(amount, unit)
    }
}
