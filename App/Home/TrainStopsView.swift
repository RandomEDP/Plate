import PlateCore
import SwiftUI

/// The train tapped on a trains tile.
struct PickedTrain: Identifiable {
    var query: TrainQuery
    /// The board's station name ("Romford").
    var station: String
    var departure: TrainDeparture
    var id: String { departure.id }
}

/// Every stop one train makes, with timetabled and expected times, kept live while it's open. Uses the train's whole
/// run when the key covers National Rail's Service Details, otherwise the stops from the departure board.
struct TrainStopsView: View {
    let picked: PickedTrain
    @State private var full: TrainDeparture?
    @Environment(\.dismiss) private var dismiss
    private var store: TrainStore { TrainStore.shared }

    /// The freshest copy of the train: its full run if we have it, else today's board, else what was tapped.
    private var train: TrainDeparture {
        if let full { return full }
        return store.entry(picked.query).board?.departures.first { $0.id == picked.id } ?? picked.departure
    }

    var body: some View {
        let d = train
        let stops = TrainStops.list(d, station: picked.station, crs: picked.query.from, to: picked.query.to)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(d, stops: stops)
                    VStack(spacing: 0) {
                        ForEach(Array(stops.enumerated()), id: \.element.id) { i, stop in
                            StopRow(stop: stop, first: i == 0, last: i == stops.count - 1)
                        }
                    }
                    .padding(.vertical, 8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
                    Text(d.previous.isEmpty
                         ? "Times update every half a minute. Live from National Rail."
                         : "Times update every half a minute. Greyed stops are ones it has already been to. Live from National Rail.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("\(d.scheduled) to \(d.destination)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task {
            while !Task.isCancelled {
                if let f = await store.service(picked.id) { full = f }
                await store.refresh(picked.query)
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    @ViewBuilder private func header(_ d: TrainDeparture, stops: [TrainStop]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(d.leaves).font(.largeTitle.weight(.bold).monospacedDigit())
                    .foregroundStyle(d.isCancelled ? Color.red : d.minutesLate != 0 ? Color.orange : Color.primary)
                    .strikethrough(d.isCancelled)
                VStack(alignment: .leading, spacing: 0) {
                    Text(d.destination).font(.title3.weight(.semibold)).lineLimit(2)
                    Text([d.operatorName, d.status].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(d.isCancelled ? Color.red : Color.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    TimelineView(.periodic(from: .now, by: 20)) { ctx in
                        Text(d.isCancelled ? "–" : TrainTime.countdown(d.minutesUntil(nowMinutes: TrainStore.nowMinutes(ctx.date))))
                            .font(.title3.weight(.semibold).monospacedDigit())
                    }
                    if let p = d.platform { Text("Platform \(p)").font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            let summary = TrainStops.summary(d, to: picked.query.to)
            if !summary.isEmpty { Text(summary).font(.subheadline).foregroundStyle(.secondary) }
            if let seen = TrainStops.lastSeen(stops) {
                Label("Last reported at \(seen.name), \(seen.time)", systemImage: "location.fill")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let reason = d.reason {
                Label(reason, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.orange)
            }
        }
    }
}

/// One stop: a line down the left joining the stops, the time, the station and how it's running.
private struct StopRow: View {
    let stop: TrainStop
    let first: Bool
    let last: Bool

    var body: some View {
        let big = stop.place == .here || stop.isJourneyEnd || last
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(stop.time).font((big ? Font.headline : .body).monospacedDigit())
                    .foregroundStyle(timeColour).strikethrough(stop.isCancelled)
                if let old = stop.oldTime {
                    Text(old).font(.caption2.monospacedDigit()).strikethrough().foregroundStyle(.secondary)
                }
            }
            .frame(width: 58, alignment: .trailing)
            Circle()
                .strokeBorder(stop.isCancelled ? Color.red : stop.been ? Color.secondary : Color.accentColor, lineWidth: 3)
                .background(Circle().fill(stop.place == .here || stop.isJourneyEnd ? Color.accentColor : Color(.secondarySystemBackground)))
                .frame(width: big ? 16 : 11, height: big ? 16 : 11)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(stop.name).font(big ? .headline : .body).lineLimit(2)
                Text(statusLine).font(.caption).foregroundStyle(statusColour)
            }
            Spacer(minLength: 4)
            if let p = stop.platform {
                Text("Plat \(p)").font(.caption.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.tint.opacity(0.18), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 50)
        .background(alignment: .topLeading) {
            // The line joining the stops runs behind the dots: 12 padding + 58 time + 12 gap + half the dot column.
            VStack(spacing: 0) {
                Rectangle().fill(first ? Color.clear : lineColour)
                Rectangle().fill(last ? Color.clear : lineColour)
            }
            .frame(width: 3)
            .padding(.leading, 12 + 58 + 12 + 9 - 1.5)
        }
        .opacity(stop.been ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    private var statusLine: String {
        var parts: [String] = []
        if stop.place == .here { parts.append("You're here") }
        if stop.isJourneyEnd { parts.append("Your stop") }
        parts.append(stop.status)
        return parts.joined(separator: " · ")
    }

    private var lineColour: Color { stop.been ? Color.secondary.opacity(0.5) : Color.accentColor.opacity(0.6) }

    private var timeColour: Color {
        switch stop.state {
        case .cancelled: return .red
        case .late, .delayed: return .orange
        default: return .primary
        }
    }

    private var statusColour: Color {
        switch stop.state {
        case .cancelled: return .red
        case .late, .delayed: return .orange
        case .noReport: return .secondary
        case .onTime: return stop.been ? .secondary : .green
        }
    }
}
