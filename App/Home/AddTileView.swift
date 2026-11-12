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
    /// The page new tiles go on (nil when the dashboard has a single page).
    var page: UUID?
    /// The folder new tiles go into, when adding from inside one.
    var folder: UUID?

    enum Section: String, CaseIterable, Identifiable {
        case home = "Home", music = "Music", plate = "Kitchen", more = "More"
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
                case .more: MoreTilePicker()
                }
            }
            .environment(\.addToPage, page)
            .environment(\.addToFolder, folder)
            .navigationTitle("Add to dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { home.start() }
    }
}

/// A row that adds the tile when tapped, or shows a tick if it's already there.
private struct AddToPageKey: EnvironmentKey { static let defaultValue: UUID? = nil }
private struct AddToFolderKey: EnvironmentKey { static let defaultValue: UUID? = nil }
extension EnvironmentValues {
    var addToFolder: UUID? {
        get { self[AddToFolderKey.self] }
        set { self[AddToFolderKey.self] = newValue }
    }
    var addToPage: UUID? {
        get { self[AddToPageKey.self] }
        set { self[AddToPageKey.self] = newValue }
    }
}

private struct AddRow: View {
    let tile: DashboardTile
    let symbol: String
    @Environment(AppModel.self) private var model
    @Environment(\.addToPage) private var page
    @Environment(\.addToFolder) private var folder

