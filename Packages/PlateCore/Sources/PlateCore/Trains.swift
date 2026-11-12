import Foundation

// Live train departures for the dashboard's trains tile. The data is National Rail's Live Departure Board (the same
// feed station screens use), read through the Rail Data Marketplace with the user's own free key. Everything here is
// plain Swift: building the request, reading the reply, and deciding which trains to show and which are the fast ones.

public struct TrainStation: Hashable, Sendable, Identifiable {
    public var name: String
    /// The three-letter station code ("PAD").
    public var crs: String
    public var id: String { crs }
    public init(_ name: String, _ crs: String) { self.name = name; self.crs = crs }

    /// London terminals and interchanges, the Elizabeth line, and the busier stations around the country. Any other
    /// station works too: type its three-letter code.
    public static let common: [TrainStation] = [
        TrainStation("London Liverpool Street", "LST"), TrainStation("London Paddington", "PAD"), TrainStation("London Kings Cross", "KGX"),
        TrainStation("London St Pancras", "STP"), TrainStation("London Euston", "EUS"), TrainStation("London Victoria", "VIC"),
        TrainStation("London Waterloo", "WAT"), TrainStation("London Bridge", "LBG"), TrainStation("London Fenchurch Street", "FST"),
        TrainStation("London Marylebone", "MYB"), TrainStation("London Charing Cross", "CHX"), TrainStation("London Cannon Street", "CST"),
        TrainStation("London Blackfriars", "BFR"), TrainStation("Farringdon", "ZFD"), TrainStation("Tottenham Court Road", "TCR"),
        TrainStation("Bond Street", "BDS"), TrainStation("Whitechapel", "ZLW"), TrainStation("Canary Wharf", "CWX"),
        TrainStation("Custom House", "CUS"), TrainStation("Woolwich", "WWC"), TrainStation("Abbey Wood", "ABW"),
        TrainStation("Stratford", "SRA"), TrainStation("Maryland", "MYL"), TrainStation("Forest Gate", "FOG"),
        TrainStation("Manor Park", "MNP"), TrainStation("Ilford", "IFD"), TrainStation("Seven Kings", "SVK"),
        TrainStation("Goodmayes", "GMY"), TrainStation("Chadwell Heath", "CTH"), TrainStation("Romford", "RMF"),
        TrainStation("Gidea Park", "GDP"), TrainStation("Harold Wood", "HRO"), TrainStation("Brentwood", "BRE"),
        TrainStation("Shenfield", "SNF"), TrainStation("Chelmsford", "CHM"), TrainStation("Colchester", "COL"),
        TrainStation("Ipswich", "IPS"), TrainStation("Norwich", "NRW"), TrainStation("Southend Victoria", "SOV"),
        TrainStation("Upminster", "UPM"), TrainStation("Cambridge", "CBG"), TrainStation("Stansted Airport", "SSD"),
        TrainStation("Ealing Broadway", "EAL"), TrainStation("Hayes & Harlington", "HAY"), TrainStation("Heathrow Terminals 2 & 3", "HXX"),
        TrainStation("Heathrow Terminal 5", "HWV"), TrainStation("Slough", "SLO"), TrainStation("Maidenhead", "MAI"),
        TrainStation("Reading", "RDG"), TrainStation("Oxford", "OXF"), TrainStation("Clapham Junction", "CLJ"),
        TrainStation("East Croydon", "ECR"), TrainStation("Gatwick Airport", "GTW"), TrainStation("Brighton", "BTN"),
        TrainStation("Watford Junction", "WFJ"), TrainStation("Milton Keynes Central", "MKC"), TrainStation("Birmingham New Street", "BHM"),
        TrainStation("Manchester Piccadilly", "MAN"), TrainStation("Liverpool Lime Street", "LIV"), TrainStation("Leeds", "LDS"),
        TrainStation("York", "YRK"), TrainStation("Newcastle", "NCL"), TrainStation("Sheffield", "SHF"),
        TrainStation("Nottingham", "NOT"), TrainStation("Bristol Temple Meads", "BRI"), TrainStation("Bath Spa", "BTH"),
        TrainStation("Cardiff Central", "CDF"), TrainStation("Edinburgh", "EDB"), TrainStation("Glasgow Central", "GLC"),
    ]

