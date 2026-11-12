import HomeKit
import PhotosUI
import PlateCore
import SwiftUI

// Where the dashboard is made your own: the look and sounds of the whole thing, each tile's name, icon and colour,
// and the full controls for a light, blind or thermostat.

extension Binding {
    /// A binding to an optional that reads as `fallback` while it's nil.
    func or<T>(_ fallback: T) -> Binding<T> where Value == T? {
        Binding<T>(get: { wrappedValue ?? fallback }, set: { wrappedValue = $0 })
    }
}

/// Colours, background, tile shape, font and sounds. Shown as a half-height sheet so the dashboard changes behind it
/// as you go.
struct StyleEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(PhotoStore.self) private var photos
    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        @Bindable var model = model
        let style = model.household.dashboard.style
        NavigationStack {
            Form {
                Section("Start from a theme") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(ThemePreset.all) { p in
                                Button {
                                    withAnimation { model.household.dashboard.style = p.applied(to: model.household.dashboard.style) }
                                    Feedback.shared.settings = model.household.dashboard.style.sounds
                                    Feedback.shared.play(.scene)
                                } label: { PresetSwatch(preset: p) }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 0))
                }

                Section("Colours") {
                    RGBPicker(title: "Accent (buttons and highlights)", value: $model.household.dashboard.style.accent)
                    RGBPicker(title: "Tiles that are on", value: $model.household.dashboard.style.onColor)
                    Picker("Light or dark", selection: $model.household.dashboard.style.appearance) {
                        Text("Automatic").tag(AppearanceChoice.auto)
                        Text("Light").tag(AppearanceChoice.light)
                        Text("Dark").tag(AppearanceChoice.dark)
                    }
                }

                Section("Background") {
                    Picker("Background", selection: $model.household.dashboard.style.background) {
                        ForEach(BackgroundKind.allCases) { Text($0.title).tag($0) }
                    }
                    if style.background != .system && style.background != .photo {
                        RGBPicker(title: style.background == .solid ? "Colour" : "First colour", value: $model.household.dashboard.style.backgroundA)
                    }
                    if style.background == .gradient || style.background == .aurora || style.background == .nowPlaying {
                        RGBPicker(title: "Second colour", value: $model.household.dashboard.style.backgroundB)
                    }
                    if style.background == .photo {
                        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                            Label(style.backgroundPhotoId == nil ? "Choose a photo" : "Choose a different photo", systemImage: "photo")
                        }
                        if !photos.canRead {
                            Text("Plate needs to be allowed to see your photos to show one behind the tiles.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if style.background == .photo || style.background == .nowPlaying {
                        slider("Blur", $model.household.dashboard.style.backgroundBlur, 0...1)
                    }
                    if style.background != .system {
                        slider("Darken", $model.household.dashboard.style.backgroundDim, 0...0.9)
                    }
                }

                Section("Tiles") {
                    Picker("Look", selection: $model.household.dashboard.style.tileLook) {
                        ForEach(TileLook.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Own tile colour", isOn: Binding(get: { style.tileColor != nil },
                                                            set: { model.household.dashboard.style.tileColor = $0 ? RGB(hex: "#1C1C1E") : nil }))
                    if style.tileColor != nil {
                        RGBPicker(title: "Tile colour", value: $model.household.dashboard.style.tileColor.or(.black))
                    }
                    slider("See-through", Binding(get: { 1 - model.household.dashboard.style.tileOpacity },
                                                  set: { model.household.dashboard.style.tileOpacity = 1 - $0 }), 0...0.8)
                    slider("Rounded corners", $model.household.dashboard.style.cornerRadius, 0...40)
                    slider("Gap between tiles", $model.household.dashboard.style.spacing, 6...28)
                    Picker("Tile size", selection: $model.household.dashboard.style.density) {
                        Text("Small (more fit)").tag(TileDensity.compact)
                        Text("Medium").tag(TileDensity.regular)
                        Text("Big").tag(TileDensity.roomy)
                    }
                }

                Section("Text") {
                    Picker("Lettering", selection: $model.household.dashboard.style.font) {
                        ForEach(FontLook.allCases) { Text($0.title).fontDesign($0.design).tag($0) }
                    }
                    Toggle("Greeting and summary at the top", isOn: $model.household.dashboard.style.showGreeting)
                    Picker("Clock in the middle", selection: $model.household.dashboard.style.headerClock) {
                        ForEach(HeaderClock.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    Picker("Sounds", selection: $model.household.dashboard.style.sounds.pack) {
                        ForEach(SoundPack.allCases) { Text($0.title).tag($0) }
                    }
                    if style.sounds.pack != .off {
                        slider("Volume", $model.household.dashboard.style.sounds.volume, 0...1)
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(SoundEvent.allCases, id: \.self) { e in
                                    Button(Self.name(e)) {
                                        Feedback.shared.settings = model.household.dashboard.style.sounds
                                        Feedback.shared.play(e)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                    Toggle("Taps you can feel (iPhone)", isOn: $model.household.dashboard.style.sounds.haptics)
                    Toggle("Say when a timer finishes", isOn: $model.household.dashboard.style.sounds.speech)
                } header: { Text("Sounds") } footer: {
                    Text("Sounds follow the device's ringer volume and silent switch, and don't interrupt music.")
                }

                Section {
                    Button("Back to the standard look", role: .destructive) {
                        withAnimation { model.household.dashboard.style = ThemePreset.all[0].applied(to: model.household.dashboard.style) }
                    }
                }
            }
            .navigationTitle("Make it yours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: photoItem) { _, item in
                guard let id = item?.itemIdentifier else { return }
                model.household.dashboard.style.backgroundPhotoId = id
                Task { if !photos.canRead { await photos.authorise() } }
            }
        }
    }

    static func name(_ e: SoundEvent) -> String {
        switch e {
        case .on: return "On"
        case .off: return "Off"
        case .scene: return "Scene"
        case .error: return "Problem"
        case .timer: return "Timer"
        case .wake: return "Wake"
        case .tap: return "Tap"
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline)
            Slider(value: value, in: range)
        }
    }
}

/// A little picture of a theme: its background, a tile and a lit tile.
private struct PresetSwatch: View {
    let preset: ThemePreset

    var body: some View {
        let s = preset.style
        VStack(spacing: 6) {
            ZStack {
                switch s.background {
                case .system: Color(.systemGroupedBackground)
                case .solid: s.backgroundA.color
                default: LinearGradient(colors: [s.backgroundA.color, s.backgroundB.color], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: s.cornerRadius / 3.5)
                        .fill(s.tileLook == .solid ? (s.tileColor?.color ?? Color(.secondarySystemGroupedBackground)) : Color.white.opacity(0.25))
                        .overlay(RoundedRectangle(cornerRadius: s.cornerRadius / 3.5).strokeBorder(s.accent.color, lineWidth: s.tileLook == .outline ? 1.5 : 0))
                    RoundedRectangle(cornerRadius: s.cornerRadius / 3.5).fill(s.onColor.color)
                }
                .padding(10)
            }
            .frame(width: 92, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.3)))
            Text(preset.name).font(.caption)
        }
    }
}

