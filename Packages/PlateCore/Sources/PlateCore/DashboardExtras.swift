import Foundation

// The parts of the dashboard beyond tiles on a grid: pages, timers, chores, bin days, routines and their schedules,
// the activity list, and the small bits of wording (greetings, countdowns, clock in words) that go with them.

// MARK: - Pages

public struct DashboardPage: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var icon: String
    public init(id: UUID = UUID(), name: String, icon: String = "square.grid.2x2") { self.id = id; self.name = name; self.icon = icon }

    enum CodingKeys: String, CodingKey { case id, name, icon }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "Page")
        icon = c.value(.icon, default: "square.grid.2x2")
    }
}

extension HomeDashboard {
    /// The pages to show: the saved ones, or a single "Home" page when none have been made.
    public var pageList: [DashboardPage] {
        pages.isEmpty ? [DashboardPage(id: HomeDashboard.firstPageId, name: "Home", icon: "house")] : pages
    }

    /// A fixed id for the page that exists before any are made, so views can keep their place.
    public static let firstPageId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// The drawable tiles on a page. Tiles with no page, or whose page was deleted, belong to the first page.
    public func tiles(onPage id: UUID) -> [DashboardTile] {
        let list = pageList
        let known = Set(list.map(\.id))
        let isFirst = list.first?.id == id
        let folders = folderIds
        return visibleTiles.filter { t in
            // Tiles kept in a folder are shown inside it, not on the page.
            if let f = t.folderId, folders.contains(f) { return false }
            if let p = t.pageId, known.contains(p) { return p == id }
            return isFirst
        }
    }

    private var folderIds: Set<UUID> { Set(tiles.filter { $0.kind == .folder }.map(\.id)) }

    /// The folder tiles, for the "Move into folder" menu.
    public var folders: [DashboardTile] { tiles.filter { $0.kind == .folder } }

    /// What's inside a folder, in order.
    public func tiles(inFolder id: UUID) -> [DashboardTile] {
        visibleTiles.filter { $0.folderId == id }
    }

    /// Puts a tile in a folder, or takes it out (nil), when it goes back on the folder's page.
    /// A folder can't go inside a folder.
    public mutating func moveTile(_ id: UUID, toFolder folder: UUID?) {
        guard let i = tiles.firstIndex(where: { $0.id == id }), tiles[i].kind != .folder, id != folder else { return }
        if let folder {
            guard let f = tiles.first(where: { $0.id == folder && $0.kind == .folder }) else { return }
            tiles[i].folderId = folder
            tiles[i].pageId = f.pageId
            tiles[i].row = nil; tiles[i].column = nil
        } else {
            if let old = tiles[i].folderId, let f = tiles.first(where: { $0.id == old }) { tiles[i].pageId = f.pageId }
            tiles[i].folderId = nil
            // Out of the folder, it goes in the first gap on the page.
            tiles[i].row = nil; tiles[i].column = nil
        }
        tiles[i].updatedAt = Date()
        updatedAt = Date()
    }

    /// Adds a page and returns its id. The first time, the existing tiles become the "Home" page.
    @discardableResult
    public mutating func addPage(named name: String, icon: String = "square.grid.2x2") -> UUID {
        if pages.isEmpty { pages = [DashboardPage(id: HomeDashboard.firstPageId, name: "Home", icon: "house")] }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let page = DashboardPage(name: trimmed.isEmpty ? "Page \(pages.count + 1)" : trimmed, icon: icon)
        pages.append(page)
        updatedAt = Date()
        return page.id
    }

    /// Removes a page. Its tiles move to the first page rather than being lost. The last page can't be removed.
    public mutating func removePage(_ id: UUID) {
        guard pages.count > 1, let i = pages.firstIndex(where: { $0.id == id }) else { return }
        pages.remove(at: i)
        let first = pages[0].id
        for j in tiles.indices where tiles[j].pageId == id { tiles[j].pageId = first }
        if pages.count == 1 {
            // Back to a single page: drop the page list so it behaves like a fresh dashboard.
            for j in tiles.indices { tiles[j].pageId = nil }
            pages = []
        }
        updatedAt = Date()
    }