    /// Stations matching what's been typed, by name or code. A bare three-letter code that isn't in the list is
    /// offered as itself, so any station in Britain can be used.
    public static func search(_ text: String) -> [TrainStation] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return common }
        var found = common.filter { $0.crs.lowercased() == q } + common.filter { $0.crs.lowercased() != q && $0.name.lowercased().contains(q) }
        if q.count == 3, q.allSatisfy(\.isLetter), !found.contains(where: { $0.crs.lowercased() == q }) {
            found.insert(TrainStation("Station code \(q.uppercased())", q.uppercased()), at: 0)
        }
        return found
    }

    public static func name(for crs: String) -> String {
        common.first { $0.crs == crs.uppercased() }?.name ?? crs.uppercased()
    }
}

public struct TrainCall: Hashable, Sendable {
    public var name: String
    public var crs: String
    /// Timetabled time, "HH:mm".
    public var scheduled: String
    /// "On time", a new time, "Delayed" or "Cancelled".
    public var expected: String?
    public init(name: String, crs: String, scheduled: String, expected: String? = nil) {
        self.name = name; self.crs = crs; self.scheduled = scheduled; self.expected = expected
    }
}

public struct TrainDeparture: Hashable, Sendable, Identifiable {
    public var id: String
    /// Timetabled departure, "HH:mm".
    public var scheduled: String
    /// "On time", a new time ("10:21"), "Delayed" or "Cancelled".
    public var expected: String
    public var platform: String?
    public var operatorName: String
    /// Two letters: "XR" is the Elizabeth line, "LE" Greater Anglia, "GW" Great Western.
    public var operatorCode: String
    public var destination: String
    public var cancelled: Bool
    /// Where it stops after this station, in order.
    public var calls: [TrainCall]
    /// Number of carriages, when the feed says.
    public var length: Int?

    public init(id: String, scheduled: String, expected: String, platform: String? = nil, operatorName: String, operatorCode: String,
                destination: String, cancelled: Bool = false, calls: [TrainCall] = [], length: Int? = nil) {
        self.id = id; self.scheduled = scheduled; self.expected = expected; self.platform = platform
        self.operatorName = operatorName; self.operatorCode = operatorCode; self.destination = destination
        self.cancelled = cancelled; self.calls = calls; self.length = length
    }

    /// The time it's now expected to leave, "HH:mm": the new time if there is one, otherwise the timetabled one.
    public var leaves: String { TrainTime.minutes(expected) != nil ? expected : scheduled }

    public var isCancelled: Bool { cancelled || expected.lowercased() == "cancelled" }

    /// Minutes late, or 0. "Delayed" with no new time counts as late by an unknown amount (nil).
    public var minutesLate: Int? {
        if expected.lowercased() == "delayed" { return nil }
        guard let e = TrainTime.minutes(expected), let s = TrainTime.minutes(scheduled) else { return 0 }
        return max(0, TrainTime.forward(from: s, to: e))
    }

    /// "On time", "3 min late", "Delayed", "Cancelled".
    public var status: String {
        if isCancelled { return "Cancelled" }
        guard let late = minutesLate else { return "Delayed" }
        return late == 0 ? "On time" : "\(late) min late"
    }

    /// Minutes from now until it leaves (negative if it has just gone).
    public func minutesUntil(nowMinutes: Int) -> Int {
        guard let t = TrainTime.minutes(leaves) else { return 0 }
        return TrainTime.signed(from: nowMinutes, to: t)
    }

    /// The stop at a station, if it calls there.
    public func call(at crs: String) -> TrainCall? { calls.first { $0.crs == crs.uppercased() } }

    /// How many stations it stops at before reaching `crs` (0 means next stop). nil if it doesn't call there.
    public func stops(before crs: String) -> Int? { calls.firstIndex { $0.crs == crs.uppercased() } }

    /// When it gets to `crs`, "HH:mm".
    public func arrival(at crs: String) -> String? {
        guard let c = call(at: crs) else { return nil }
        if let e = c.expected, TrainTime.minutes(e) != nil { return e }
        return c.scheduled
    }

    /// Minutes from leaving here to arriving at `crs`.
    public func journeyMinutes(to crs: String) -> Int? {
        guard let a = arrival(at: crs).flatMap(TrainTime.minutes), let d = TrainTime.minutes(leaves) else { return nil }
        return TrainTime.forward(from: d, to: a)
    }
}

