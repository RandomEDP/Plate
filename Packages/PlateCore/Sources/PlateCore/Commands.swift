import Foundation

// Typed commands for the dashboard: "kitchen off", "lamp 30%", "play Blue", "pasta 10 min", "movie night".
// No AI and no network: the words are matched against the names of the home's accessories, rooms, scenes, routines and
// pinned music, so it's instant and works the same every time.

public struct CommandNames: Sendable {
    public struct Named: Hashable, Sendable {
        public var id: String
        public var name: String
        /// For an accessory, the room it's in.
        public var room: String?
        public init(id: String, name: String, room: String? = nil) { self.id = id; self.name = name; self.room = room }
    }

    public var accessories: [Named]
    public var rooms: [Named]
    public var scenes: [Named]
    public var routines: [Named]
    /// Pinned albums and playlists.
    public var music: [Named]

    public init(accessories: [Named] = [], rooms: [Named] = [], scenes: [Named] = [], routines: [Named] = [], music: [Named] = []) {
        self.accessories = accessories; self.rooms = rooms; self.scenes = scenes; self.routines = routines; self.music = music
    }
}

public enum CommandAction: Hashable, Sendable {
    /// `on` nil means "the other way from now".
    case accessory(id: String, on: Bool?)
    case brightness(id: String, percent: Int)
    case room(id: String, on: Bool)
    /// Every light in a room to a brightness.
    case roomBrightness(id: String, percent: Int)
    case scene(id: String)
    case routine(id: String)
    case allLightsOff
    case play(id: String)
    case pause, resume, next
    case timer(label: String, seconds: Double)
    case lightShow(LightShow)
    case stopLightShow
    case briefing
    case showArtwork
}

public struct CommandResult: Hashable, Sendable {
    public var actions: [CommandAction]
    /// What to show back: "Kitchen off", or why nothing happened.
    public var reply: String
    public var understood: Bool { !actions.isEmpty }
}

public enum CommandParser {
    public static func parse(_ text: String, names: CommandNames) -> CommandResult {
        let clauses = split(normalise(text))
        guard !clauses.isEmpty else { return CommandResult(actions: [], reply: "Type what you'd like, such as “kitchen off” or “pasta 10 min”.") }
        var actions: [CommandAction] = []
        var replies: [String] = []
        for clause in clauses {
            if let (action, reply) = one(clause, names: names) {
                actions.append(action)
                replies.append(reply)
            } else {
                replies.append("I didn't understand “\(clause)”")
            }
        }
        return CommandResult(actions: actions, reply: replies.joined(separator: ". "))
    }