    public mutating func moveTile(_ id: UUID, toPage page: UUID) {
        guard let i = tiles.firstIndex(where: { $0.id == id }) else { return }
        tiles[i].pageId = page
        tiles[i].folderId = nil
        // It goes in the first gap on its new page.
        tiles[i].row = nil; tiles[i].column = nil
        // A folder takes its contents with it.
        if tiles[i].kind == .folder { for j in tiles.indices where tiles[j].folderId == id { tiles[j].pageId = page } }
        tiles[i].updatedAt = Date()
        updatedAt = Date()
    }

    public mutating func update(_ tile: DashboardTile) {
        guard let i = tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        var t = tile
        t.updatedAt = Date()
        tiles[i] = t
        updatedAt = Date()
    }

    /// Adds to the activity list, newest first, keeping the last 40.
    public mutating func log(_ text: String, icon: String = "bolt.fill", at date: Date = Date()) {
        activity.insert(ActivityEntry(date: date, text: text, icon: icon), at: 0)
        if activity.count > 40 { activity.removeLast(activity.count - 40) }
    }
}

public struct ActivityEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var text: String
    public var icon: String
    public init(id: UUID = UUID(), date: Date, text: String, icon: String) { self.id = id; self.date = date; self.text = text; self.icon = icon }

    enum CodingKeys: String, CodingKey { case id, date, text, icon }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        date = c.value(.date, default: Date())
        text = c.value(.text, default: "")
        icon = c.value(.icon, default: "bolt.fill")
    }
}

// MARK: - Timers

public struct DashTimer: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var label: String
    /// The full length in seconds.
    public var duration: Double
    /// When it finishes, while running.
    public var endsAt: Date?
    /// Seconds left, while paused.
    public var pausedRemaining: Double?
    /// A routine to run when it finishes (say, lights off after a sleep timer).
    public var routineId: UUID?
    /// Set once the finished sound has played, so it only plays once.
    public var announced: Bool

    public init(id: UUID = UUID(), label: String, duration: Double, startingAt now: Date = Date(), routineId: UUID? = nil) {
        self.id = id; self.label = label; self.duration = duration; self.endsAt = now.addingTimeInterval(duration)
        self.pausedRemaining = nil; self.routineId = routineId; self.announced = false
    }

    enum CodingKeys: String, CodingKey { case id, label, duration, endsAt, pausedRemaining, routineId, announced }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        label = c.value(.label, default: "Timer")
        duration = c.value(.duration, default: 0)
        endsAt = c.optional(.endsAt)
        pausedRemaining = c.optional(.pausedRemaining)
        routineId = c.optional(.routineId)
        announced = c.value(.announced, default: false)
    }

    public var isPaused: Bool { pausedRemaining != nil }

    public func remaining(now: Date) -> Double {
        if let pausedRemaining { return max(0, pausedRemaining) }
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(now))
    }

    public func isFinished(now: Date) -> Bool { !isPaused && remaining(now: now) <= 0 }

    /// How far through it is, 0 to 1.
    public func progress(now: Date) -> Double {
        duration > 0 ? min(1, max(0, 1 - remaining(now: now) / duration)) : 1
    }

    public mutating func pause(now: Date) {
        guard !isPaused, !isFinished(now: now) else { return }
        pausedRemaining = remaining(now: now)
        endsAt = nil
    }

    public mutating func resume(now: Date) {
        guard let left = pausedRemaining else { return }
        endsAt = now.addingTimeInterval(left)
        pausedRemaining = nil
    }

    public mutating func add(_ seconds: Double, now: Date) {
        duration += seconds
        if let left = pausedRemaining { pausedRemaining = left + seconds }
        else { endsAt = (isFinished(now: now) ? now : (endsAt ?? now)).addingTimeInterval(seconds); announced = false }
    }

    /// "9:05", or "1:02:03" for an hour or more. Rounds up, so a timer shows 0:01 until it really finishes.
    public static func text(_ seconds: Double) -> String {
        let s = Int(max(0, seconds).rounded(.up))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        func two(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }
        return h > 0 ? "\(h):\(two(m)):\(two(sec))" : "\(m):\(two(sec))"
    }

    /// "10 min", "1 hr 30 min", "45 sec": for buttons and for saying out loud.
    public static func words(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hr") }
        if m > 0 { parts.append("\(m) min") }
        if sec > 0 && h == 0 { parts.append("\(sec) sec") }
        return parts.isEmpty ? "0 sec" : parts.joined(separator: " ")
    }
}