public enum TrainTime {
    /// "09:05" as minutes after midnight; nil for "On time", "Delayed" and anything else that isn't a time.
    public static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    /// Minutes from one time of day to a later one, going past midnight if need be (23:50 to 00:10 is 20).
    public static func forward(from: Int, to: Int) -> Int { ((to - from) % 1440 + 1440) % 1440 }

    /// Like `forward`, but a time that looks like it was a little while ago comes back negative (so a train that left
    /// two minutes ago is -2, not 1438).
    public static func signed(from: Int, to: Int) -> Int {
        let f = forward(from: from, to: to)
        return f > 1200 ? f - 1440 : f
    }

    /// "Due", "4 min", "1 hr 12 min".
    public static func countdown(_ minutes: Int) -> String {
        if minutes <= 0 { return "Due" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) hr \(minutes % 60) min"
    }
}

public struct TrainBoard: Hashable, Sendable {
    public var station: String
    public var departures: [TrainDeparture]
    /// Notices for the station ("Lifts out of order…"), with any HTML taken out.
    public var messages: [String]
    public init(station: String, departures: [TrainDeparture], messages: [String] = []) {
        self.station = station; self.departures = departures; self.messages = messages
    }
}

/// What one trains tile is set to show.
/// Which trains a journey shows, by how quick they are.
public enum TrainSpeed: String, CaseIterable, Hashable, Sendable, Identifiable {
    case all, fast, stopping

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: return "Every train"
        case .fast: return "Fast trains only"
        case .stopping: return "Stopping trains only"
        }
    }

    /// How it's saved in a tile's options under "fast" ("1" was the only value before stopping trains came along).
    var saved: String? { self == .fast ? "1" : self == .stopping ? "slow" : nil }
    init(saved: String?) { self = saved == "1" ? .fast : saved == "slow" ? .stopping : .all }
}

/// One journey on a trains tile: a station, where the trains go, whose trains and how quick.
public struct TrainQuery: Hashable, Sendable {
    /// The station to leave from.
    public var from: String
    /// Only trains that call here ("into London" is a London terminal). Empty for every departure.
    public var to: String
    /// Only these operators' trains (two-letter codes). Empty for all.
    public var operators: Set<String>
    /// Fast trains, stopping trains or both.
    public var speed: TrainSpeed
    /// The name you gave it, such as "Romford fast". Empty to use the stations' names.
    public var label: String

    public var fastOnly: Bool {
        get { speed == .fast }
        set { speed = newValue ? .fast : .all }
    }

    public init(from: String, to: String = "", operators: Set<String> = [], fastOnly: Bool = false,
                speed: TrainSpeed? = nil, label: String = "") {
        self.from = from.uppercased(); self.to = to.uppercased(); self.operators = Set(operators.map { $0.uppercased() })
        self.speed = speed ?? (fastOnly ? .fast : .all)
        self.label = label
    }

    /// A tile can show this many journeys, one under another.
    public static let maxJourneys = 3

    /// The option key for a journey: the first uses the plain names ("from"), the others a number ("from2", "from3").
    public static func key(_ base: String, _ index: Int) -> String { index == 0 ? base : "\(base)\(index + 1)" }
    static let keys = ["from", "to", "ops", "fast", "label"]

    /// Reads one journey from a tile's saved settings.
    public init(options: [String: String], index: Int = 0) {
        func get(_ k: String) -> String? { options[Self.key(k, index)] }
        self.init(from: get("from") ?? "", to: get("to") ?? "",
                  operators: Set((get("ops") ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }),
                  speed: TrainSpeed(saved: get("fast")), label: get("label") ?? "")
    }

    /// Saves this journey into a tile's settings.
    public func write(into options: inout [String: String], index: Int = 0) {
        func set(_ k: String, _ v: String?) { options[Self.key(k, index)] = (v?.isEmpty ?? true) ? nil : v }
        set("from", from)
        set("to", to)
        set("ops", operators.sorted().joined(separator: ","))
        set("fast", speed.saved)
        set("label", label)
    }

