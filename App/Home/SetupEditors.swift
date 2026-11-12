import HomeKit
import PlateCore
import SwiftUI

// The dashboard's settings: what the wall iPad does when idle, pages, chores, bin days, routines and their schedules,
// and saving the whole layout to share or keep.

struct DashboardSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(PhotoStore.self) private var photos
    @Environment(WeatherStore.self) private var weather
    @Environment(\.dismiss) private var dismiss
    @AppStorage("wallModeOnLaunch") private var wallOnLaunch = false
    @State private var albums: [PhotoStore.AlbumInfo] = []

    var body: some View {
        @Bindable var model = model
        let d = model.household.dashboard
        NavigationStack {
            Form {
                Section("Around the flat") {
                    NavigationLink { PagesEditor() } label: { row("Pages", "square.on.square", d.pages.isEmpty ? "One" : "\(d.pages.count)") }
                    NavigationLink { RoutinesEditor() } label: { row("Routines", "wand.and.stars", "\(d.routines.count)") }
                    NavigationLink { ChoresEditor() } label: { row("Chores", "checklist", "\(d.chores.count)") }
                    NavigationLink { RecurringEditor() } label: { row("Bin days", "trash", "\(d.recurring.count)") }
                    NavigationLink { LayoutShareView() } label: { row("Save or share this layout", "square.and.arrow.up", "") }
                }
                Section {
                    Picker("Show artwork after", selection: $model.household.dashboard.idle.minutes) {
                        Text("Never").tag(0)
                        ForEach([1, 2, 3, 5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    Toggle("Show the time", isOn: $model.household.dashboard.idle.showClock)
                    if d.idle.showClock {
                        Picker("Clock", selection: $model.household.dashboard.idle.clockFace) {
                            ForEach(ClockFace.allCases) { Text($0.title).tag($0) }
                        }
                        Toggle("Weather next to the time", isOn: $model.household.dashboard.idle.showWeather)
                    }
                    Toggle("Gentle movement", isOn: $model.household.dashboard.idle.drift)
                    Toggle("Moving colours when there's no photo", isOn: $model.household.dashboard.idle.aurora)
                    Toggle("Wake when a motion sensor sees someone", isOn: $model.household.dashboard.idle.wakeOnMotion)
                } header: { Text("When nobody's using it (wall mode)") } footer: {
                    Text("While music is playing it shows the album cover. Otherwise it shows the photo album below. A tap goes back to the dashboard. "
                         + "Gentle movement slowly zooms the photos and nudges the clock around, which also stops anything marking the screen.")
                }
                Section("Photos") {
                    if photos.canRead {
                        Picker("Album", selection: Binding(get: { model.household.dashboard.idle.photoAlbumId },
                                                           set: { id in
                                                               model.household.dashboard.idle.photoAlbumId = id
                                                               model.household.dashboard.idle.photoAlbumTitle = albums.first { $0.id == id }?.title
                                                           })) {
                            Text("None").tag(String?.none)
                            ForEach(albums) { a in Text("\(a.title) (\(a.count))").tag(Optional(a.id)) }
                        }
                        Picker("Each photo for", selection: $model.household.dashboard.idle.secondsPerSlide) {
                            ForEach([10, 20, 30, 60, 120, 300], id: \.self) { s in
                                Text(s < 60 ? "\(s) seconds" : "\(s / 60) min").tag(s)
                            }
                        }
                    } else if photos.status == .denied || photos.status == .restricted {
                        Text("Plate isn't allowed to see your photos. Turn it on in Settings → Privacy & Security → Photos.")
                            .font(.subheadline)
                    } else {
                        Button("Choose a photo album") { Task { await photos.authorise(); albums = photos.albums() } }
                    }
                }
                Section {
                    Toggle("Dim at night", isOn: $model.household.dashboard.idle.nightDim)
                    if d.idle.nightDim {
                        MinutesPicker(title: "From", minutes: $model.household.dashboard.idle.nightStart)
                        MinutesPicker(title: "Until", minutes: $model.household.dashboard.idle.nightEnd)
                        VStack(alignment: .leading) {
                            Text("How dark")
                            Slider(value: $model.household.dashboard.idle.nightDarkness, in: 0.2...0.95)
                        }
                    }
                } header: { Text("Night") }
                Section {
                    Button("Find my location again") { weather.forgetLocation(); Task { await weather.refresh(force: true) } }
                } header: { Text("Weather") } footer: {
                    Text("Plate keeps this device's location, rounded to about a kilometre, so the weather tile works without asking again. Use this if the device moves.")
                }
                Section {
                    Toggle("Open in wall mode", isOn: $wallOnLaunch)
                } header: { Text("This device") } footer: {
                    Text("Turn this on for the iPad on the wall. To stop anyone leaving Plate, use Guided Access: Settings → Accessibility → Guided Access, then triple-click the top button in Plate.")
                }
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { albums = photos.albums() }
        }
    }

    private func row(_ title: String, _ symbol: String, _ value: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}

/// A time of day, kept as minutes after midnight.
struct MinutesPicker: View {
    let title: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { Calendar.plate.date(byAdding: .minute, value: minutes, to: Calendar.plate.startOfDay(for: Date())) ?? Date() },
            set: { d in
                let c = Calendar.plate.dateComponents([.hour, .minute], from: d)
                minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }), displayedComponents: .hourAndMinute)
        .environment(\.locale, Locale(identifier: "en_GB"))
        .environment(\.timeZone, Calendar.plate.timeZone)
    }
}

// MARK: Pages

struct PagesEditor: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                ForEach($model.household.dashboard.pages) { $p in
                    HStack {
                        Menu {
                            ForEach(["house", "sofa", "bed.double", "fork.knife", "music.note", "lightbulb", "tv", "leaf", "star", "square.grid.2x2"], id: \.self) { i in
                                Button { p.icon = i } label: { Label(i, systemImage: i) }
                            }
                        } label: { Image(systemName: p.icon).frame(width: 30) }
                        TextField("Name", text: $p.name)
                    }
                }
                .onDelete { offsets in
                    for id in offsets.map({ model.household.dashboard.pages[$0].id }) { model.household.dashboard.removePage(id) }
                }
                .onMove { model.household.dashboard.pages.move(fromOffsets: $0, toOffset: $1) }
            } footer: {
                Text(model.household.dashboard.pages.isEmpty
                     ? "Add a page to split the dashboard up, say one for music or one per room. Swipe sideways to move between them."
                     : "Swipe a page to delete it; its tiles move to the first page. Move a tile to a page from its menu in edit mode.")
            }
            Section("New page") {
                TextField("Music", text: $name)
                Button("Add page") {
                    model.household.dashboard.addPage(named: name)
                    name = ""
                }
            }
        }
        .navigationTitle("Pages")
        .toolbar { EditButton() }
    }
}

