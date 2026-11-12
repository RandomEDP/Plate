import Foundation

/// An event as the calendar tile needs it. The app fills these in from the iPad's calendars (iCloud, shared, Google,
/// Exchange, subscribed: whatever is set up in Settings → Calendar).
public struct CalendarEvent: Hashable, Sendable, Identifiable {
    public var id: String
    public var calendarId: String
    public var title: String
    public var start: Date
    public var end: Date
    public var allDay: Bool
    public var location: String?

    public init(id: String, calendarId: String, title: String, start: Date, end: Date, allDay: Bool = false, location: String? = nil) {
        self.id = id; self.calendarId = calendarId; self.title = title; self.start = start; self.end = end
        self.allDay = allDay; self.location = location
    }
}

/// A calendar tile's settings, kept in the tile's options: which calendars ("cals", empty for all of them) and how
/// many days ahead ("days").
public enum CalendarTileSettings {
    public static let dayChoices = [1, 2, 3, 7, 14, 31]
    public static let defaultDays = 7

    /// The calendars chosen for a tile. Empty means every calendar, including ones added later.
    public static func calendars(_ options: [String: String]) -> Set<String> {
        Set((options["cals"] ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty })
    }

    public static func setCalendars(_ ids: Set<String>, in options: inout [String: String]) {
        options["cals"] = ids.isEmpty ? nil : ids.sorted().joined(separator: "\n")
    }

    /// Ticks or unticks one calendar. Unticking from "every calendar" leaves all the others ticked.
    public static func toggle(_ id: String, all: [String], in options: inout [String: String]) {
        var chosen = calendars(options)
        if chosen.isEmpty { chosen = Set(all) }
        if chosen.contains(id) {
            // Keep at least one ticked: a tile showing no calendars would just look broken.
            guard chosen.count > 1 else { return }
            chosen.remove(id)
        } else {
            chosen.insert(id)
        }
        // Everything ticked is the same as "every calendar", which also picks up calendars added later.
        if !all.isEmpty, Set(all).isSubset(of: chosen) { chosen = [] }
        setCalendars(chosen, in: &options)
    }

    public static func shows(_ calendarId: String, options: [String: String]) -> Bool {
        let chosen = calendars(options)
        return chosen.isEmpty || chosen.contains(calendarId)
    }

    public static func days(_ options: [String: String]) -> Int {
        min(31, max(1, Int(options["days"] ?? "") ?? defaultDays))
    }

    /// The events a tile shows: from the chosen calendars, not yet over, starting before the end of the last day
    /// asked for, soonest first (all-day events first on their day).
    public static func events(_ all: [CalendarEvent], options: [String: String], now: Date, calendar: Calendar) -> [CalendarEvent] {
        let today = calendar.startOfDay(for: now)
        let until = calendar.date(byAdding: .day, value: days(options), to: today) ?? now
        return all.filter { e in
            shows(e.calendarId, options: options) && e.end > now && e.start < until
        }
        .sorted { a, b in
            let da = calendar.startOfDay(for: max(a.start, today)), db = calendar.startOfDay(for: max(b.start, today))
            if da != db { return da < db }
            if a.allDay != b.allDay { return a.allDay }
            return a.start == b.start ? a.title < b.title : a.start < b.start
        }
    }

    /// "Today", "Tomorrow", "Friday" (this week) or "Mon 24 Nov".
    public static func dayHeading(_ date: Date, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: max(date, today))
        let diff = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        if diff == 0 { return "Today" }
        if diff == 1 { return "Tomorrow" }
        let full = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let short = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let c = calendar.dateComponents([.weekday, .day, .month], from: day)
        let w = ((c.weekday ?? 1) - 1 + 7) % 7
        if diff < 7 { return full[w] }
        return "\(short[w]) \(c.day ?? 1) \(months[((c.month ?? 1) - 1 + 12) % 12])"
    }
}