    /// The journeys a tile has, in order. The first is always there (it may not have a station yet).
    public static func journeys(_ options: [String: String]) -> [TrainQuery] {
        var list = [TrainQuery(options: options, index: 0)]
        for i in 1..<maxJourneys {
            let q = TrainQuery(options: options, index: i)
            if q.isReady { list.append(q) } else { break }
        }
        return list
    }

    /// Adds a journey after the others (a copy of the last one's station, to change), unless the tile is full.
    public static func addJourney(to options: inout [String: String]) {
        let list = journeys(options)
        guard list.count < maxJourneys, let last = list.last, last.isReady else { return }
        var copy = last
        copy.label = ""
        copy.write(into: &options, index: list.count)
    }

    /// Removes a journey; the ones after it move up. The first can only go if there's another to take its place.
    public static func removeJourney(_ index: Int, from options: inout [String: String]) {
        var list = journeys(options)
        guard list.indices.contains(index), list.count > 1 else { return }
        list.remove(at: index)
        for i in 0..<maxJourneys { for k in keys { options[key(k, i)] = nil } }
        for (i, q) in list.enumerated() { q.write(into: &options, index: i) }
    }

    public var isReady: Bool { from.count == 3 }

    /// "Reading to London Paddington".
    public var title: String {
        to.isEmpty ? TrainStation.name(for: from) : "\(TrainStation.name(for: from)) to \(TrainStation.name(for: to))"
    }

    /// What to call it on the tile: your name for it, or the stations with "fast" or "stopping" if it's only those.
    public var name: String {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return label }
        switch speed {
        case .all: return title
        case .fast: return "\(title) (fast)"
        case .stopping: return "\(title) (stopping)"
        }
    }
}

public struct TrainRow: Hashable, Sendable, Identifiable {
    public var departure: TrainDeparture
    /// Faster than the stopping trains on the same board.
    public var isFast: Bool
    public var arrival: String?
    public var stops: Int?
    public var journeyMinutes: Int?
    public var id: String { departure.id }
}

public enum Trains {
    public static let host = "api1.raildata.org.uk"

    /// The address to ask for a station's departures, with where each train stops. Carries only station codes.
    public static func url(for query: TrainQuery, rows: Int = 16, details: Bool = true) -> URL? {
        guard query.isReady, query.from.allSatisfy({ $0.isLetter && $0.isASCII }) else { return nil }
        var c = URLComponents()
        c.scheme = "https"
        c.host = host
        c.path = "/1010-live-departure-board-dep1_2/LDBWS/api/20220120/\(details ? "GetDepBoardWithDetails" : "GetDepartureBoard")/\(query.from)"
        var items = [URLQueryItem(name: "numRows", value: "\(min(details ? 10 : 20, max(1, rows)))"), URLQueryItem(name: "timeWindow", value: "120")]
        if query.to.count == 3, query.to.allSatisfy({ $0.isLetter && $0.isASCII }) {
            items.append(URLQueryItem(name: "filterCrs", value: query.to))
            items.append(URLQueryItem(name: "filterType", value: "to"))
        }
        c.queryItems = items
        return c.url
    }