    var body: some View {
        let added = model.household.dashboard.contains(tile.kind, ref: tile.ref) && !tile.kind.canRepeat && !(tile.kind.needsRef && tile.ref == nil)
        Button {
            if added {
                if let existing = model.household.dashboard.tiles.first(where: { $0.kind == tile.kind && $0.ref == tile.ref }) {
                    model.household.dashboard.remove(existing.id)
                }
            } else {
                var t = tile
                // A fresh id every tap: this row can stay on screen and be tapped again to add another.
                t.id = UUID()
                t.pageId = page
                if t.kind != .folder { t.folderId = folder }
                // The description under the row is for choosing; it isn't shown on these tiles.
                if !t.kind.needsRef && t.kind != .note { t.subtitle = nil }
                model.household.dashboard.add(t)
                Feedback.shared.play(.tap)
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
                SwiftUI.Section("Whole home") {
                    AddRow(tile: DashboardTile(kind: .allOff, title: "All lights", subtitle: "How many are on, and one tap for all off"), symbol: "lightbulb.slash")
                    AddRow(tile: DashboardTile(kind: .climate, title: "Climate", subtitle: "Temperature and humidity from every sensor"), symbol: "thermometer.medium")
                    AddRow(tile: DashboardTile(kind: .battery, title: "Batteries", subtitle: "Warns when an accessory's battery is low"), symbol: "battery.25")
                    AddRow(tile: DashboardTile(kind: .group, title: "Switch together", subtitle: "Several lights or plugs you choose, on and off with one tap"), symbol: "square.grid.2x2")
                    AddRow(tile: DashboardTile(kind: .activity, title: "Recently", subtitle: "What's been switched from the dashboard"), symbol: "clock.arrow.circlepath")
                    ForEach(LightShow.allCases) { show in
                        AddRow(tile: DashboardTile(kind: .lightShow, title: show.title, subtitle: "Light show for colour bulbs", options: ["show": show.rawValue]),
                               symbol: show.icon)
                    }
                }
                if !home.cameras.isEmpty {
                    SwiftUI.Section("Cameras") {
                        ForEach(home.cameras, id: \.uniqueIdentifier) { c in
                            AddRow(tile: DashboardTile(kind: .camera, ref: c.uniqueIdentifier.uuidString, title: c.name, subtitle: c.room?.name),
                                   symbol: "video")
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
    @State private var playlists: [Playlist] = []
    @State private var foundPlaylists: [Playlist] = []
    @State private var stations: [Station] = []

    var body: some View {
        List {
            switch music.status {
            case .authorized:
                SwiftUI.Section {
                    AddRow(tile: DashboardTile(kind: .nowPlaying, title: "Now playing", subtitle: "Play, pause, skip and AirPlay"),
                           symbol: "play.circle")
                    AddRow(tile: DashboardTile(kind: .musicAlbum, title: "Music tile", subtitle: "Add it empty, then tap it to search all of Apple Music"),
                           symbol: "plus.square.dashed")
                }
                if !results.isEmpty {
                    SwiftUI.Section("Apple Music") { ForEach(results) { row($0) } }
                }
                if !foundPlaylists.isEmpty {
                    SwiftUI.Section("Playlists") { ForEach(foundPlaylists) { playlistRow($0) } }
                }
                if !stations.isEmpty {
                    SwiftUI.Section("Stations") {
                        ForEach(stations) { s in
                            AddRow(tile: DashboardTile(kind: .playlist, ref: s.id.rawValue, title: s.name, subtitle: "Station", options: ["type": "station"]),
                                   symbol: "dot.radiowaves.left.and.right")
                        }
                    }
                }
                if !playlists.isEmpty {
                    SwiftUI.Section("Your playlists") { ForEach(playlists) { playlistRow($0) } }
                }
                if !library.isEmpty {
                    SwiftUI.Section("Your albums") { ForEach(library) { row($0) } }
                }
            case .denied, .restricted:
                Text("Plate isn't allowed to use Apple Music. Turn it on in Settings → Privacy & Security → Media & Apple Music.")
            default:
                Button("Allow Apple Music") { Task { await music.authorise(); await loadLibrary() } }
            }
        }
        .searchable(text: $term, prompt: "Search albums, playlists and stations")
        .task(id: term) {
            try? await Task.sleep(for: .milliseconds(350))
            if Task.isCancelled { return }
            results = await music.search(term)
            let more = await music.searchPlaylists(term)
            foundPlaylists = more.playlists
            stations = more.stations
        }
        .task { if music.status == .notDetermined { await music.authorise() }; await loadLibrary() }
    }

    private func loadLibrary() async {
        if music.status == .authorized {
            library = await music.libraryAlbums()
            playlists = await music.libraryPlaylists()
        }
    }

    private func playlistRow(_ p: Playlist) -> some View {
        HStack(spacing: 12) {
            if let art = p.artwork { ArtworkImage(art, width: 44).clipShape(RoundedRectangle(cornerRadius: 6)) }
            AddRow(tile: DashboardTile(kind: .playlist, ref: p.id.rawValue, title: p.name, subtitle: p.curatorName ?? "Playlist",
                                       options: ["type": "playlist"]),
                   symbol: "music.note.list")
        }
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
                AddRow(tile: DashboardTile(kind: .todaysMeals, title: "Today's meals", subtitle: "From the meal plan"),
                       symbol: "fork.knife")
                AddRow(tile: DashboardTile(kind: .shoppingList, title: "Shopping list", subtitle: "What's left to buy"),
                       symbol: "cart")
                AddRow(tile: DashboardTile(kind: .useSoon, title: "Use soon", subtitle: "Food going off in the next few days"),
                       symbol: "clock.badge.exclamationmark")
                AddRow(tile: DashboardTile(kind: .cookNow, title: "Cook now", subtitle: "The best thing to make from what's in"), symbol: "frying.pan")
                AddRow(tile: DashboardTile(kind: .macros, title: "Today's food", subtitle: "Calories and protein against your targets"), symbol: "flame")
                AddRow(tile: DashboardTile(kind: .timer, title: "Timers", subtitle: "Kitchen timers that speak when they finish"), symbol: "timer")
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

/// Everything that isn't HomeKit, music or food.
private struct MoreTilePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(PhotoStore.self) private var photos
    @State private var albums: [PhotoStore.AlbumInfo] = []

    var body: some View {
        List {
            SwiftUI.Section("Calendar, time and weather") {
                AddRow(tile: DashboardTile(kind: .calendar, title: "Calendar",
                                           subtitle: "Coming events from the calendars you choose, shared ones too. Add one per calendar if you like"),
                       symbol: "calendar")
                AddRow(tile: DashboardTile(kind: .clock, title: "Clock", subtitle: "Digital, analogue or in words"), symbol: "clock")
                AddRow(tile: DashboardTile(kind: .weather, title: "Weather", subtitle: "Now, today's high and low, and rain on the way"), symbol: "cloud.sun")
                AddRow(tile: DashboardTile(kind: .forecast, title: "This week", subtitle: "The next few days of weather"), symbol: "calendar.day.timeline.left")
                AddRow(tile: DashboardTile(kind: .sun, title: "Sun", subtitle: "Time until sunrise or sunset"), symbol: "sunset")
                AddRow(tile: DashboardTile(kind: .worldClock, title: "World clock", subtitle: "The time somewhere else",
                                           options: ["tz": "America/New_York"]), symbol: "globe")
                AddRow(tile: DashboardTile(kind: .countdown, title: "Countdown", subtitle: "Days until something",
                                           options: ["date": TileDates.text(Date().addingTimeInterval(30 * 86_400))]), symbol: "calendar.badge.clock")
            }
            SwiftUI.Section("Getting about") {
                AddRow(tile: DashboardTile(kind: .trains, title: "Trains", subtitle: "Live departures from a station: choose the direction and operators"),
                       symbol: "tram.fill")
            }
            SwiftUI.Section("The flat") {
                AddRow(tile: DashboardTile(kind: .chores, title: "Chores", subtitle: "Whose turn it is, and a tick when it's done"), symbol: "checklist")
                AddRow(tile: DashboardTile(kind: .bins, title: "Bin days", subtitle: "Which bin goes out next"), symbol: "trash")
                AddRow(tile: DashboardTile(kind: .wifi, title: "Guest Wi-Fi", subtitle: "A code guests scan to join"), symbol: "wifi")
                AddRow(tile: DashboardTile(kind: .briefing, title: "Briefing", subtitle: "Says the weather, meals and chores out loud"), symbol: "speaker.wave.2.bubble")
            }
            SwiftUI.Section {
                AddRow(tile: DashboardTile(kind: .command, title: "Type a command", subtitle: "“kitchen off”, “lamp 30%”, “pasta 10 min”"), symbol: "text.cursor")
                ForEach(model.household.dashboard.routines) { r in
                    AddRow(tile: DashboardTile(kind: .routine, ref: r.id.uuidString, title: r.name, subtitle: "Routine"), symbol: r.icon)
                }
                AddRow(tile: DashboardTile(kind: .shortcut, title: "Shortcut or link", subtitle: "Runs one of Apple's Shortcuts, or opens a link"), symbol: "link")
            } header: { Text("Do things") } footer: {
                Text("Make routines (several steps from one tap) in the dashboard's settings: the cog in edit mode.")
            }
            SwiftUI.Section("Layout") {
                AddRow(tile: DashboardTile(kind: .folder, title: "Folder", subtitle: "Holds other tiles: tap to open it. Move tiles in from their menu"), symbol: "folder")
                AddRow(tile: DashboardTile(kind: .heading, title: "Heading", subtitle: "A title to split the grid into sections"), symbol: "textformat.size")
                AddRow(tile: DashboardTile(kind: .spacer, title: "Gap", subtitle: "An empty space"), symbol: "square.dashed")
            }
            SwiftUI.Section("Photo frames") {
                if photos.canRead {
                    ForEach(albums) { a in
                        AddRow(tile: DashboardTile(kind: .photoFrame, ref: a.id, title: a.title, subtitle: "\(a.count) photos"), symbol: "photo.on.rectangle")
                    }
                } else {
                    Button("Allow Photos to add a photo frame") { Task { await photos.authorise(); albums = photos.albums() } }
                }
            }
        }
        .onAppear { albums = photos.albums() }
    }
}