// MARK: Chores and bin days

/// Names typed with commas between them. Keeps its own text so commas and spaces can be typed freely.
struct PeopleField: View {
    @Binding var people: [String]
    @State private var text = ""

    var body: some View {
        TextField("Ethan, Sam", text: $text)
            .autocorrectionDisabled()
            .onAppear { text = people.joined(separator: ", ") }
            .onChange(of: text) { _, t in
                people = t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
    }
}

struct ChoresEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            ForEach($model.household.dashboard.chores) { $c in
                Section {
                    TextField("Hoovering", text: $c.name)
                    HStack {
                        Text("Whose turn")
                        PeopleField(people: $c.people).multilineTextAlignment(.trailing)
                    }
                    Picker("Comes round", selection: $c.everyDays) {
                        Text("Every day").tag(1)
                        Text("Every 2 days").tag(2)
                        Text("Twice a week").tag(3)
                        Text("Every week").tag(7)
                        Text("Every 2 weeks").tag(14)
                        Text("Every 4 weeks").tag(28)
                    }
                    DatePicker("First turn starts", selection: $c.start, displayedComponents: .date)
                    IconRow(icon: $c.icon, choices: ["sparkles", "washer.fill", "dishwasher.fill", "trash.fill", "bathtub.fill", "toilet.fill", "leaf.fill", "cart.fill", "bed.double.fill", "pawprint.fill"])
                    if let who = c.assignee(on: Date()) { Text("This turn: \(who)").font(.caption).foregroundStyle(.secondary) }
                    Button("Remove this chore", role: .destructive) {
                        let id = c.id
                        model.household.dashboard.chores.removeAll { $0.id == id }
                    }
                }
            }
            Section {
                Button("Add a chore", systemImage: "plus") {
                    let names = model.household.members.map(\.name).filter { $0.lowercased() != "me" }
                    model.household.dashboard.chores.append(Chore(name: "", people: names, start: Calendar.plate.startOfWeek(for: Date())))
                    model.household.dashboard.add(DashboardTile(kind: .chores, title: "Chores"))
                }
            } footer: {
                Text("List the people in order and Plate works out whose turn it is each time. Tick a chore off on its tile; it comes back for the next person.")
            }
        }
        .navigationTitle("Chores")
    }
}

