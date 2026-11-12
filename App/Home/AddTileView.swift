import HomeKit
import MusicKit
import PlateCore
import SwiftUI

/// Picks what to put on the dashboard: scenes, accessories and rooms from HomeKit, Apple Music albums, and Plate's own
/// tiles. Things already on the dashboard are ticked.
struct AddTileView: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var home
    @Environment(\.dismiss) private var dismiss
    @State private var section: Section = .home

    enum Section: String, CaseIterable, Identifiable {
        case home = "Home", music = "Music", plate = "Plate"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Show", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()
                switch section {
                case .home: HomeTilePicker()
                case .music: AlbumPicker()
                case .plate: PlateTilePicker()
                }
            }
            .navigationTitle("Add to dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { home.start() }
    }
}

/// A row that adds the tile when tapped, or shows a tick if it's already there.
private struct AddRow: View {
    let tile: DashboardTile
    let symbol: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let added = model.household.dashboard.contains(tile.kind, ref: tile.ref) && tile.kind != .note
        Button {
            if added {
                if let existing = model.household.dashboard.tiles.first(where: { $0.kind == tile.kind && $0.ref == tile.ref }) {
                    model.household.dashboard.remove(existing.id)
                }
            } else {
                model.household.dashboard.add(tile)
            }
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading) {
                        Text(tile.title)
                        if let s = tile.subtitle { Text(s).font(.caption).foregroundStyle(.secondary) }
                    }
                } icon: { Image(systemName: symbol) }
                Spacer()
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(added ? Color.green : Color.accentColor)
            }
        }
        .foregroundStyle(.primary)
    }
}

private struct HomeTilePicker: View {
    @Environment(HomeStore.self) private var home

    var body: some View {
        List {
            switch home.status {
            case .notStarted, .loading:
                HStack { ProgressView(); Text("Looking for your home…").foregroundStyle(.secondary) }
            case .denied:
                Text("Plate isn't allowed to see your home. Turn it on in Settings → Privacy & Security → HomeKit.")
            case .noHome:
                Text("There's no home set up yet. Add your accessories in Apple's Home app, then come back here.")
            case .ready:
                if home.homes.count > 1 {
                    Picker("Home", selection: Binding(get: { home.home?.uniqueIdentifier.uuidString },
                                                      set: { home.homeId = $0 })) {
                        ForEach(home.homes, id: \.uniqueIdentifier) { h in
                            Text(h.name).tag(Optional(h.uniqueIdentifier.uuidString))
                        }
                    }
                }
                if !home.scenes.isEmpty {
                    SwiftUI.Section("Scenes") {
                        ForEach(home.scenes, id: \.uniqueIdentifier) { s in
                            AddRow(tile: DashboardTile(kind: .scene, ref: s.uniqueIdentifier.uuidString, title: s.name),
                                   symbol: SceneTile.symbol(for: s))
                        }
                    }
                }
                ForEach(home.rooms, id: \.uniqueIdentifier) { room in
                    SwiftUI.Section(room.name) {
                        AddRow(tile: DashboardTile(kind: .room, ref: room.uniqueIdentifier.uuidString, title: room.name,
                                                   subtitle: "Every light and plug in the room"),
                               symbol: "lightbulb.2")
                        ForEach(home.accessories(in: room), id: \.uniqueIdentifier) { a in
                            AddRow(tile: DashboardTile(kind: .accessory, ref: a.uniqueIdentifier.uuidString, title: a.name,
                                                       subtitle: room.name),
                                   symbol: home.state(of: a).symbol)
                        }
                    }
                }
            }
        }
    }
}

private struct AlbumPicker: View {
    @Environment(MusicStore.self) private var music
    @State private var term = ""
    @State private var results: [Album] = []
    @State private var library: [Album] = []

    var body: some View {
        List {
            switch music.status {
            case .authorized:
                SwiftUI.Section {
                    AddRow(tile: DashboardTile(kind: .nowPlaying, title: "Now playing", subtitle: "Play, pause, skip and AirPlay"),
                           symbol: "play.circle")
                }
                if !results.isEmpty {
                    SwiftUI.Section("Apple Music") { ForEach(results) { row($0) } }
                }
                if !library.isEmpty {
                    SwiftUI.Section("Your library") { ForEach(library) { row($0) } }
                }
            case .denied, .restricted:
                Text("Plate isn't allowed to use Apple Music. Turn it on in Settings → Privacy & Security → Media & Apple Music.")
            default:
                Button("Allow Apple Music") { Task { await music.authorise(); await loadLibrary() } }
            }
        }
        .searchable(text: $term, prompt: "Search Apple Music albums")
        .task(id: term) {
            try? await Task.sleep(for: .milliseconds(350))
            results = await music.search(term)
        }
        .task { if music.status == .notDetermined { await music.authorise() }; await loadLibrary() }
    }

    private func loadLibrary() async {
        if music.status == .authorized { library = await music.libraryAlbums() }
    }

    private func row(_ a: Album) -> some View {
        HStack(spacing: 12) {
            if let art = a.artwork { ArtworkImage(art, width: 44).clipShape(RoundedRectangle(cornerRadius: 6)) }
            AddRow(tile: DashboardTile(kind: .musicAlbum, ref: a.id.rawValue, title: a.title, subtitle: a.artistName),
                   symbol: "music.note")
        }
    }
}

private struct PlateTilePicker: View {
    @Environment(AppModel.self) private var model
    @State private var note = ""

    var body: some View {
        List {
            SwiftUI.Section {
                AddRow(tile: DashboardTile(kind: .clock, title: "Clock", subtitle: "Time and date"), symbol: "clock")
                AddRow(tile: DashboardTile(kind: .todaysMeals, title: "Today's meals", subtitle: "From the meal plan"),
                       symbol: "fork.knife")
                AddRow(tile: DashboardTile(kind: .shoppingList, title: "Shopping list", subtitle: "What's left to buy"),
                       symbol: "cart")
                AddRow(tile: DashboardTile(kind: .useSoon, title: "Use soon", subtitle: "Food going off in the next few days"),
                       symbol: "clock.badge.exclamationmark")
            }
            SwiftUI.Section {
                TextField("Bins out Thursday", text: $note, axis: .vertical)
                Button("Add note") {
                    model.household.dashboard.add(DashboardTile(kind: .note, title: "Note",
                                                                subtitle: note.trimmingCharacters(in: .whitespacesAndNewlines)))
                    note = ""
                }
                .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: { Text("A note") } footer: { Text("Shown on a yellow tile. Remove it in edit mode when it's done.") }
        }
    }
}