public enum TimerParser {
    /// Reads "pasta 10", "10 min", "1h30", "90s", "eggs 6m30s", "1:30" (a bare number is minutes).
    /// Returns nil when there's no time in it.
    public static func parse(_ text: String) -> (label: String, seconds: Double)? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return nil }
        var words = lower.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        let filler: Set<String> = ["timer", "for", "set", "a", "an", "start", "the", "and"]
        var seconds = 0.0
        var found = false
        var labelWords: [String] = []
        var i = 0
        // "1 h 30 m" → "1h 30m": join a number to the unit after it.
        var joined: [String] = []
        while i < words.count {
            if Double(words[i]) != nil, i + 1 < words.count, unit(words[i + 1]) != nil {
                joined.append(words[i] + words[i + 1]); i += 2
            } else { joined.append(words[i]); i += 1 }
        }
        words = joined
        for w in words {
            if let s = duration(w) { seconds += s; found = true }
            else if !filler.contains(w) { labelWords.append(w) }
        }
        guard found, seconds > 0, seconds <= 24 * 3600 else { return nil }
        let label = labelWords.joined(separator: " ")
        return (label.isEmpty ? "Timer" : label.prefix(1).uppercased() + label.dropFirst(), seconds)
    }

    private static func unit(_ s: String) -> Double? {
        switch s {
        case "h", "hr", "hrs", "hour", "hours": return 3600
        case "m", "min", "mins", "minute", "minutes": return 60
        case "s", "sec", "secs", "second", "seconds": return 1
        default: return nil
        }
    }

    /// One word as a length of time: "10", "10m", "1h30", "1h30m", "90s", "1:30".
    private static func duration(_ w: String) -> Double? {
        if let n = Double(w) { return n > 0 ? n * 60 : nil }
        if w.contains(":") {
            let p = w.split(separator: ":").map { Double($0) }
            guard p.count == 2 || p.count == 3, !p.contains(where: { $0 == nil }) else { return nil }
            let v = p.compactMap { $0 }
            return v.count == 2 ? v[0] * 60 + v[1] : v[0] * 3600 + v[1] * 60 + v[2]
        }
        var total = 0.0
        var number = ""
        var letters = ""
        var lastUnit: Double?
        var any = false
        func flush() -> Bool {
            guard !number.isEmpty else { return letters.isEmpty }
            guard let n = Double(number) else { return false }
            if letters.isEmpty {
                // "1h30": a trailing number takes the next unit down.
                guard let last = lastUnit else { return false }
                total += n * (last == 3600 ? 60 : 1)
            } else {
                guard let u = unit(letters) else { return false }
                total += n * u
                lastUnit = u
            }
            any = true
            number = ""; letters = ""
            return true
        }
        for ch in w {
            if ch.isNumber || ch == "." {
                if !letters.isEmpty { guard flush() else { return nil } }
                number.append(ch)
            } else if ch.isLetter {
                guard !number.isEmpty else { return nil }
                letters.append(ch)
            } else { return nil }
        }
        guard flush(), any else { return nil }
        return total
    }
}

// MARK: - Chores

/// A job that goes round the flat: each period it's the next person's turn.
public struct Chore: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var icon: String
    /// Who takes turns, in order.
    public var people: [String]
    /// How often it comes round, in days (7 is weekly).
    public var everyDays: Int
    /// The first day of the first person's turn.
    public var start: Date
    public var lastDone: Date?
    public var lastDoneBy: String?

    public init(id: UUID = UUID(), name: String, icon: String = "sparkles", people: [String], everyDays: Int = 7, start: Date) {
        self.id = id; self.name = name; self.icon = icon; self.people = people; self.everyDays = everyDays; self.start = start
    }

    enum CodingKeys: String, CodingKey { case id, name, icon, people, everyDays, start, lastDone, lastDoneBy }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "Chore")
        icon = c.value(.icon, default: "sparkles")
        people = c.value(.people, default: [])
        everyDays = c.value(.everyDays, default: 7)
        start = c.value(.start, default: Date())
        lastDone = c.optional(.lastDone)
        lastDoneBy = c.optional(.lastDoneBy)
    }

    /// Which turn we're on (0 for the first period), counting whole days so clock changes don't matter.
    public func period(on date: Date, calendar: Calendar = .plate) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)).day ?? 0
        let every = max(1, everyDays)
        return Int((Double(days) / Double(every)).rounded(.down))
    }

    public func periodStart(on date: Date, calendar: Calendar = .plate) -> Date {
        calendar.date(byAdding: .day, value: period(on: date, calendar: calendar) * max(1, everyDays), to: calendar.startOfDay(for: start)) ?? start
    }

    /// Whose turn it is.
    public func assignee(on date: Date, calendar: Calendar = .plate) -> String? {
        guard !people.isEmpty else { return nil }
        let p = period(on: date, calendar: calendar)
        return people[((p % people.count) + people.count) % people.count]
    }

    /// Done for this turn?
    public func isDone(on date: Date, calendar: Calendar = .plate) -> Bool {
        guard let lastDone else { return false }
        return lastDone >= periodStart(on: date, calendar: calendar)
    }

    /// Days left in this turn, counting today (1 means it's due today).
    public func daysLeft(on date: Date, calendar: Calendar = .plate) -> Int {
        let end = calendar.date(byAdding: .day, value: max(1, everyDays), to: periodStart(on: date, calendar: calendar)) ?? date
        return max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: end).day ?? 1)
    }
}