/// A row of icons to choose one from.
struct IconRow: View {
    @Binding var icon: String
    let choices: [String]
    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(choices, id: \.self) { i in
                    Button { icon = i } label: {
                        Image(systemName: i).frame(width: 38, height: 38)
                            .background(icon == i ? Color.accentColor.opacity(0.25) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

struct RecurringEditor: View {
    @Environment(AppModel.self) private var model

    private static let colours: [(String, String)] = [("Black", "#3A3A3C"), ("Blue", "#0A84FF"), ("Green", "#30B050"), ("Brown", "#A2703F"),
                                                       ("Purple", "#8E5AC8"), ("Red", "#E0483E"), ("Yellow", "#E6B800")]

    var body: some View {
        @Bindable var model = model
        Form {
            ForEach($model.household.dashboard.recurring) { $r in
                Section {
                    TextField("Recycling", text: $r.name)
                    Picker("How often", selection: $r.everyWeeks) {
                        Text("Every week").tag(1)
                        Text("Every 2 weeks").tag(2)
                        Text("Every 3 weeks").tag(3)
                        Text("Every 4 weeks").tag(4)
                    }
                    DatePicker("A day it happens", selection: $r.anchor, displayedComponents: .date)
                    HStack {
                        Text("Colour")
                        Spacer()
                        ForEach(Self.colours, id: \.1) { name, hex in
                            Button { r.tint = RGB(hex: hex) } label: {
                                Circle().fill(RGB(hex: hex)?.color ?? .gray).frame(width: 26, height: 26)
                                    .overlay(Circle().strokeBorder(Color.primary, lineWidth: r.tint?.hex == hex ? 2 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(name)
                        }
                    }
                    IconRow(icon: $r.icon, choices: ["trash", "trash.fill", "arrow.3.trianglepath", "leaf.fill", "waterbottle.fill", "shippingbox.fill", "newspaper.fill", "calendar"])
                    Text("Next: \(DayText.relative(r.next(onOrAfter: Date()), now: Date()))").font(.caption).foregroundStyle(.secondary)
                    Button("Remove", role: .destructive) {
                        let id = r.id
                        model.household.dashboard.recurring.removeAll { $0.id == id }
                    }
                }
            }
            Section {
                Button("Add a bin day", systemImage: "plus") {
                    model.household.dashboard.recurring.append(Recurring(name: "", anchor: Date()))
                    model.household.dashboard.add(DashboardTile(kind: .bins, title: "Bin days"))
                }
            } footer: {
                Text("Pick any day the collection happens and how often. It works for anything that comes round: bins, a cleaner, a veg box.")
            }
        }
        .navigationTitle("Bin days")
    }
}

// MARK: Routines

struct RoutinesEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var home

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                ForEach($model.household.dashboard.routines) { $r in
                    NavigationLink {
                        RoutineEditor(routine: $r)
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(r.name.isEmpty ? "New routine" : r.name)
                                Text(r.actions.isEmpty ? "No steps yet" : r.actions.prefix(3).map(\.summary).joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        } icon: { Image(systemName: r.icon) }
                    }
                }
                .onDelete { offsets in
                    let ids = Set(offsets.map { model.household.dashboard.routines[$0].id })
                    model.household.dashboard.routines.removeAll { ids.contains($0.id) }
                    model.household.dashboard.schedules.removeAll { ids.contains($0.routineId) }
                    model.household.dashboard.tiles.removeAll { $0.kind == .routine && ids.contains(UUID(uuidString: $0.ref ?? "") ?? UUID()) }
                }
                Button("New routine", systemImage: "plus") {
                    let r = Routine(name: "Routine \(model.household.dashboard.routines.count + 1)")
                    model.household.dashboard.routines.append(r)
                    model.household.dashboard.add(DashboardTile(kind: .routine, ref: r.id.uuidString, title: r.name))
                }
            } footer: {
                Text("A routine does several things from one tap, in order: scenes, lights, music, a timer, something said out loud, with waits in between. "
                     + "It can also run by itself at a time of day or at sunset, while Plate is open (which the wall iPad always is). "
                     + "Each routine gets a tile, and you can type its name in the command box.")
            }
        }
        .navigationTitle("Routines")
        .onAppear { home.start() }
    }
}

struct RoutineEditor: View {
    @Binding var routine: Routine
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var home
    @Environment(DashboardEngine.self) private var engine

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                TextField("Movie night", text: $routine.name)
                IconRow(icon: $routine.icon, choices: ["wand.and.stars", "moon.fill", "sunrise.fill", "tv.fill", "fork.knife", "sofa.fill", "figure.walk",
                                                       "party.popper.fill", "bed.double.fill", "house.fill", "cup.and.saucer.fill", "book.fill"])
            }
            Section("Steps, in order") {
                ForEach($routine.actions) { $a in
                    NavigationLink { ActionEditor(action: $a) } label: { Label(a.summary, systemImage: a.kind.icon) }
                }
                .onDelete { routine.actions.remove(atOffsets: $0) }
                .onMove { routine.actions.move(fromOffsets: $0, toOffset: $1) }
                Menu {
                    ForEach(RoutineActionKind.allCases) { k in
                        Button(k.title, systemImage: k.icon) { routine.actions.append(Self.fresh(k)) }
                    }
                } label: { Label("Add a step", systemImage: "plus") }
            }
            Section {
                ForEach($model.household.dashboard.schedules) { $s in
                    if s.routineId == routine.id { ScheduleRow(schedule: $s) }
                }
                Button("Add a time", systemImage: "clock.badge.plus") {
                    model.household.dashboard.schedules.append(RoutineSchedule(routineId: routine.id))
                }
            } header: { Text("Runs by itself") } footer: {
                Text("Sunrise and sunset come from the weather, so they need the weather tile to have worked once today.")
            }
            Section {
                Button("Try it now", systemImage: "play.fill") { Task { await engine.run(routine) } }
                    .disabled(routine.actions.isEmpty || engine.runningRoutine == routine.id)
            }
        }
        .navigationTitle(routine.name.isEmpty ? "Routine" : routine.name)
        .toolbar { EditButton() }
        .onChange(of: routine.name) { _, name in
            // Keep the routine's tile in step with its name.
            if let i = model.household.dashboard.tiles.firstIndex(where: { $0.kind == .routine && $0.ref == routine.id.uuidString }) {
                model.household.dashboard.tiles[i].title = name
            }
        }
    }