    /// Reads the feed's reply. Anything missing is left out rather than failing the whole board.
    public static func parse(_ data: Data) throws -> TrainBoard {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TrainError.unreadable
        }
        func text(_ v: Any?) -> String? {
            if let s = v as? String { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
            if let n = v as? NSNumber { return n.stringValue }
            return nil
        }
        func flag(_ v: Any?) -> Bool { (v as? Bool) ?? (v as? NSNumber)?.boolValue ?? false }
        func whole(_ v: Any?) -> Int? { (v as? Int) ?? (v as? NSNumber)?.intValue ?? (v as? String).flatMap { Int($0) } }
        func calls(_ v: Any?) -> [TrainCall] {
            // The feed nests the stops one level down ("callingPoint"); a train that splits has several lists, and the
            // first is the main one.
            var points: [[String: Any]] = []
            if let lists = v as? [[String: Any]] {
                if let inner = lists.first?["callingPoint"] as? [[String: Any]] { points = inner }
                else if lists.first?["crs"] != nil { points = lists }
            }
            return points.compactMap { p in
                guard let crs = text(p["crs"]), let st = text(p["st"]) else { return nil }
                return TrainCall(name: text(p["locationName"]) ?? crs, crs: crs.uppercased(), scheduled: st, expected: text(p["et"]) ?? text(p["at"]))
            }
        }
        let services = (root["trainServices"] as? [[String: Any]]) ?? []
        let departures: [TrainDeparture] = services.enumerated().compactMap { i, s in
            guard let std = text(s["std"]) else { return nil }
            let destinations = (s["destination"] as? [[String: Any]])?.compactMap { text($0["locationName"]) } ?? []
            return TrainDeparture(
                id: text(s["serviceID"]) ?? text(s["serviceIdUrlSafe"]) ?? "\(i)-\(std)",
                scheduled: std, expected: text(s["etd"]) ?? "On time", platform: text(s["platform"]),
                operatorName: text(s["operator"]) ?? "", operatorCode: (text(s["operatorCode"]) ?? "").uppercased(),
                destination: destinations.isEmpty ? "Unknown" : destinations.joined(separator: " & "),
                cancelled: flag(s["isCancelled"]), calls: calls(s["subsequentCallingPoints"]),
                length: whole(s["length"]).flatMap { $0 > 0 ? $0 : nil })
        }
        let messages = ((root["nrccMessages"] as? [[String: Any]]) ?? []).compactMap { m in
            (text(m["Value"]) ?? text(m["value"]) ?? text(m["xhtmlMessage"])).map(plain)
        }
        return TrainBoard(station: text(root["locationName"]) ?? "", departures: departures, messages: messages)
    }

    /// Takes the HTML out of a station notice.
    static func plain(_ html: String) -> String {
        var out = "", inTag = false
        for ch in html {
            if ch == "<" { inTag = true } else if ch == ">" { inTag = false; out.append(" ") } else if !inTag { out.append(ch) }
        }
        return out.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&nbsp;", with: " ")
            .split(separator: " ").joined(separator: " ")
    }

    /// The trains a tile shows: the chosen operators' trains towards the chosen station, soonest first, with the fast
    /// ones marked. A train is "fast" when it gets there in at most four fifths of the slowest train's time (and at
    /// least four minutes quicker), which separates a non-stop service from one calling at every station.
    public static func rows(_ board: TrainBoard, query: TrainQuery, nowMinutes: Int) -> [TrainRow] {
        var list = board.departures
        if !query.to.isEmpty {
            // With stop details, keep only trains that really call there. Without them, trust the feed's own filter.
            list = list.filter { $0.calls.isEmpty || $0.call(at: query.to) != nil }
        }
        let slowest = list.compactMap { $0.journeyMinutes(to: query.to) }.max()
        var rows = list.map { d -> TrainRow in
            let journey = query.to.isEmpty ? nil : d.journeyMinutes(to: query.to)
            let fast = journey.map { j in slowest.map { j * 5 <= $0 * 4 && $0 - j >= 4 } ?? false } ?? false
            return TrainRow(departure: d, isFast: fast, arrival: query.to.isEmpty ? nil : d.arrival(at: query.to),
                            stops: query.to.isEmpty ? nil : d.stops(before: query.to), journeyMinutes: journey)
        }
        if !query.operators.isEmpty { rows = rows.filter { query.operators.contains($0.departure.operatorCode) } }
        switch query.speed {
        case .all: break
        case .fast: rows = rows.filter(\.isFast)
        case .stopping: rows = rows.filter { !$0.isFast }
        }
        return rows.filter { $0.departure.minutesUntil(nowMinutes: nowMinutes) >= -1 }
            .sorted { $0.departure.minutesUntil(nowMinutes: nowMinutes) < $1.departure.minutesUntil(nowMinutes: nowMinutes) }
    }

    /// "Non-stop", "1 stop", "6 stops".
    public static func stopsText(_ stops: Int) -> String {
        stops == 0 ? "Non-stop" : stops == 1 ? "1 stop" : "\(stops) stops"
    }

    /// The operators on a board, for the "which trains" choice: code and name, in name order.
    public static func operators(on board: TrainBoard) -> [(code: String, name: String)] {
        var seen: [String: String] = [:]
        for d in board.departures where !d.operatorCode.isEmpty { seen[d.operatorCode] = d.operatorName }
        return seen.map { ($0.key, $0.value) }.sorted { $0.1 < $1.1 }
    }
}

public enum TrainError: Error, Equatable {
    case unreadable
}