// MARK: - Bin days and other repeating things

public struct Recurring: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var icon: String
    public var tint: RGB?
    /// Every this many weeks (1 is weekly, 2 is fortnightly).
    public var everyWeeks: Int
    /// A day it happens on. The weekday comes from this; later dates repeat from it.
    public var anchor: Date

    public init(id: UUID = UUID(), name: String, icon: String = "trash", tint: RGB? = nil, everyWeeks: Int = 1, anchor: Date) {
        self.id = id; self.name = name; self.icon = icon; self.tint = tint; self.everyWeeks = everyWeeks; self.anchor = anchor
    }

    enum CodingKeys: String, CodingKey { case id, name, icon, tint, everyWeeks, anchor }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "Bin day")
        icon = c.value(.icon, default: "trash")
        tint = c.optional(.tint)
        everyWeeks = c.value(.everyWeeks, default: 1)
        anchor = c.value(.anchor, default: Date())
    }

    /// The next day it happens, today included.
    public func next(onOrAfter date: Date, calendar: Calendar = .plate) -> Date {
        let a = calendar.startOfDay(for: anchor), d = calendar.startOfDay(for: date)
        let step = max(1, everyWeeks) * 7
        let days = calendar.dateComponents([.day], from: a, to: d).day ?? 0
        let periods = days <= 0 ? 0 : Int((Double(days) / Double(step)).rounded(.up))
        return calendar.date(byAdding: .day, value: periods * step, to: a) ?? a
    }
}

public enum DayText {
    /// "Today", "Tomorrow", "Thursday" (within a week), otherwise "Thu 21 Nov".
    public static func relative(_ date: Date, now: Date, calendar: Calendar = .plate) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6: return weekday(date, calendar: calendar)
        default:
            let c = calendar.dateComponents([.day, .month], from: date)
            return "\(weekday(date, calendar: calendar).prefix(3)) \(c.day ?? 0) \(months[(c.month ?? 1) - 1])"
        }
    }

    public static func weekday(_ date: Date, calendar: Calendar = .plate) -> String {
        days[(calendar.component(.weekday, from: date) + 6) % 7]
    }

    static let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// For a countdown tile: the number and what it counts ("12", "days to go").
    public static func countdown(to date: Date, now: Date, calendar: Calendar = .plate) -> (number: String, caption: String) {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return ("Today", "It's here")
        case 1: return ("1", "day to go")
        case -1: return ("1", "day ago")
        case let d where d > 1: return ("\(d)", "days to go")
        default: return ("\(-days)", "days ago")
        }
    }

    /// "Good morning", by the hour, with the name when there is one.
    public static func greeting(hour: Int, name: String? = nil) -> String {
        let g: String
        switch hour {
        case 5..<12: g = "Good morning"
        case 12..<18: g = "Good afternoon"
        case 18..<23: g = "Good evening"
        default: g = "Good night"
        }
        if let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty, name.lowercased() != "me" { return "\(g), \(name)" }
        return g
    }

    /// One line about the home for under the greeting: "3 lights on · 20.5° inside · Rain likely from 15:00".
    public static func summary(lightsOn: Int?, inside: Double?, outside: Double?, rain: String?, timers: Int, choresDue: Int) -> String {
        var parts: [String] = []
        if let lightsOn { parts.append(lightsOn == 0 ? "All lights off" : lightsOn == 1 ? "1 light on" : "\(lightsOn) lights on") }
        if let inside { parts.append(String(format: "%.1f° inside", inside)) }
        if let outside { parts.append("\(WeatherText.temperature(outside)) outside") }
        if let rain { parts.append(rain) }
        if timers > 0 { parts.append(timers == 1 ? "1 timer running" : "\(timers) timers running") }
        if choresDue > 0 { parts.append(choresDue == 1 ? "1 chore due" : "\(choresDue) chores due") }
        return parts.joined(separator: " · ")
    }

    /// The time in words, the British way: "twenty past four", "quarter to nine", "half past twelve", "midnight".
    /// Rounded to the nearest five minutes, as you'd say it.
    public static func clockWords(hour: Int, minute: Int) -> String {
        let names = ["twelve", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven"]
        var five = Int((Double(minute) / 5).rounded())
        var h = hour
        if five == 12 { five = 0; h += 1 }
        h = ((h % 24) + 24) % 24
        let next = (h + 1) % 24
        func name(_ hour24: Int) -> String {
            if hour24 == 0 { return "midnight" }
            if hour24 == 12 { return "midday" }
            return names[hour24 % 12]
        }
        switch five {
        case 0: return h == 0 || h == 12 ? name(h) : "\(name(h)) o'clock"
        case 1: return "five past \(name(h))"
        case 2: return "ten past \(name(h))"
        case 3: return "quarter past \(name(h))"
        case 4: return "twenty past \(name(h))"
        case 5: return "twenty-five past \(name(h))"
        case 6: return "half past \(name(h))"
        case 7: return "twenty-five to \(name(next))"
        case 8: return "twenty to \(name(next))"
        case 9: return "quarter to \(name(next))"
        case 10: return "ten to \(name(next))"
        default: return "five to \(name(next))"
        }
    }
}

