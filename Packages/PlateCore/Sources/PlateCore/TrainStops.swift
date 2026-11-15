import Foundation

// One train's stops, for the view you get by tapping a train on the trains tile: where it has been (when the fuller
// reply has that), the station it was tapped at, and every stop after, each with its timetabled time, the time it's
// now expected (or really got there), and whether it's late or cancelled.

public struct TrainStop: Hashable, Sendable, Identifiable {
    public enum Place: Hashable, Sendable { case before, here, after }

    public enum State: Hashable, Sendable {
        case onTime
        case late(Int)
        case delayed
        case cancelled
        case noReport
    }

    /// Position and code, as a train can call at a station twice (a loop).
    public var id: String
    public var name: String
    public var crs: String
    public var place: Place
    /// Timetabled, "HH:mm".
    public var scheduled: String
    /// The best time to show, "HH:mm": when it really got there, else the new expected time, else the timetable.
    public var time: String
    public var state: State
    /// It has already been here (the feed gave a real time).
    public var been: Bool
    /// Only known for the station the train was tapped at.
    public var platform: String?
    /// The station the tile's journey is going to.
    public var isJourneyEnd: Bool

    public var isCancelled: Bool { state == .cancelled }
    /// The timetabled time, for crossing out, when it's different from `time`.
    public var oldTime: String? { time != scheduled && !isCancelled ? scheduled : nil }

    /// "On time", "3 min late", "Delayed", "Cancelled", "No report"; "Left on time" or "Left 3 min late" once it's been.
    public var status: String {
        let word: String
        switch state {
        case .onTime: word = "On time"
        case .late(let m): word = "\(m) min late"
        case .delayed: return "Delayed"
        case .cancelled: return "Cancelled"
        case .noReport: return "No report"
        }
        guard been else { return word }
        return place == .before || place == .here ? "Left \(word.prefix(1).lowercased() + word.dropFirst())"
                                                    : "Arrived \(word.prefix(1).lowercased() + word.dropFirst())"
    }
}

public enum TrainStops {
    /// The state of a stop from the feed's words: a new time, "On time", "Delayed", "Cancelled" or "No report".
    public static func state(scheduled: String, reported: String?, cancelled: Bool) -> TrainStop.State {
        if cancelled { return .cancelled }
        guard let r = reported?.trimmingCharacters(in: .whitespaces), !r.isEmpty else { return .onTime }
        switch r.lowercased() {
        case "cancelled": return .cancelled
        case "delayed": return .delayed
        case "no report": return .noReport
        case "on time": return .onTime
        default: break
        }
        guard let t = TrainTime.minutes(r), let s = TrainTime.minutes(scheduled) else { return .onTime }
        let late = TrainTime.signed(from: s, to: t)
        return late > 0 ? .late(late) : .onTime
    }

    /// Every stop in order. `crs` is the station the train was tapped at; `to` the tile journey's end, if it has one.
    public static func list(_ d: TrainDeparture, station: String, crs: String, to: String = "") -> [TrainStop] {
        let end = to.uppercased()
        var out: [TrainStop] = []
        func add(_ c: TrainCall, _ place: TrainStop.Place) {
            let reported = c.actual ?? c.expected
            let state = state(scheduled: c.scheduled, reported: reported, cancelled: c.cancelled)
            let time = reported.flatMap { TrainTime.minutes($0) != nil ? $0 : nil } ?? c.scheduled
            out.append(TrainStop(id: "\(out.count)-\(c.crs)", name: c.name, crs: c.crs, place: place, scheduled: c.scheduled,
                                 time: time, state: state, been: c.actual != nil, platform: nil,
                                 isJourneyEnd: place == .after && !end.isEmpty && c.crs == end))
        }
        for c in d.previous { add(c, .before) }
        let hereState = state(scheduled: d.scheduled, reported: d.expected, cancelled: d.isCancelled)
        out.append(TrainStop(id: "\(out.count)-\(crs.uppercased())", name: station.isEmpty ? TrainStation.name(for: crs) : station,
                             crs: crs.uppercased(), place: .here, scheduled: d.scheduled, time: d.leaves, state: hereState,
                             been: false, platform: d.platform, isJourneyEnd: false))
        for c in d.calls { add(c, .after) }
        // Only the first visit to the journey's end counts.
        if let first = out.firstIndex(where: \.isJourneyEnd) {
            for i in out.indices where i != first { out[i].isJourneyEnd = false }
        }
        return out
    }

    /// Where the train last reported from, among the stops before this station ("Last seen at Shenfield, 12:31").
    public static func lastSeen(_ stops: [TrainStop]) -> TrainStop? {
        stops.last { $0.place == .before && $0.been }
    }

    /// "Calls at 10 stations · gets to London Paddington at 13:12 · 35 min".
    public static func summary(_ d: TrainDeparture, to: String = "") -> String {
        var parts: [String] = []
        let count = d.calls.count
        if count > 0 { parts.append(count == 1 ? "Calls at 1 station" : "Calls at \(count) stations") }
        let end = to.isEmpty ? d.calls.last?.crs : to
        if let end, let call = d.call(at: end), let at = d.arrival(at: end) {
            parts.append("gets to \(call.name) at \(at)")
            if let j = d.journeyMinutes(to: end) { parts.append(j < 60 ? "\(j) min" : "\(j / 60) h \(j % 60) min") }
        }
        if let n = d.length { parts.append("\(n) carriages") }
        return parts.joined(separator: " · ")
    }
}