    /// Lower case, punctuation gone (but "%" and ":" and "." kept for numbers), polite words dropped.
    static func normalise(_ text: String) -> String {
        var out = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "%" || ch == ":" || ch == "." || ch == "," { out.append(ch) }
            else if ch == "'" || ch == "’" { continue }
            else { out.append(" ") }
        }
        let drop: Set<String> = ["please", "the", "can", "you", "could", "my", "to", "hey", "plate", "up"]
        return out.split(separator: " ").map(String.init).filter { !drop.contains($0) }
            .map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }.joined(separator: " ")
    }

    /// "lamp on, then play blue" is two commands. "and" isn't split on, because names contain it ("Salt and Pepper").
    static func split(_ text: String) -> [String] {
        text.replacingOccurrences(of: " then ", with: ",").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func words(_ s: String) -> [String] { s.split(separator: " ").map(String.init) }

    private static func key(_ name: String) -> String { normalise(name) }

    /// The best name found inside the clause: the longest one whose words all appear together, in order.
    private static func find(_ list: [CommandNames.Named], in clause: String) -> [CommandNames.Named] {
        let padded = " " + clause + " "
        var best: [CommandNames.Named] = []
        var bestLength = 0
        for item in list {
            let k = key(item.name)
            guard !k.isEmpty, padded.contains(" " + k + " ") || padded.contains(" " + k + "s ") else { continue }
            if k.count > bestLength { best = [item]; bestLength = k.count }
            else if k.count == bestLength { best.append(item) }
        }
        return best
    }

    private static func percent(in clause: String) -> Int? {
        let w = words(clause)
        for (i, word) in w.enumerated() {
            if word.hasSuffix("%"), let n = Int(word.dropLast()) { return min(100, max(0, n)) }
            if let n = Int(word), i + 1 < w.count, w[i + 1] == "percent" || w[i + 1] == "%" { return min(100, max(0, n)) }
        }
        if w.contains("dim") || w.contains("low") { return 25 }
        if w.contains("half") { return 50 }
        if w.contains("bright") || w.contains("brighten") || w.contains("full") || w.contains("max") { return 100 }
        return nil
    }

    private static func one(_ clause: String, names: CommandNames) -> (CommandAction, String)? {
        let w = Set(words(clause))
        let all = words(clause)

        // Music controls.
        if clause == "pause" || clause == "stop" || clause == "stop music" || clause == "pause music" || clause == "music off" {
            return (.pause, "Music paused")
        }
        if clause == "next" || clause == "skip" || clause == "next song" || clause == "skip song" || clause == "next track" {
            return (.next, "Next song")
        }
        if clause == "play" || clause == "resume" || clause == "play music" || clause == "music on" { return (.resume, "Playing") }

        // Scenes and routines by name come before everything else, so a scene called "Good night" always wins.
        let stripped = all.first == "run" || all.first == "start" || all.first == "set" ? all.dropFirst().joined(separator: " ") : clause
        if let r = find(names.routines, in: stripped).first, key(r.name) == stripped || stripped == key(r.name) + " routine" {
            return (.routine(id: r.id), "Running \(r.name)")
        }
        if let s = find(names.scenes, in: stripped).first, key(s.name) == stripped || stripped == key(s.name) + " scene" {
            return (.scene(id: s.id), "Running \(s.name)")
        }

        if all.first == "play" || all.first == "listen" {
            if let m = find(names.music, in: clause).first { return (.play(id: m.id), "Playing \(m.name)") }
            return nil
        }

        // Light shows.
        let lightWord = w.contains("light") || w.contains("lights")
        if (w.contains("show") && lightWord) || w.contains("party") || w.contains("disco") || w.contains("rainbow") || w.contains("candlelight") {
            if w.contains("stop") || w.contains("off") || w.contains("end") { return (.stopLightShow, "Light show stopped") }
            let show: LightShow = w.contains("rainbow") ? .rainbow : w.contains("candle") || w.contains("candlelight") ? .candle
                : w.contains("ocean") ? .ocean : w.contains("sunset") ? .sunset : .party
            return (.lightShow(show), "\(show.title) light show")
        }

        if clause == "briefing" || clause == "brief me" || clause == "whats on today" || clause == "whats on" {
            return (.briefing, "Here's your briefing")
        }
        if clause == "artwork" || clause == "screensaver" || clause == "photos" || clause == "show artwork" || clause == "show photos" {
            return (.showArtwork, "Showing the artwork")
        }

        let on: Bool? = {
            if w.contains("off") || w.contains("unlock") || w.contains("close") || w.contains("shut") { return false }
            if w.contains("on") || w.contains("lock") || w.contains("open") { return true }
            return nil
        }()
        // Locks and blinds read the other way round: "unlock" switches a lock's "locked" off, "open" switches blinds on.
        let level = percent(in: clause)

        let rooms = find(names.rooms, in: clause)
        var accessories = find(names.accessories, in: clause)
        if accessories.count > 1, let room = rooms.first {
            let inRoom = accessories.filter { $0.room.map(key) == key(room.name) }
            if !inRoom.isEmpty { accessories = inRoom }
        }

        // "everything off", "all lights off", "lights off" with no room named.
        if on == false, rooms.isEmpty, accessories.isEmpty,
           w.contains("everything") || w.contains("all") || w.contains("lights") || w.contains("light") {
            return (.allLightsOff, "Every light off")
        }

        // A bare number after a light's name is a brightness: "lamp 30".
        let bare = all.compactMap { Int($0) }.first { (1...100).contains($0) }

        // A named accessory beats the room it's in.
        if let a = accessories.first {
            if let level = level ?? bare, level > 0 { return (.brightness(id: a.id, percent: level), "\(a.name) to \(level)%") }
            if level == 0 { return (.accessory(id: a.id, on: false), "\(a.name) off") }
            if let on {
                let verb = w.contains("unlock") ? "unlocked" : w.contains("lock") ? "locked" : w.contains("open") ? "open"
                    : (w.contains("close") || w.contains("shut")) ? "closed" : on ? "on" : "off"
                return (.accessory(id: a.id, on: on), "\(a.name) \(verb)")
            }
            return (.accessory(id: a.id, on: nil), "Switched \(a.name)")
        }
        if let r = rooms.first {
            if let level, level > 0 { return (.roomBrightness(id: r.id, percent: level), "\(r.name) to \(level)%") }
            if let on = level == 0 ? false : on { return (.room(id: r.id, on: on), "\(r.name) \(on ? "on" : "off")") }
        }

        // A scene or routine mentioned anywhere ("do movie night").
        if let r = find(names.routines, in: clause).first { return (.routine(id: r.id), "Running \(r.name)") }
        if let s = find(names.scenes, in: clause).first { return (.scene(id: s.id), "Running \(s.name)") }

        // Anything with a length of time in it is a timer: "pasta 10", "timer 5 min".
        if let t = TimerParser.parse(clause) {
            return (.timer(label: t.label, seconds: t.seconds), "\(t.label) timer for \(DashTimer.words(t.seconds))")
        }
        // Pinned music by name alone.
        if let m = find(names.music, in: clause).first, key(m.name) == clause { return (.play(id: m.id), "Playing \(m.name)") }
        return nil
    }
}