// MARK: - Routines

public enum RoutineActionKind: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case scene, accessoryOn, accessoryOff, brightness, roomOn, roomOff, allLightsOff
    case playAlbum, pauseMusic, startTimer, say, wait, lightShow, stopLightShow, showArtwork

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .scene: return "Run a scene"
        case .accessoryOn: return "Turn something on"
        case .accessoryOff: return "Turn something off"
        case .brightness: return "Set a light's brightness"
        case .roomOn: return "Turn a room on"
        case .roomOff: return "Turn a room off"
        case .allLightsOff: return "Turn every light off"
        case .playAlbum: return "Play a pinned album or playlist"
        case .pauseMusic: return "Pause the music"
        case .startTimer: return "Start a timer"
        case .say: return "Say something"
        case .wait: return "Wait"
        case .lightShow: return "Start a light show"
        case .stopLightShow: return "Stop the light show"
        case .showArtwork: return "Show the artwork screen"
        }
    }

    public var icon: String {
        switch self {
        case .scene: return "sparkles"
        case .accessoryOn, .roomOn: return "power"
        case .accessoryOff, .roomOff, .allLightsOff: return "poweroff"
        case .brightness: return "sun.max"
        case .playAlbum: return "play.fill"
        case .pauseMusic: return "pause.fill"
        case .startTimer: return "timer"
        case .say: return "speaker.wave.2"
        case .wait: return "hourglass"
        case .lightShow, .stopLightShow: return "party.popper"
        case .showArtwork: return "photo"
        }
    }

    /// Whether the action points at a HomeKit or Music thing chosen from a list.
    public var needsRef: Bool {
        switch self {
        case .scene, .accessoryOn, .accessoryOff, .brightness, .roomOn, .roomOff, .playAlbum: return true
        default: return false
        }
    }
}

