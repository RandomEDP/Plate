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
    /// The event's notes, shown when it's tapped open.
    public var notes: String?

    public init(id: String, calendarId: String, title: String, start: Date, end: Date, allDay: Bool = false, location: String? = nil,
                notes: String? = nil) {
        self.id = id; self.calendarId = calendarId; self.title = title; self.start = start; self.end = end
        self.allDay = allDay; self.location = location; self.notes = notes
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

// MARK: Reminders

/// A reminder as the calendar tile needs it, from a Reminders list (shared ones included). The app fills these in.
public struct ReminderItem: Hashable, Sendable, Identifiable {
    public var id: String
    public var listId: String
    public var title: String
    /// When it's due, if it says. `dueHasTime` is false for a reminder due on a day but at no particular time.
    public var due: Date?
    public var dueHasTime: Bool
    public var notes: String?
    /// 0 is none; 1 is high, 5 medium, 9 low (Apple's numbers).
    public var priority: Int

    public init(id: String, listId: String, title: String, due: Date? = nil, dueHasTime: Bool = false, notes: String? = nil,
                priority: Int = 0) {
        self.id = id; self.listId = listId; self.title = title; self.due = due; self.dueHasTime = dueHasTime
        self.notes = notes; self.priority = priority
    }

    /// Due before now (or, with no time, before today).
    public func isOverdue(now: Date, calendar: Calendar) -> Bool {
        guard let due else { return false }
        return dueHasTime ? due < now : calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    }

    /// High first, then medium, low and none.
    var rank: Int { priority == 0 ? 10 : priority }
}

/// One line on the calendar tile: an event or a reminder.
public enum AgendaItem: Hashable, Sendable, Identifiable {
    case event(CalendarEvent)
    case reminder(ReminderItem)

    public var id: String {
        switch self {
        case .event(let e): return "e-" + e.id
        case .reminder(let r): return "r-" + r.id
        }
    }

    /// The day it's listed under: today for anything overdue or already started.
    public func day(now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .event(let e): return calendar.startOfDay(for: max(e.start, today))
        case .reminder(let r): return calendar.startOfDay(for: max(r.due ?? today, today))
        }
    }
}

extension CalendarTileSettings {
    /// The Reminders lists a tile shows ("rlists"). Unlike calendars, none chosen means no reminders.
    public static func reminderLists(_ options: [String: String]) -> Set<String> {
        Set((options["rlists"] ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty })
    }

    public static func toggleReminderList(_ id: String, in options: inout [String: String]) {
        var chosen = reminderLists(options)
        if chosen.contains(id) { chosen.remove(id) } else { chosen.insert(id) }
        options["rlists"] = chosen.isEmpty ? nil : chosen.sorted().joined(separator: "\n")
    }

    /// Whether reminders with no due date are listed too, under "To do" ("undated", on unless turned off).
    public static func showsUndated(_ options: [String: String]) -> Bool { options["undated"] != "0" }

    /// Events and dated reminders together, day by day. On each day: all-day events, then reminders due that day (or
    /// overdue) with no time, then everything with a time, in time order.
    public static func agenda(events all: [CalendarEvent], reminders: [ReminderItem], options: [String: String], now: Date,
                              calendar: Calendar) -> [AgendaItem] {
        let today = calendar.startOfDay(for: now)
        let until = calendar.date(byAdding: .day, value: days(options), to: today) ?? now
        let lists = reminderLists(options)
        let dated = reminders.filter { r in
            guard let due = r.due, lists.contains(r.listId) else { return false }
            return due < until
        }
        let items = events(all, options: options, now: now, calendar: calendar).map(AgendaItem.event) + dated.map(AgendaItem.reminder)
        func order(_ i: AgendaItem) -> (Int, Date, Int, String) {
            switch i {
            case .event(let e):
                return e.allDay ? (0, today, 0, e.title) : (2, max(e.start, now), 0, e.title)
            case .reminder(let r):
                // A timed reminder that's overdue sits with the untimed ones at the top of today.
                if !r.dueHasTime || r.isOverdue(now: now, calendar: calendar) { return (1, r.due ?? today, r.rank, r.title) }
                return (2, r.due ?? today, r.rank, r.title)
            }
        }
        return items.sorted { a, b in
            let da = a.day(now: now, calendar: calendar), db = b.day(now: now, calendar: calendar)
            if da != db { return da < db }
            let oa = order(a), ob = order(b)
            if oa.0 != ob.0 { return oa.0 < ob.0 }
            if oa.1 != ob.1 { return oa.1 < ob.1 }
            if oa.2 != ob.2 { return oa.2 < ob.2 }
            return oa.3 < ob.3
        }
    }

    /// Reminders from the chosen lists with no due date, most important first.
    public static func undated(_ reminders: [ReminderItem], options: [String: String]) -> [ReminderItem] {
        guard showsUndated(options) else { return [] }
        let lists = reminderLists(options)
        return reminders.filter { $0.due == nil && lists.contains($0.listId) }
            .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

// MARK: Today's list

/// How often a reminder added from the dashboard comes round again. The app turns this into a Reminders repeat, so a
/// repeating reminder ticked off today comes back on its next day by itself.
public enum ReminderRepeat: String, CaseIterable, Hashable, Sendable, Identifiable {
    case never, daily, weekdays, weekly, fortnightly, monthly

    public var id: String { rawValue }

    /// "Every Thursday" for weekly ones, given the day it starts on.
    public func title(startingOn day: Date, calendar: Calendar) -> String {
        switch self {
        case .never: return "Just once"
        case .daily: return "Every day"
        case .weekdays: return "Every weekday"
        case .weekly: return "Every \(DayText.weekday(day, calendar: calendar))"
        case .fortnightly: return "Every other \(DayText.weekday(day, calendar: calendar))"
        case .monthly: return "Every month"
        }
    }
}

extension CalendarTileSettings {
    /// What's on today's list: reminders from the chosen lists due today or overdue, then (unless turned off) ones with
    /// no date. Overdue first, then anything due at no particular time, then timed ones in time order.
    public static func dueToday(_ reminders: [ReminderItem], options: [String: String], now: Date, calendar: Calendar) -> [ReminderItem] {
        let lists = reminderLists(options)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let dated = reminders.filter { r in
            guard let due = r.due, lists.contains(r.listId) else { return false }
            return due < tomorrow
        }
        .sorted { a, b in
            func key(_ r: ReminderItem) -> (Int, Date, Int, String) {
                let late = r.isOverdue(now: now, calendar: calendar)
                return (late ? 0 : r.dueHasTime ? 2 : 1, r.due ?? now, r.rank, r.title.lowercased())
            }
            return key(a) < key(b)
        }
        return dated + undated(reminders, options: options)
    }
}
