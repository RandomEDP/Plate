import MusicKit
import Observation
import PlateCore
import SwiftUI

/// Live departures for the trains tiles, from National Rail's Live Departure Board through the Rail Data Marketplace.
/// The key is the user's own (free) and lives in this device's keychain; requests carry only station codes.
@MainActor
@Observable
final class TrainStore {
    static let shared = TrainStore()
    static let keyAccount = "rail-data-key"

    struct Entry {
        var board: TrainBoard?
        var problem: String?
        var fetched: Date?
    }

    private(set) var entries: [String: Entry] = [:]
    private(set) var hasKey = SecretStore.get(TrainStore.keyAccount) != nil
    @ObservationIgnored private var loading = Set<String>()
    /// Whether the fuller reply (with each train's stops) is available on this key. Tried first, remembered if not.
    @ObservationIgnored private var detailsWork = true

    static func id(_ q: TrainQuery) -> String { "\(q.from)>\(q.to)" }

    func entry(_ q: TrainQuery) -> Entry { entries[Self.id(q)] ?? Entry() }

    func setKey(_ key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        SecretStore.set(Self.keyAccount, k.isEmpty ? nil : k)
        hasKey = !k.isEmpty
        detailsWork = true
        entries = [:]
    }

    /// Fetches a board unless it was fetched in the last 40 seconds.
    func refresh(_ q: TrainQuery, force: Bool = false) async {
        let id = Self.id(q)
        guard q.isReady, !loading.contains(id) else { return }
        if !force, let at = entries[id]?.fetched, Date().timeIntervalSince(at) < 40 { return }
        guard let key = SecretStore.get(Self.keyAccount) else {
            hasKey = false
            return
        }
        loading.insert(id)
        defer { loading.remove(id) }
        var entry = entries[id] ?? Entry()
        do {
            var result = try await fetch(q, key: key, details: detailsWork)
            if result.status == 404 || result.status == 400, detailsWork {
                // This key's product doesn't include the detailed board: use the plain one (no arrival times).
                detailsWork = false
                result = try await fetch(q, key: key, details: false)
            }
            switch result.status {
            case 200:
                entry.board = try Trains.parse(result.data)
                entry.problem = nil
            case 401, 403:
                entry.problem = "National Rail didn't accept the key. Check it's the consumer key for “Live Departure Board” and that the subscription is active."
            case 429:
                entry.problem = "Too many requests for now. It'll try again shortly."
            default:
                entry.problem = "National Rail's feed answered with error \(result.status). It'll try again shortly."
            }
        } catch is TrainError {
            entry.problem = "National Rail's feed sent something Plate couldn't read. It'll try again shortly."
        } catch {
            entry.problem = "Couldn't reach National Rail: \(error.localizedDescription)"
        }
        entry.fetched = Date()
        entries[id] = entry
    }