public struct RoutineAction: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: RoutineActionKind
    /// The HomeKit or Music identifier the action is about.
    public var ref: String?
    /// The name of that thing, for showing the routine without HomeKit loaded.
    public var name: String?
    /// Brightness (percent), a wait or timer length (seconds).
    public var value: Double?
    /// What to say, a timer's label, or which light show.
    public var text: String?

    public init(id: UUID = UUID(), kind: RoutineActionKind, ref: String? = nil, name: String? = nil, value: Double? = nil, text: String? = nil) {
        self.id = id; self.kind = kind; self.ref = ref; self.name = name; self.value = value; self.text = text
    }

    enum CodingKeys: String, CodingKey { case id, kind, ref, name, value, text }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        kind = try c.decode(RoutineActionKind.self, forKey: .kind)
        ref = c.optional(.ref); name = c.optional(.name); value = c.optional(.value); text = c.optional(.text)
    }

    /// "Turn on Lamp", "Wait 30 sec", "Say “Dinner's ready”".
    public var summary: String {
        let thing = name ?? "something"
        switch kind {
        case .scene: return "Run \(thing)"
        case .accessoryOn, .roomOn: return "Turn on \(thing)"
        case .accessoryOff, .roomOff: return "Turn off \(thing)"
        case .brightness: return "Set \(thing) to \(Int((value ?? 50).rounded()))%"
        case .allLightsOff: return "Turn every light off"
        case .playAlbum: return "Play \(thing)"
        case .pauseMusic: return "Pause the music"
        case .startTimer: return "Start a \(DashTimer.words(value ?? 300)) timer" + ((text ?? "").isEmpty ? "" : " (\(text!))")
        case .say: return "Say “\(text ?? "")”"
        case .wait: return "Wait \(DashTimer.words(value ?? 5))"
        case .lightShow: return "Start the \((LightShow(rawValue: text ?? "") ?? .party).title.lowercased()) light show"
        case .stopLightShow: return "Stop the light show"
        case .showArtwork: return "Show the artwork screen"
        }
    }
}

public struct Routine: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var icon: String
    public var actions: [RoutineAction]
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, icon: String = "wand.and.stars", actions: [RoutineAction] = []) {
        self.id = id; self.name = name; self.icon = icon; self.actions = actions; self.updatedAt = Date()
    }

    enum CodingKeys: String, CodingKey { case id, name, icon, actions, updatedAt }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "Routine")
        icon = c.value(.icon, default: "wand.and.stars")
        // One action from a newer Plate shouldn't lose the rest: read them one at a time.
        actions = (c.optional(.actions, as: [Lenient<RoutineAction>].self) ?? []).compactMap(\.value)
        updatedAt = c.value(.updatedAt, default: Date())
    }
}

/// Wraps a value so that one unreadable item in a list is skipped instead of failing the whole list.
struct Lenient<T: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    var value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    func encode(to encoder: Encoder) throws { try value?.encode(to: encoder) }
}

public enum SunEvent: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case none, sunrise, sunset
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .none: return "At a set time"
        case .sunrise: return "At sunrise"
        case .sunset: return "At sunset"
        }
    }
}

/// Runs a routine by itself at a time of day. Works while Plate is open, which on the wall iPad is always.
public struct RoutineSchedule: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var routineId: UUID
    public var enabled: Bool
    /// Minutes after midnight, when `sun` is `.none`.
    public var minutes: Int
    public var sun: SunEvent
    /// Minutes before (negative) or after the sunrise or sunset.
    public var offset: Int
    /// Days it runs on: 1 is Sunday … 7 is Saturday. Empty means every day.
    public var weekdays: Set<Int>

    public init(id: UUID = UUID(), routineId: UUID, enabled: Bool = true, minutes: Int = 7 * 60, sun: SunEvent = .none,
                offset: Int = 0, weekdays: Set<Int> = []) {
        self.id = id; self.routineId = routineId; self.enabled = enabled; self.minutes = minutes; self.sun = sun
        self.offset = offset; self.weekdays = weekdays
    }

    enum CodingKeys: String, CodingKey { case id, routineId, enabled, minutes, sun, offset, weekdays }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        routineId = try c.decode(UUID.self, forKey: .routineId)
        enabled = c.value(.enabled, default: true)
        minutes = c.value(.minutes, default: 7 * 60)
        sun = c.value(.sun, default: .none)
        offset = c.value(.offset, default: 0)
        weekdays = c.value(.weekdays, default: [])
    }

    /// When it runs on the day containing `day`, or nil if it doesn't that day (wrong weekday, or no sun times yet).
    public func fireTime(on day: Date, sunrise: Date?, sunset: Date?, calendar: Calendar = .plate) -> Date? {
        if !weekdays.isEmpty, !weekdays.contains(calendar.component(.weekday, from: day)) { return nil }
        switch sun {
        case .none: return calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: day))
        case .sunrise: return sunrise.flatMap { calendar.isDate($0, inSameDayAs: day) ? $0.addingTimeInterval(Double(offset) * 60) : nil }
        case .sunset: return sunset.flatMap { calendar.isDate($0, inSameDayAs: day) ? $0.addingTimeInterval(Double(offset) * 60) : nil }
        }
    }

    /// Whether it should run now: its time fell after the last check and no more than `grace` seconds ago, so a
    /// schedule missed while the app was closed for hours doesn't fire late.
    public func isDue(lastCheck: Date, now: Date, sunrise: Date?, sunset: Date?, grace: Double = 600, calendar: Calendar = .plate) -> Bool {
        guard enabled, let t = fireTime(on: now, sunrise: sunrise, sunset: sunset, calendar: calendar) else { return false }
        return t > lastCheck && t <= now && now.timeIntervalSince(t) <= grace
    }

    /// "07:00 every day", "Sunset −15 min on Mon, Fri".
    public var summary: String {
        let when: String
        switch sun {
        case .none: when = IdleMode.timeText(minutes)
        case .sunrise, .sunset:
            let base = sun == .sunrise ? "Sunrise" : "Sunset"
            when = offset == 0 ? base : "\(base) \(offset > 0 ? "+" : "−")\(abs(offset)) min"
        }
        if weekdays.isEmpty || weekdays.count == 7 { return "\(when) every day" }
        if weekdays == [2, 3, 4, 5, 6] { return "\(when) on weekdays" }
        if weekdays == [1, 7] { return "\(when) at weekends" }
        let order = [2, 3, 4, 5, 6, 7, 1]
        return "\(when) on " + order.filter(weekdays.contains).map { String(DayText.days[$0 - 1].prefix(3)) }.joined(separator: ", ")
    }
}

