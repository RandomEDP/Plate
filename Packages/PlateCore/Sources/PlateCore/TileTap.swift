import Foundation

// What tapping a dashboard tile does when the tile isn't a button itself: open a bigger view with more detail, or go
// to the part of Plate it comes from. Tiles that are buttons (lights, scenes, music, routines…) keep their own tap,
// and a long press still gives their extra controls.

/// A part of Plate's own app, for tiles about food.
public enum PlateSection: String, Hashable, Sendable {
    case today, kitchen, recipes, plan, shop
}

public enum TileTap: Hashable, Sendable {
    /// Nothing more to show, or the tile handles its own taps.
    case none
    /// A sheet with more detail about the tile.
    case details
    /// Go to that part of Plate (leaving wall mode if it's on).
    case open(PlateSection)

    public static func action(for kind: TileKind) -> TileTap {
        switch kind {
        case .weather, .forecast, .sun, .calendar, .nowPlaying, .climate, .battery, .bins, .wifi, .activity, .checklist:
            return .details
        case .todaysMeals: return .open(.plan)
        case .shoppingList: return .open(.shop)
        case .useSoon: return .open(.kitchen)
        case .macros: return .open(.today)
        case .cookNow: return .open(.recipes)
        default: return .none
        }
    }
}

extension WeatherText {
    /// Where a day's low and high sit on a bar running from the week's coldest to its warmest, as fractions 0 to 1, so
    /// the days can be compared at a glance.
    public static func span(low: Double, high: Double, weekLow: Double, weekHigh: Double) -> (start: Double, end: Double) {
        let width = weekHigh - weekLow
        guard width > 0.01 else { return (0, 1) }
        func at(_ t: Double) -> Double { min(1, max(0, (t - weekLow) / width)) }
        let a = at(min(low, high)), b = at(max(low, high))
        // Always wide enough to see.
        return b - a < 0.04 ? (max(0, min(a, 0.96)), max(0, min(a, 0.96)) + 0.04) : (a, b)
    }

    /// The next `count` hours from the start of this one.
    public static func nextHours(_ hours: [HourForecast], now: Date, count: Int = 24, calendar: Calendar = .plate) -> [HourForecast] {
        let thisHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return Array(hours.filter { $0.date >= thisHour }.sorted { $0.date < $1.date }.prefix(count))
    }
}

extension Recurring {
    /// The next few days it happens, today included: for the bin days view.
    public func upcoming(_ count: Int, from date: Date, calendar: Calendar = .plate) -> [Date] {
        var out: [Date] = []
        var from = date
        while out.count < count {
            let n = next(onOrAfter: from, calendar: calendar)
            if let last = out.last, n <= last { break }
            out.append(n)
            from = calendar.date(byAdding: .day, value: 1, to: n) ?? n.addingTimeInterval(86_400)
        }
        return out
    }
}
