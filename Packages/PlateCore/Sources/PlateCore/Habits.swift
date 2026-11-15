import Foundation

// How the things on today's list are going: read from what's been ticked off in Reminders (on the iPad or anyone's
// phone), so nothing extra is stored in Plate.

/// One reminder ticked off.
public struct ReminderDone: Hashable, Sendable {
    public var title: String
    public var listId: String
    public var completed: Date
    public init(title: String, listId: String, completed: Date) {
        self.title = title; self.listId = listId; self.completed = completed
    }
}

public struct HabitStats: Hashable, Sendable, Identifiable {
    public var title: String
    /// Days it was done in the last seven, today included.
    public var lastSeven: Int
    /// Days it was done in the last thirty.
    public var lastThirty: Int
    /// Days in a row up to today (or up to yesterday, if today's not done yet).
    public var streak: Int
    public var lastDone: Date?
    public var doneToday: Bool
    public var id: String { title.lowercased() }
}

public enum Habits {
    /// A key that treats "Drink a protein shake" and "drink a protein shake " as the same thing.
    public static func key(_ title: String) -> String {
        title.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Stats for everything ticked off from the chosen lists in the last 30 days, most often done first.
    public static func stats(_ done: [ReminderDone], options: [String: String], now: Date, calendar: Calendar) -> [HabitStats] {
        let lists = CalendarTileSettings.reminderLists(options)
        let today = calendar.startOfDay(for: now)
        guard let monthAgo = calendar.date(byAdding: .day, value: -29, to: today),
              let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) else { return [] }
        let recent = done.filter { lists.contains($0.listId) && $0.completed >= monthAgo && $0.completed <= now }
        let groups = Dictionary(grouping: recent) { key($0.title) }
        return groups.values.compactMap { items -> HabitStats? in
            guard let newest = items.max(by: { $0.completed < $1.completed }) else { return nil }
            let days = Set(items.map { calendar.startOfDay(for: $0.completed) })
            return HabitStats(title: newest.title.trimmingCharacters(in: .whitespaces),
                              lastSeven: days.filter { $0 >= weekAgo }.count, lastThirty: days.count,
                              streak: streak(days, today: today, calendar: calendar), lastDone: newest.completed,
                              doneToday: days.contains(today))
        }
        .sorted { ($0.lastThirty, $1.title.lowercased()) > ($1.lastThirty, $0.title.lowercased()) }
    }

    /// Days in a row ending today, or ending yesterday when today isn't done yet (so a streak doesn't vanish at dawn).
    public static func streak(_ days: Set<Date>, today: Date, calendar: Calendar) -> Int {
        var day = days.contains(today) ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var count = 0
        while days.contains(day) {
            count += 1
            guard let before = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = before
        }
        return count
    }

    /// "Done 5 of the last 7 days · 3 days in a row" for things done most days; "Last done Thursday" for the rest.
    public static func summary(_ s: HabitStats, now: Date, calendar: Calendar) -> String {
        if s.lastSeven >= 2 {
            var text = "Done \(s.lastSeven) of the last 7 days"
            if s.streak >= 2 { text += " · \(s.streak) days in a row" }
            return text
        }
        guard let last = s.lastDone else { return "Not done yet" }
        let when = DayText.relative(last, now: now, calendar: calendar)
        return "Last done " + (when == "Today" || when == "Yesterday" ? when.lowercased() : when)
            + (s.lastThirty > 1 ? " · \(s.lastThirty) times this month" : "")
    }

    /// The streak to show beside an item on today's list, if it's worth showing (2 days or more).
    public static func streak(for title: String, in stats: [HabitStats]) -> Int? {
        let k = key(title)
        guard let s = stats.first(where: { $0.id == k || key($0.title) == k }), s.streak >= 2 else { return nil }
        return s.streak
    }
}