// MARK: - Lights

/// Moving light effects for colour bulbs.
public enum LightShow: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case party, rainbow, candle, ocean, sunset

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .party: return "Party"
        case .rainbow: return "Slow rainbow"
        case .candle: return "Candlelight"
        case .ocean: return "Ocean"
        case .sunset: return "Sunset"
        }
    }
    public var icon: String {
        switch self {
        case .party: return "party.popper.fill"
        case .rainbow: return "rainbow"
        case .candle: return "flame.fill"
        case .ocean: return "water.waves"
        case .sunset: return "sunset.fill"
        }
    }

    /// Seconds between changes. HomeKit bulbs can't keep up with much faster than this.
    public var interval: Double {
        switch self {
        case .party: return 1.5
        case .candle: return 2
        case .rainbow, .ocean, .sunset: return 4
        }
    }

    /// The colour for one light at one step: hue in degrees (0 to 360), saturation and brightness in percent.
    /// Lights get different colours from each other so the room isn't one flat colour.
    public func color(step: Int, light: Int, of count: Int) -> (hue: Double, saturation: Double, brightness: Double) {
        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: step &* 7919 &+ light &* 104_729 &+ 1))
        let spread = 360.0 / Double(max(1, count))
        func wrap(_ h: Double) -> Double { let m = h.truncatingRemainder(dividingBy: 360); return m < 0 ? m + 360 : m }
        switch self {
        case .party:
            // Six strong colours, never the same one on a light twice running.
            let palette = [0.0, 30, 120, 200, 275, 320]
            let i = (step * 5 + light * 2 + Int(rng.next() % 2) * 3) % palette.count
            return (palette[i], 100, 100)
        case .rainbow:
            return (wrap(Double(step) * 12 + Double(light) * spread), 90, 80)
        case .candle:
            let flicker = Double(rng.next() % 1000) / 1000
            return (28 + flicker * 10, 85 + flicker * 10, 35 + flicker * 30)
        case .ocean:
            let wave = sin(Double(step) * 0.5 + Double(light) * 1.3)
            return (200 + wave * 30, 85, 60 + wave * 15)
        case .sunset:
            let wave = sin(Double(step) * 0.4 + Double(light) * 1.1)
            return (wrap(15 + wave * 25), 90, 65 + wave * 15)
        }
    }
}

public enum LightColor {
    /// Ready-made colours for the light picker: name, hue (degrees), saturation (percent).
    public static let swatches: [(name: String, hue: Double, saturation: Double)] = [
        ("Red", 0, 100), ("Orange", 28, 100), ("Yellow", 50, 100), ("Lime", 90, 100), ("Green", 130, 100),
        ("Teal", 175, 100), ("Sky", 200, 90), ("Blue", 235, 100), ("Purple", 275, 100), ("Pink", 320, 85),
    ]