// MARK: One tile

/// Name, icon, colour, size and page for one tile, plus whatever is particular to its kind.
struct TileEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var home
    @Environment(PhotoStore.self) private var photos
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DashboardTile
    @State private var password = ""
    @State private var showIcons = false

    init(tile: DashboardTile) { _draft = State(initialValue: tile) }

    private func option(_ key: String) -> Binding<String> {
        Binding(get: { draft.options[key] ?? "" }, set: { draft.options[key] = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                particular
                if draft.kind != .spacer {
                    Section("Name and look") {
                        TextField(draft.title.isEmpty ? "Name" : draft.title, text: $draft.label.or(""))
                        DisclosureGroup(isExpanded: $showIcons) {
                            IconPicker(selection: $draft.icon)
                        } label: {
                            HStack {
                                Text("Icon")
                                Spacer()
                                if let icon = draft.icon { Image(systemName: icon) } else { Text("Automatic").foregroundStyle(.secondary) }
                            }
                        }
                        Toggle("Its own colour", isOn: Binding(get: { draft.tint != nil },
                                                               set: { draft.tint = $0 ? model.household.dashboard.style.accent : nil }))
                        if draft.tint != nil { RGBPicker(title: "Colour", value: $draft.tint.or(.black)) }
                    }
                }
                Section("Size and place") {
                    Picker("Size", selection: $draft.size) { ForEach(TileSize.allCases) { Text($0.title).tag($0) } }
                        .pickerStyle(.segmented)
                    if model.household.dashboard.pages.count > 1 {
                        Picker("Page", selection: Binding(get: { draft.pageId ?? model.household.dashboard.pages[0].id },
                                                          set: { draft.pageId = $0 })) {
                            ForEach(model.household.dashboard.pages) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                Section {
                    Button("Remove from the dashboard", role: .destructive) {
                        if draft.kind == .wifi { SecretStore.set(SecretStore.wifiAccount(draft.id), nil) }
                        model.household.dashboard.remove(draft.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle(draft.name())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { save() }.fontWeight(.semibold) }
            }
            .onAppear {
                if draft.kind == .wifi { password = SecretStore.get(SecretStore.wifiAccount(draft.id)) ?? "" }
            }
        }
    }

    private func save() {
        if draft.kind == .wifi { SecretStore.set(SecretStore.wifiAccount(draft.id), password) }
        if let l = draft.label, l.trimmingCharacters(in: .whitespaces).isEmpty { draft.label = nil }
        model.household.dashboard.update(draft)
        dismiss()
    }

    /// The settings only this kind of tile has.
    @ViewBuilder private var particular: some View {
        switch draft.kind {
        case .note:
            Section("Note") { TextField("Bins out Thursday", text: $draft.subtitle.or(""), axis: .vertical).lineLimit(2...6) }
        case .countdown:
            Section("Counting down to") {
                DatePicker("Day", selection: Binding(get: { TileDates.day(draft.options["date"]) ?? Date() },
                                                     set: { draft.options["date"] = TileDates.text($0) }), displayedComponents: .date)
            }
        case .worldClock:
            Section("Where") {
                Picker("Time zone", selection: option("tz")) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                }
                .pickerStyle(.navigationLink)
            }
        case .calendar:
            CalendarSettings(options: $draft.options)
        case .clock:
            Section("Clock") {
                Picker("Face", selection: option("face")) {
                    Text("Digital").tag("")
                    Text("Analogue").tag(ClockFace.analogue.rawValue)
                    Text("In words").tag(ClockFace.words.rawValue)
                }
            }
        case .wifi:
            Section {
                TextField("Wi-Fi name", text: option("ssid")).autocorrectionDisabled().textInputAutocapitalization(.never)
                SecureField("Password", text: $password)
                Toggle("Hidden network", isOn: Binding(get: { draft.options["hidden"] == "1" }, set: { draft.options["hidden"] = $0 ? "1" : nil }))
            } header: { Text("Guest Wi-Fi") } footer: {
                Text("Guests point their camera at the tile to join. The password is kept in this device's keychain, not in Plate's files.")
            }
        case .shortcut:
            Section {
                TextField("Name of a shortcut", text: option("shortcut")).autocorrectionDisabled()
                TextField("or a link (https://…)", text: option("url")).autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL)
            } header: { Text("What it opens") } footer: {
                Text("Type a shortcut's name exactly as it is in Apple's Shortcuts app, and a tap runs it. That reaches anything Shortcuts can: your TV, a robot vacuum, another app.")
            }
        case .lightShow:
            Section("Light show") {
                Picker("Show", selection: option("show")) {
                    ForEach(LightShow.allCases) { Label($0.title, systemImage: $0.icon).tag($0.rawValue) }
                }
                .pickerStyle(.inline).labelsHidden()
            }
        case .photoFrame:
            Section("Photos") {
                Picker("Album", selection: $draft.ref) {
                    ForEach(photos.albums()) { a in Text("\(a.title) (\(a.count))").tag(Optional(a.id)) }
                }
                Picker("Each photo for", selection: option("seconds")) {
                    Text("30 seconds").tag("")
                    Text("10 seconds").tag("10")
                    Text("1 minute").tag("60")
                    Text("5 minutes").tag("300")
                    Text("1 hour").tag("3600")
                }
            }
        case .group:
            Section {
                let chosen = Set((draft.options["ids"] ?? "").split(separator: ",").map(String.init))
                ForEach(home.rooms, id: \.uniqueIdentifier) { room in
                    ForEach(home.accessories(in: room).filter { HomeStore.category(of: $0) != .sensor && HomeStore.category(of: $0) != .other },
                            id: \.uniqueIdentifier) { a in
                        let id = a.uniqueIdentifier.uuidString
                        Button {
                            var next = chosen
                            if next.contains(id) { next.remove(id) } else { next.insert(id) }
                            draft.options["ids"] = next.sorted().joined(separator: ",")
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(a.name)
                                    Text(room.name).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: chosen.contains(id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(chosen.contains(id) ? Color.green : Color.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            } header: { Text("What's in the group") } footer: { Text("One tap switches all of these together.") }
            .onAppear { home.start() }
        case .trains:
            TrainSettings(options: $draft.options)
        case .musicAlbum, .playlist:
            Section {
                NavigationLink {
                    MusicPickerView { draft.setMusic($0) }
                } label: {
                    HStack {
                        Text(draft.ref == nil ? "Choose music" : "Change the music")
                        Spacer()
                        Text(draft.ref == nil ? "" : draft.title).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } header: { Text("What it plays") } footer: {
                Text("Search your library and the whole of Apple Music: albums, playlists and stations.")
            }
        case .chores:
            Section { NavigationLink("Edit the chores") { ChoresEditor() } }
        case .bins:
            Section { NavigationLink("Edit the bin days") { RecurringEditor() } }
        case .routine:
            Section { NavigationLink("Edit routines") { RoutinesEditor() } }
        default:
            EmptyView()
        }
    }
}

// MARK: One accessory

/// Everything a light, blind or thermostat can do, beyond on and off.
struct AccessoryControlView: View {
    let accessoryId: String
    @Environment(HomeStore.self) private var home
    @Environment(\.dismiss) private var dismiss
    @State private var brightness = 50.0
    @State private var position = 50.0

    var body: some View {
        NavigationStack {
            Group {
                if let a = home.accessory(accessoryId) { controls(a) } else { Text("This isn't in your home any more.") }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private func controls(_ a: HMAccessory) -> some View {
        let s = home.state(of: a)
        let d = home.detail(of: a)
        let cat = HomeStore.category(of: a)
        Form {
            Section {
                HStack {
                    Image(systemName: s.symbol).font(.title).foregroundStyle(s.isOn == true ? Color.yellow : Color.secondary)
                    VStack(alignment: .leading) {
                        Text(a.name).font(.headline)
                        Text(s.reachable ? (s.detail ?? "") : "Not responding").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if cat != .thermostat && cat != .lock, s.isOn != nil {
                        Toggle("On", isOn: Binding(get: { s.isOn == true }, set: { _ in Task { await home.toggle(a) } })).labelsHidden()
                    }
                }
            }
            if d.brightness != nil {
                Section("Brightness") {
                    HStack {
                        Image(systemName: "sun.min")
                        Slider(value: $brightness, in: 1...100, step: 1) { moving in
                            if !moving { Task { await home.setBrightness(a, to: Int(brightness)) } }
                        }
                        Image(systemName: "sun.max.fill")
                    }
                    Text("\(Int(brightness))%").font(.caption).foregroundStyle(.secondary)
                }
            }
            if d.hue != nil {
                Section("Colour") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 46))], spacing: 12) {
                        ForEach(LightColor.swatches, id: \.name) { c in
                            Button {
                                Feedback.shared.play(.tap)
                                Task { await home.setColour(a, hue: c.hue, saturation: c.saturation) }
                            } label: {
                                Circle().fill(RGB(hue: c.hue / 360, saturation: c.saturation / 100, brightness: 1).color)
                                    .frame(width: 44, height: 44)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(c.name)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if d.mired != nil || d.hue != nil {
                Section("White") {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(LightColor.whites, id: \.name) { w in
                                Button(w.name) {
                                    Feedback.shared.play(.tap)
                                    Task {
                                        if d.mired != nil { await home.setWarmth(a, kelvin: w.kelvin) }
                                        else { await home.setColour(a, hue: w.kelvin < 4500 ? 32 : 210, saturation: abs(4500 - w.kelvin) / 60) }
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            if cat == .blinds {
                Section("How far open") {
                    Slider(value: $position, in: 0...100, step: 5) { moving in
                        if !moving { Task { await home.setPosition(a, to: Int(position)) } }
                    }
                    HStack {
                        Button("Closed") { position = 0; Task { await home.setPosition(a, to: 0) } }
                        Spacer()
                        Button("Half") { position = 50; Task { await home.setPosition(a, to: 50) } }
                        Spacer()
                        Button("Open") { position = 100; Task { await home.setPosition(a, to: 100) } }
                    }
                    .buttonStyle(.bordered)
                }
            }
            if cat == .thermostat {
                Section("Temperature") {
                    HStack {
                        Button { Task { await home.nudgeTemperature(a, by: -0.5) } } label: { Image(systemName: "minus.circle.fill").font(.largeTitle) }
                        Spacer()
                        Text(s.detail ?? "–").font(.title2.weight(.semibold))
                        Spacer()
                        Button { Task { await home.nudgeTemperature(a, by: 0.5) } } label: { Image(systemName: "plus.circle.fill").font(.largeTitle) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(a.name)
        .onAppear {
            brightness = Double(d.brightness ?? 50)
            if let p = (HomeStore.characteristic(HMCharacteristicTypeCurrentPosition, in: a)?.value as? NSNumber)?.doubleValue { position = p }
        }
    }
}