    private func fetch(_ q: TrainQuery, key: String, details: Bool) async throws -> (data: Data, status: Int) {
        guard let url = Trains.url(for: q, details: details) else { throw TrainError.unreadable }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(key, forHTTPHeaderField: "x-apikey")
        request.setValue("Plate iOS app", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// The time of day on the railway's clock, as minutes after midnight.
    static func nowMinutes(_ date: Date = Date()) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        let c = cal.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

struct TrainTile: View {
    let tile: DashboardTile
    @Environment(\.dashStyle) private var style
    private var store: TrainStore { TrainStore.shared }

    var body: some View {
        let all = TrainQuery.journeys(tile.options).filter(\.isReady)
        // A small tile only has room for the first journey.
        let journeys = tile.size == .small ? Array(all.prefix(1)) : all
        let single = journeys.count <= 1
        TileCard {
            VStack(alignment: .leading, spacing: 7) {
                TileHeader(title: tile.name(single ? (journeys.first?.name ?? "Trains") : "Trains"), symbol: "tram.fill")
                if journeys.isEmpty {
                    hint("Edit this tile to choose the station and which trains to show.")
                } else if !store.hasKey {
                    hint("Edit this tile and add a free National Rail key to see live trains.")
                } else if single, let q = journeys.first {
                    section(q, count: rowsEach(1), compact: tile.size == .small)
                } else if tile.size == .wide {
                    // Side by side on a wide tile: just the times.
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(journeys.enumerated()), id: \.offset) { _, q in
                            VStack(alignment: .leading, spacing: 5) {
                                heading(q)
                                section(q, count: 2, compact: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    ForEach(Array(journeys.enumerated()), id: \.offset) { i, q in
                        if i > 0 { Divider().opacity(0.4) }
                        heading(q)
                        section(q, count: rowsEach(journeys.count), compact: false)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .task(id: journeys.map(TrainStore.id).joined(separator: "|") + (store.hasKey ? "k" : "")) {
            // Fresh every minute while the tile is on screen. Journeys from the same station share one request.
            while !Task.isCancelled {
                for q in journeys { await store.refresh(q) }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func rowsEach(_ journeys: Int) -> Int {
        switch tile.size {
        case .small: return 1
        case .wide: return journeys == 1 ? 2 : 1
        case .tall: return journeys == 1 ? 5 : journeys == 2 ? 3 : 2
        case .large: return journeys == 1 ? 5 : journeys == 2 ? 3 : 2
        }
    }

    private func heading(_ q: TrainQuery) -> some View {
        Text(q.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
    }

    @ViewBuilder private func section(_ query: TrainQuery, count: Int, compact: Bool) -> some View {
        let entry = store.entry(query)
        if let board = entry.board {
            TimelineView(.periodic(from: .now, by: 20)) { ctx in
                let now = TrainStore.nowMinutes(ctx.date)
                let rows = Trains.rows(board, query: query, nowMinutes: now)
                VStack(alignment: .leading, spacing: 7) {
                    if rows.isEmpty { hint("No trains in the next two hours.") }
                    ForEach(rows.prefix(count)) { r in row(r, now: now, compact: compact) }
                }
            }
            if let problem = entry.problem, !compact {
                Text(problem).font(.caption2).foregroundStyle(.orange).lineLimit(2)
            }
        } else if let problem = entry.problem {
            hint(problem)
        } else {
            ProgressView()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ r: TrainRow, now: Int, compact: Bool) -> some View {
        let d = r.departure
        let late = d.minutesLate != 0
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(d.leaves).font(.headline.monospacedDigit())
                    .foregroundStyle(d.isCancelled ? Color.red : late ? Color.orange : Color.primary)
                    .strikethrough(d.isCancelled)
                if late && !d.isCancelled && d.leaves != d.scheduled {
                    Text(d.scheduled).font(.caption2.monospacedDigit()).strikethrough().foregroundStyle(.secondary)
                }
            }
            .frame(width: 50, alignment: .leading)
            if !compact {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(d.destination).font(.subheadline.weight(.medium)).lineLimit(1)
                        if r.isFast {
                            Text("FAST").font(.caption2.weight(.heavy)).padding(.horizontal, 5).padding(.vertical, 1)
                                .background(style.accent.color, in: Capsule())
                                .foregroundStyle(style.accent.wantsDarkText ? Color.black : Color.white)
                        }
                    }
                    Text(detail(r)).font(.caption).foregroundStyle(d.isCancelled ? Color.red : Color.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 0) {
                Text(d.isCancelled ? "–" : TrainTime.countdown(d.minutesUntil(nowMinutes: now)))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                if let p = d.platform { Text("Plat \(p)").font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }

    /// "Greater Anglia · Non-stop · arrives 10:34".
    private func detail(_ r: TrainRow) -> String {
        if r.departure.isCancelled { return "Cancelled" }
        var parts = [r.departure.operatorName]
        if r.departure.status != "On time" { parts.insert(r.departure.status, at: 0) }
        if let s = r.stops { parts.append(Trains.stopsText(s)) }
        if let a = r.arrival { parts.append("arrives \(a)") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// The trains tile's settings: up to three journeys (station, direction, operators, fast or stopping) and the key.
struct TrainSettings: View {
    @Binding var options: [String: String]
    @State private var key = ""
    @State private var savedKey = TrainStore.shared.hasKey
    private var store: TrainStore { TrainStore.shared }

    var body: some View {
        let journeys = TrainQuery.journeys(options)
        ForEach(journeys.indices, id: \.self) { i in
            journey(i, count: journeys.count)
        }
        if journeys.count < TrainQuery.maxJourneys, journeys.last?.isReady == true {
            Section {
                Button("Add another journey", systemImage: "plus.circle") { TrainQuery.addJourney(to: &options) }
            } footer: {
                Text("A tile can show up to three, one under another: say Romford fast trains, Romford stopping trains and the Elizabeth line from Gidea Park.")
            }
        }
        Section {
            if savedKey {
                Label("Key saved on this device", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                Button("Remove the key", role: .destructive) { store.setKey(""); savedKey = false }
            } else {
                SecureField("Consumer key", text: $key).autocorrectionDisabled().textInputAutocapitalization(.never)
                Button("Save key") { store.setKey(key); key = ""; savedKey = store.hasKey }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                Link("Get a free key at raildata.org.uk", destination: URL(string: "https://raildata.org.uk")!)
            }
        } header: { Text("National Rail key") } footer: {
            Text("Live times come from National Rail, which needs a free key: sign up at raildata.org.uk, subscribe to “Live Departure Board”, and paste its consumer key here. It's kept in this device's keychain and used for every trains tile.")
        }
    }

    private func query(_ i: Int) -> Binding<TrainQuery> {
        Binding(get: { TrainQuery(options: options, index: i) }, set: { $0.write(into: &options, index: i) })
    }

    @ViewBuilder private func journey(_ i: Int, count: Int) -> some View {
        let q = query(i)
        Section {
            TextField("Name, such as Romford fast", text: q.label)
            NavigationLink {
                StationPicker(title: "Leaving from", allowAny: false, selection: q.from)
            } label: { labelled("From", q.wrappedValue.from.isEmpty ? "Choose" : TrainStation.name(for: q.wrappedValue.from)) }
            NavigationLink {
                StationPicker(title: "Trains calling at", allowAny: true, selection: q.to)
            } label: { labelled("Only trains to", q.wrappedValue.to.isEmpty ? "Anywhere" : TrainStation.name(for: q.wrappedValue.to)) }
            NavigationLink {
                OperatorPicker(query: q)
            } label: { labelled("Operators", operatorsText(q.wrappedValue)) }
            Picker("Trains", selection: q.speed) {
                ForEach(TrainSpeed.allCases) { Text($0.title).tag($0) }
            }
            if count > 1 {
                Button("Remove this journey", role: .destructive) { TrainQuery.removeJourney(i, from: &options) }
            }
        } header: {
            Text(count > 1 ? "Journey \(i + 1)" : "Journey")
        } footer: {
            if i == 0 {
                Text("For trains into London, choose the London station they end up at. Fast trains are then marked, with when each one arrives. “Stopping trains only” leaves the fast ones out.")
            }
        }
        .task(id: TrainStore.id(q.wrappedValue)) { await store.refresh(q.wrappedValue) }
    }

    private func operatorsText(_ q: TrainQuery) -> String {
        if q.operators.isEmpty { return "Every operator" }
        return q.operators.sorted().map { TrainSettings.operatorNames[$0] ?? $0 }.joined(separator: ", ")
    }

    static let operatorNames = ["XR": "Elizabeth line", "LE": "Greater Anglia", "GW": "Great Western Railway", "CC": "c2c", "LO": "London Overground"]

    private func labelled(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary).lineLimit(1) }
    }
}

/// Choose whose trains a journey shows. The list fills in from the station's board once it has loaded.
struct OperatorPicker: View {
    @Binding var query: TrainQuery
    private var store: TrainStore { TrainStore.shared }

    var body: some View {
        List {
            Button { query.operators = [] } label: { tick("Every operator", query.operators.isEmpty) }.foregroundStyle(.primary)
            ForEach(operators(query), id: \.code) { op in
                Button {
                    if query.operators.contains(op.code) { query.operators.remove(op.code) } else { query.operators.insert(op.code) }
                } label: { tick(op.name, query.operators.contains(op.code)) }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("Operators")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.refresh(query) }
    }

    private func operators(_ q: TrainQuery) -> [(code: String, name: String)] {
        var list = store.entry(q).board.map(Trains.operators(on:)) ?? []
        // Operators already chosen stay in the list even when none of their trains are on the board right now.
        for code in q.operators.sorted() where !list.contains(where: { $0.code == code }) {
            list.append((code, TrainSettings.operatorNames[code] ?? code))
        }
        if list.isEmpty { list = [("XR", "Elizabeth line"), ("LE", "Greater Anglia")] }
        return list
    }

    private func tick(_ title: String, _ on: Bool) -> some View {
        HStack { Text(title); Spacer(); if on { Image(systemName: "checkmark").foregroundStyle(.tint) } }
    }
}

struct StationPicker: View {
    let title: String
    let allowAny: Bool
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""

    var body: some View {
        List {
            if allowAny && term.isEmpty {
                Button { selection = ""; dismiss() } label: { Text("Anywhere (every departure)") }.foregroundStyle(.primary)
            }
            ForEach(TrainStation.search(term)) { s in
                Button { selection = s.crs; dismiss() } label: {
                    HStack {
                        Text(s.name)
                        Spacer()
                        Text(s.crs).font(.caption.monospaced()).foregroundStyle(.secondary)
                        if s.crs == selection { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .searchable(text: $term, placement: .navigationBarDrawer(displayMode: .always), prompt: "Station name or three-letter code")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Choosing music for a tile

/// Search your library and all of Apple Music for an album, playlist or station to put on a tile.
struct MusicPickerView: View {
    let onPick: (MusicStore.Found) -> Void
    @Environment(MusicStore.self) private var music
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var results: [MusicStore.Found] = []
    @State private var searching = false

    var body: some View {
        List {
            switch music.status {
            case .authorized:
                if term.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Type an album, artist, playlist or station. It searches your library and the whole of Apple Music.")
                        .foregroundStyle(.secondary)
                } else if results.isEmpty {
                    if searching { HStack { ProgressView(); Text("Searching…").foregroundStyle(.secondary) } }
                    else { Text("Nothing found for “\(term)”.").foregroundStyle(.secondary) }
                }
                ForEach(results) { f in
                    Button { onPick(f); dismiss() } label: {
                        HStack(spacing: 12) {
                            if let art = f.artwork {
                                ArtworkImage(art, width: 46).clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: f.type == "station" ? "dot.radiowaves.left.and.right" : "music.note").frame(width: 46, height: 46)
                            }
                            VStack(alignment: .leading) {
                                Text(f.title).lineLimit(1)
                                Text(f.detail + (f.inLibrary ? " · in your library" : "")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            case .denied, .restricted:
                Text("Plate isn't allowed to use Apple Music. Turn it on in Settings → Privacy & Security → Media & Apple Music.")
            default:
                Button("Allow Apple Music") { Task { await music.authorise() } }
            }
        }
        .searchable(text: $term, placement: .navigationBarDrawer(displayMode: .always), prompt: "Albums, playlists, stations")
        .navigationTitle("Choose music")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: term) {
            searching = true
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            results = await music.searchEverything(term)
            searching = false
        }
        .task { if music.status == .notDetermined { await music.authorise() } }
    }
}

extension DashboardTile {
    /// Points this tile at the chosen music.
    mutating func setMusic(_ f: MusicStore.Found) {
        kind = f.type == nil ? .musicAlbum : .playlist
        ref = f.id
        title = f.title
        subtitle = f.detail
        options["type"] = f.type
    }
}