    /// Whites, warm to cool, as colour temperatures in kelvin.
    public static let whites: [(name: String, kelvin: Double)] = [
        ("Candle", 2000), ("Warm", 2700), ("Soft", 3200), ("Neutral", 4000), ("Daylight", 5500), ("Cool", 6500),
    ]

    /// HomeKit measures colour temperature in mireds (a million divided by the kelvin), kept inside the bulb's range.
    public static func mired(kelvin: Double, min lo: Double = 140, max hi: Double = 500) -> Int {
        Int(Swift.min(hi, Swift.max(lo, 1_000_000 / Swift.max(1, kelvin))).rounded())
    }
}

// MARK: - Odds and ends

public enum WiFiQR {
    /// The text a phone's camera understands as "join this Wi-Fi". Special characters in the name and password are
    /// escaped as the format requires.
    public static func payload(ssid: String, password: String, hidden: Bool = false) -> String {
        func esc(_ s: String) -> String {
            var out = ""
            for ch in s {
                if "\\;,:\"".contains(ch) { out.append("\\") }
                out.append(ch)
            }
            return out
        }
        let security = password.isEmpty ? "nopass" : "WPA"
        return "WIFI:T:\(security);S:\(esc(ssid));" + (password.isEmpty ? "" : "P:\(esc(password));") + (hidden ? "H:true;" : "") + ";"
    }
}

extension IdleMode {
    /// A small, slow drift for what's on the idle screen, so nothing sits on the same pixels for hours
    /// (which marks some screens). Moves a few points every minute around a loop that takes about an hour.
    public static func burnInOffset(_ date: Date, radius: Double = 12) -> (x: Double, y: Double) {
        let minute = (date.timeIntervalSince1970 / 60).rounded(.down)
        return (radius * cos(minute * 2 * .pi / 61), radius * sin(minute * 2 * .pi / 37))
    }
}

public enum Briefing {
    /// What the "Briefing" tile says out loud. Each part is left out when there's nothing to say.
    public static func text(greeting: String, weather: String?, rain: String?, meals: [String], chores: [String], bins: [String], timers: Int) -> String {
        var s = [greeting + "."]
        if let weather { s.append(weather) }
        if let rain { s.append(rain + ".") }
        if !meals.isEmpty { s.append("On the plan today: " + list(meals) + ".") }
        if !chores.isEmpty { s.append("Chores due: " + list(chores) + ".") }
        if !bins.isEmpty { s.append(list(bins) + ".") }
        if timers > 0 { s.append(timers == 1 ? "One timer is running." : "\(timers) timers are running.") }
        return s.joined(separator: " ")
    }

    /// "a", "a and b", "a, b and c".
    public static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}

extension TileKind {
    /// A symbol that stands for this kind of tile, for the little pictures on a folder.
    public var symbol: String {
        switch self {
        case .accessory: return "lightbulb.fill"
        case .scene: return "sparkles"
        case .room: return "lightbulb.2.fill"
        case .musicAlbum: return "music.note"
        case .playlist: return "music.note.list"
        case .clock, .worldClock: return "clock.fill"
        case .todaysMeals: return "fork.knife"
        case .shoppingList: return "cart.fill"
        case .useSoon: return "clock.badge.exclamationmark"
        case .note: return "note.text"
        case .nowPlaying: return "play.circle.fill"
        case .weather: return "cloud.sun.fill"
        case .timer: return "timer"
        case .countdown: return "calendar.badge.clock"
        case .calendar: return "calendar"
        case .chores: return "checklist"
        case .bins: return "trash.fill"
        case .wifi: return "wifi"
        case .camera: return "video.fill"
        case .climate: return "thermometer.medium"
        case .allOff: return "lightbulb.slash.fill"
        case .photoFrame: return "photo.fill"
        case .forecast: return "calendar.day.timeline.left"
        case .sun: return "sunset.fill"
        case .macros: return "flame.fill"
        case .cookNow: return "frying.pan.fill"
        case .shortcut: return "link"
        case .routine: return "wand.and.stars"
        case .lightShow: return "party.popper.fill"
        case .activity: return "clock.arrow.circlepath"
        case .command: return "text.cursor"
        case .briefing: return "speaker.wave.2.fill"
        case .battery: return "battery.25"
        case .group: return "square.grid.2x2.fill"
        case .folder: return "folder.fill"
        case .trains: return "tram.fill"
        case .heading: return "textformat.size"
        case .spacer: return "square.dashed"
        case .unknown: return "questionmark"
        }
    }
}