    static func fresh(_ k: RoutineActionKind) -> RoutineAction {
        switch k {
        case .brightness: return RoutineAction(kind: k, value: 50)
        case .startTimer: return RoutineAction(kind: k, value: 600)
        case .wait: return RoutineAction(kind: k, value: 5)
        case .lightShow: return RoutineAction(kind: k, text: LightShow.party.rawValue)
        default: return RoutineAction(kind: k)
        }
    }
}

private struct ScheduleRow: View {
    @Binding var schedule: RoutineSchedule
    @Environment(AppModel.self) private var model
    private static let days: [(Int, String)] = [(2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S"), (1, "S")]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(schedule.summary, isOn: $schedule.enabled)
            Picker("When", selection: $schedule.sun) { ForEach(SunEvent.allCases) { Text($0.title).tag($0) } }
            if schedule.sun == .none {
                MinutesPicker(title: "Time", minutes: $schedule.minutes)
            } else {
                Stepper(schedule.offset == 0 ? "Exactly then" : "\(abs(schedule.offset)) min \(schedule.offset < 0 ? "before" : "after")",
                        value: $schedule.offset, in: -120...120, step: 5)
            }
            HStack(spacing: 6) {
                ForEach(Self.days, id: \.0) { day, letter in
                    let on = schedule.weekdays.isEmpty || schedule.weekdays.contains(day)
                    Button {
                        var set = schedule.weekdays.isEmpty ? Set(1...7) : schedule.weekdays
                        if set.contains(day) { set.remove(day) } else { set.insert(day) }
                        schedule.weekdays = set.count == 7 ? [] : set
                    } label: {
                        Text(letter).font(.caption.weight(.bold)).frame(width: 30, height: 30)
                            .background(on ? Color.accentColor : Color(.tertiarySystemFill), in: Circle())
                            .foregroundStyle(on ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button(role: .destructive) {
                    let id = schedule.id
                    model.household.dashboard.schedules.removeAll { $0.id == id }
                } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

/// One step of a routine.
private struct ActionEditor: View {
    @Binding var action: RoutineAction
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var home

    var body: some View {
        Form {
            switch action.kind {
            case .scene:
                choices(home.scenes.map { ($0.uniqueIdentifier.uuidString, $0.name, nil as String?) }, empty: "No scenes in your home yet. Make them in Apple's Home app.")
            case .accessoryOn, .accessoryOff, .brightness:
                if action.kind == .brightness {
                    Section("Brightness") {
                        Slider(value: $action.value.or(50), in: 1...100, step: 1)
                        Text("\(Int(action.value ?? 50))%").foregroundStyle(.secondary)
                    }
                }
                choices((home.home?.accessories ?? [])
                    .filter { action.kind == .brightness ? HomeStore.category(of: $0) == .light : home.state(of: $0).isOn != nil }
                    .sorted { ($0.room?.name ?? "", $0.name) < ($1.room?.name ?? "", $1.name) }
                    .map { ($0.uniqueIdentifier.uuidString, $0.name, $0.room?.name) }, empty: "Nothing to switch in your home yet.")
            case .roomOn, .roomOff:
                choices(home.rooms.map { ($0.uniqueIdentifier.uuidString, $0.name, nil as String?) }, empty: "No rooms in your home yet.")
            case .playAlbum:
                let pinned = model.household.dashboard.tiles.filter { $0.kind == .musicAlbum || $0.kind == .playlist }
                Section {
                    if pinned.isEmpty { Text("Pin an album or playlist to the dashboard first, then choose it here.").foregroundStyle(.secondary) }
                    ForEach(pinned) { t in
                        Button {
                            action.ref = t.ref
                            action.name = t.name()
                            action.text = t.kind == .playlist ? (t.options["type"] ?? "playlist") : nil
                        } label: { pick(t.name(), t.subtitle, chosen: action.ref == t.ref) }
                        .foregroundStyle(.primary)
                    }
                }
            case .startTimer:
                Section("Timer") {
                    TextField("What it's for (optional)", text: $action.text.or(""))
                    Stepper("\(DashTimer.words(action.value ?? 600))", value: $action.value.or(600), in: 60...14_400, step: 60)
                }
            case .say:
                Section {
                    TextField("Dinner's ready", text: $action.text.or(""), axis: .vertical)
                    Button("Hear it", systemImage: "speaker.wave.2") { Feedback.shared.say(action.text ?? "", force: true) }
                } footer: { Text("Said out loud by the iPad in a British voice.") }
            case .wait:
                Section("Wait") {
                    Stepper("\(DashTimer.words(action.value ?? 5))", value: $action.value.or(5), in: 1...3600, step: (action.value ?? 5) >= 60 ? 30 : 1)
                }
            case .lightShow:
                Section("Light show") {
                    Picker("Show", selection: $action.text.or(LightShow.party.rawValue)) {
                        ForEach(LightShow.allCases) { Label($0.title, systemImage: $0.icon).tag($0.rawValue) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
            case .allLightsOff, .pauseMusic, .stopLightShow, .showArtwork:
                Section { Text("Nothing to set for this step.").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(action.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { home.start() }
    }

    private func choices(_ items: [(String, String, String?)], empty: String) -> some View {
        Section {
            if items.isEmpty { Text(home.status == .ready ? empty : "Looking for your home…").foregroundStyle(.secondary) }
            ForEach(items, id: \.0) { id, name, detail in
                Button {
                    action.ref = id
                    action.name = name
                } label: { pick(name, detail, chosen: action.ref == id) }
                .foregroundStyle(.primary)
            }
        }
    }

    private func pick(_ name: String, _ detail: String?, chosen: Bool) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if chosen { Image(systemName: "checkmark").foregroundStyle(.tint) }
        }
    }
}

// MARK: Save and share

/// The whole dashboard (tiles, look, routines, chores) as text, to keep as a backup or send to another device.
struct LayoutShareView: View {
    @Environment(AppModel.self) private var model
    @State private var message: String?
    @State private var confirm: HomeDashboard?

    var body: some View {
        Form {
            Section {
                ShareLink(item: Self.export(model.household.dashboard), preview: SharePreview("Plate dashboard layout")) {
                    Label("Share this layout", systemImage: "square.and.arrow.up")
                }
                Button("Copy it", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = Self.export(model.household.dashboard)
                    message = "Copied. Paste it into Notes or a message to keep it."
                }
            } footer: {
                Text("The layout is plain text. It doesn't include the Wi-Fi password, and tiles for lights only work in the same home.")
            }
            Section {
                Button("Use a layout I've copied", systemImage: "doc.on.clipboard") {
                    guard let text = UIPasteboard.general.string, let d = Self.read(text) else {
                        message = "What's on the clipboard isn't a Plate dashboard layout. Copy the whole text and try again."
                        return
                    }
                    confirm = d
                }
            } footer: { if let message { Text(message) } }
        }
        .navigationTitle("Save or share")
        .confirmationDialog("Replace this dashboard with the copied one?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible) {
            Button("Replace (\(confirm?.tiles.count ?? 0) tiles)", role: .destructive) {
                if let confirm { model.household.dashboard = confirm; message = "Done. The dashboard is now the copied layout." }
                confirm = nil
            }
        }
    }

    static func export(_ d: HomeDashboard) -> String {
        var copy = d
        copy.timers = []
        copy.activity = []
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return (try? e.encode(copy)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func read(_ text: String) -> HomeDashboard? {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        guard let data = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              text.contains("\"tiles\""), let dash = try? d.decode(HomeDashboard.self, from: data) else { return nil }
        return dash
    }
}
