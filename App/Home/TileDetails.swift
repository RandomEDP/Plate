import MusicKit
import PlateCore
import SwiftUI

// Tap a tile to see more. Tiles that are buttons (lights, scenes, music, routines…) keep their own tap; the rest open a
// bigger view here, or go to the part of Plate they come from. Which does what is `TileTap` in PlateCore.

struct TileTapModifier: ViewModifier {
    let tile: DashboardTile
    let enabled: Bool
    @Environment(AppModel.self) private var model
    @State private var showing = false

    func body(content: Content) -> some View {
        let action = TileTap.action(for: tile.kind)
        if !enabled || action == .none {
            content
        } else {
            content
                .contentShape(Rectangle())
                .onTapGesture {
                    Feedback.shared.play(.tap)
                    switch action {
                    case .details: showing = true
                    case .open(let section): open(section)
                    case .none: break
                    }
                }
                .accessibilityAddTraits(.isButton)
                .sheet(isPresented: $showing) {
                    TileDetailView(tile: tile)
                        .presentationDragIndicator(.visible)
                }
        }
    }

    private func open(_ section: PlateSection) {
        model.showWall = false
        switch section {
        case .today: model.selectedTab = .today
        case .kitchen: model.selectedTab = .kitchen
        case .recipes: model.selectedTab = .recipes
        case .plan: model.selectedTab = .plan
        case .shop: model.selectedTab = .shop
        }
    }
}

/// The bigger view for one tile, with a Done button.
struct TileDetailView: View {
    let tile: DashboardTile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var title: String {
        switch tile.kind {
        case .weather, .forecast, .sun: return "Weather"
        case .calendar: return tile.name("Calendar")
        case .nowPlaying: return "Now playing"
        case .climate: return tile.name("Climate")
        case .battery: return "Batteries"
        case .bins: return tile.name("Bin days")
        case .wifi: return "Guest Wi-Fi"
        case .activity: return tile.name("Recently")
        case .checklist: return tile.name("Today")
        default: return tile.name()
        }
    }

    @ViewBuilder private var content: some View {
        switch tile.kind {
        case .weather, .forecast, .sun: WeatherDetailView()
        case .calendar: CalendarDetailView(tile: tile)
        case .nowPlaying: NowPlayingDetailView()
        case .climate: ClimateDetailView()
        case .battery: BatteryDetailView()
        case .bins: BinsDetailView()
        case .wifi: WiFiDetailView(tile: tile)
        case .activity: ActivityDetailView()
        case .checklist: ChecklistDetailView(tile: tile)
        default: ContentUnavailableView("Nothing more to show", systemImage: "square.dashed")
        }
    }
}

// MARK: Weather

struct WeatherDetailView: View {
    @Environment(WeatherStore.self) private var weather

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let now = weather.now {
                    current(now)
                    hourly(now)
                    daily(now)
                    sun(now)
                } else {
                    Text(weather.problem ?? "Getting the weather…").foregroundStyle(.secondary)
                }
                WeatherAttributionMark()
            }
            .padding()
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .environment(\.locale, Locale(identifier: "en_GB"))
        .task { await weather.refresh() }
    }

    private func current(_ now: WeatherStore.Now) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: now.symbol).symbolRenderingMode(.multicolor).font(.system(size: 64))
                VStack(alignment: .leading) {
                    Text(WeatherText.temperature(now.temperature)).font(.system(size: 60, weight: .semibold))
                    Text(now.condition).font(.title3).foregroundStyle(.secondary)
                }
                Spacer()
                if let r = WeatherText.range(now.hours, now: Date()) {
                    VStack(alignment: .trailing) {
                        Text("High \(WeatherText.temperature(r.high))")
                        Text("Low \(WeatherText.temperature(r.low))").foregroundStyle(.secondary)
                    }
                    .font(.title3.monospacedDigit())
                }
            }
            if let rain = WeatherText.rainNote(now.hours, now: Date()) {
                Label(rain, systemImage: "umbrella.fill").font(.headline).foregroundStyle(.blue)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                if let f = now.feelsLike { fact("Feels like", WeatherText.temperature(f), "thermometer.medium") }
                if let h = now.humidity { fact("Humidity", "\(h)%", "humidity") }
                if let w = now.windMph { fact("Wind", "\(w) mph" + (now.windDirection.map { " \($0)" } ?? ""), "wind") }
                if let uv = now.uvIndex { fact("UV index", "\(uv)", "sun.max") }
            }
        }
    }

    private func fact(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func hourly(_ now: WeatherStore.Now) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next 24 hours").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(WeatherText.nextHours(now.hours, now: Date()).enumerated()), id: \.element.date) { i, h in
                        VStack(spacing: 6) {
                            Text(i == 0 ? "Now" : h.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))))
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Image(systemName: h.symbol ?? "cloud").symbolRenderingMode(.multicolor).font(.title3).frame(height: 28)
                            Text(WeatherText.temperature(h.temperature)).font(.subheadline.weight(.semibold).monospacedDigit())
                            Text(h.precipitationChance >= 0.1 ? "\(Int((h.precipitationChance * 100).rounded()))%" : " ")
                                .font(.caption2.weight(.semibold)).foregroundStyle(.blue)
                        }
                        .frame(minWidth: 40)
                    }
                }
                .padding(12)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func daily(_ now: WeatherStore.Now) -> some View {
        let lo = now.days.map(\.low).min() ?? 0, hi = now.days.map(\.high).max() ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            Text("This week").font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(now.days.enumerated()), id: \.element.date) { i, d in
                    if i > 0 { Divider() }
                    HStack(spacing: 12) {
                        Text(i == 0 ? "Today" : DayText.weekday(d.date)).frame(width: 96, alignment: .leading)
                        Image(systemName: d.symbol).symbolRenderingMode(.multicolor).frame(width: 30)
                        Text(d.precipitationChance >= 0.1 ? "\(Int((d.precipitationChance * 100).rounded()))%" : "")
                            .font(.caption.weight(.semibold)).foregroundStyle(.blue).frame(width: 36, alignment: .leading)
                        Text(WeatherText.temperature(d.low)).monospacedDigit().foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                        GeometryReader { geo in
                            let s = WeatherText.span(low: d.low, high: d.high, weekLow: lo, weekHigh: hi)
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.2))
                                Capsule().fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geo.size.width * (s.end - s.start))
                                    .offset(x: geo.size.width * s.start)
                            }
                        }
                        .frame(height: 6)
                        Text(WeatherText.temperature(d.high)).monospacedDigit().frame(width: 36, alignment: .leading)
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder private func sun(_ now: WeatherStore.Now) -> some View {
        if let rise = now.sunrise, let set = now.sunset {
            HStack(spacing: 10) {
                fact("Sunrise", WorldClockTile.time(rise, Calendar.plate.timeZone), "sunrise.fill")
                fact("Sunset", WorldClockTile.time(set, Calendar.plate.timeZone), "sunset.fill")
                fact("Daylight", DashTimer.words(set.timeIntervalSince(rise)), "sun.horizon")
            }
        }
    }
}

// MARK: Calendar

struct CalendarDetailView: View {
    let tile: DashboardTile
    @State private var newReminder = ""
    private var store: CalendarStore { CalendarStore.shared }

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let items = CalendarTileSettings.agenda(events: store.events, reminders: store.reminders, options: wider, now: ctx.date,
                                                    calendar: .plate)
            let todo = CalendarTileSettings.undated(store.reminders, options: tile.options)
            let days = Dictionary(grouping: items) { $0.day(now: ctx.date, calendar: .plate) }
            let lists = CalendarTileSettings.reminderLists(tile.options)
            List {
                if let list = store.reminderLists.first(where: { lists.contains($0.id) }) {
                    Section {
                        HStack {
                            Image(systemName: "plus.circle.fill").foregroundStyle(list.color)
                            TextField("New reminder in \(list.title)", text: $newReminder)
                                .submitLabel(.done)
                                .onSubmit { add(to: list.id) }
                        }
                    }
                }
                if items.isEmpty && todo.isEmpty {
                    Text("Nothing in the next fortnight.").foregroundStyle(.secondary)
                }
                ForEach(days.keys.sorted(), id: \.self) { day in
                    Section(CalendarTileSettings.dayHeading(day, now: ctx.date, calendar: .plate)) {
                        ForEach(days[day] ?? []) { item in
                            switch item {
                            case .event(let e): EventRow(event: e, now: ctx.date)
                            case .reminder(let r):
                                ReminderLine(reminder: r, colour: store.listColours[r.listId] ?? .accentColor, now: ctx.date)
                            }
                        }
                    }
                }
                if !todo.isEmpty {
                    Section("To do") {
                        ForEach(todo) { r in
                            ReminderLine(reminder: r, colour: store.listColours[r.listId] ?? .accentColor, now: ctx.date)
                        }
                    }
                }
            }
        }
        .task {
            await store.refresh()
            if !CalendarTileSettings.reminderLists(tile.options).isEmpty { await store.refreshReminders(force: true) }
        }
    }

    private func add(to listId: String) {
        let title = newReminder
        newReminder = ""
        Task { await store.add(title, to: listId) }
    }

    /// The tile's calendars, but a fortnight ahead (or more, if the tile already looks further).
    private var wider: [String: String] {
        var options = tile.options
        options["days"] = "\(max(14, CalendarTileSettings.days(tile.options)))"
        return options
    }
}

struct EventRow: View {
    let event: CalendarEvent
    let now: Date
    private var store: CalendarStore { CalendarStore.shared }

    var body: some View {
        let source = store.calendars.first { $0.id == event.calendarId }
        HStack(alignment: .top, spacing: 12) {
            Capsule().fill(source?.color ?? .accentColor).frame(width: 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.headline)
                Text(time).font(.subheadline).foregroundStyle(.secondary)
                if let place = event.location, !place.isEmpty {
                    Label(place, systemImage: "mappin.and.ellipse").font(.subheadline)
                }
                if let notes = event.notes, !notes.isEmpty {
                    Text(notes).font(.callout).foregroundStyle(.secondary).lineLimit(6)
                }
                if let source { Text(source.title).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(.vertical, 4)
    }

    /// "All day", "Now, until 21:00", "18:00 to 19:00 (1 hr)".
    private var time: String {
        let t = { (d: Date) in HeaderClock.timeText(d, calendar: .plate) }
        if event.allDay { return "All day" }
        if event.start <= now { return "Now, until \(t(event.end))" }
        let length = event.end.timeIntervalSince(event.start)
        return "\(t(event.start)) to \(t(event.end))" + (length > 0 ? " (\(DashTimer.words(length)))" : "")
    }
}

// MARK: Music

struct NowPlayingDetailView: View {
    @Environment(MusicStore.self) private var music
    @ObservedObject private var state = SystemMusicPlayer.shared.state
    @ObservedObject private var queue = SystemMusicPlayer.shared.queue

    var body: some View {
        let current = queue.currentEntry
        List {
            Section {
                VStack(spacing: 16) {
                    Group {
                        if let art = current?.artwork {
                            ArtworkImage(art, width: 280, height: 280)
                        } else {
                            RoundedRectangle(cornerRadius: 16).fill(Color.pink.gradient)
                                .overlay(Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.white))
                        }
                    }
                    .frame(width: 280, height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 12)
                    VStack(spacing: 4) {
                        Text(current?.title ?? "Nothing playing").font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                        Text(current?.subtitle ?? "Play something here or in Music").foregroundStyle(.secondary)
                    }
                    progress(current)
                    HStack(spacing: 36) {
                        Button { state.shuffleMode = state.shuffleMode == .songs ? .off : .songs } label: {
                            Image(systemName: "shuffle").opacity(state.shuffleMode == .songs ? 1 : 0.4)
                        }
                        Button { Task { try? await music.player.skipToPreviousEntry() } } label: { Image(systemName: "backward.fill") }
                        Button { Task { await music.togglePlayPause() } } label: {
                            Image(systemName: state.playbackStatus == .playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 56))
                        }
                        Button { Task { try? await music.player.skipToNextEntry() } } label: { Image(systemName: "forward.fill") }
                        RoutePicker().frame(width: 30, height: 30)
                    }
                    .font(.title)
                    .buttonStyle(.plain)
                    .disabled(current == nil)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
        }
    }

    @ViewBuilder private func progress(_ entry: MusicPlayer.Queue.Entry?) -> some View {
        if case .song(let song)? = entry?.item, let length = song.duration, length > 0 {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let at = min(length, max(0, music.player.playbackTime))
                VStack(spacing: 4) {
                    ProgressView(value: at, total: length)
                    HStack {
                        Text(Self.clock(at)); Spacer(); Text("-" + Self.clock(length - at))
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 360)
            }
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.down))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}

// MARK: Home

struct ClimateDetailView: View {
    @Environment(HomeStore.self) private var home

    var body: some View {
        let readings = home.readings
        let rooms = Dictionary(grouping: readings) { $0.room ?? "Elsewhere" }
        List {
            if readings.isEmpty {
                Text(home.status == .ready ? "Nothing in your home measures temperature or humidity." : "Loading…").foregroundStyle(.secondary)
            }
            ForEach(rooms.keys.sorted(), id: \.self) { room in
                Section(room) {
                    ForEach(rooms[room] ?? []) { r in
                        HStack {
                            Text(r.name)
                            Spacer()
                            if let h = r.humidity { Label("\(h)%", systemImage: "humidity").foregroundStyle(.secondary) }
                            if let t = r.temperature { Text(HomeStore.degrees(t)).font(.title3.weight(.semibold).monospacedDigit()) }
                        }
                    }
                }
            }
        }
        .onAppear { home.start() }
    }
}

struct BatteryDetailView: View {
    @Environment(HomeStore.self) private var home

    var body: some View {
        let low = home.lowBatteries
        List {
            if low.isEmpty {
                Label(home.status == .ready ? "Every battery is fine." : "Loading…", systemImage: "battery.100")
            } else {
                Section {
                    ForEach(low) { b in
                        HStack {
                            Text(b.name)
                            Spacer()
                            Text(b.level.map { "\($0)%" } ?? "Low").foregroundStyle(.orange).monospacedDigit()
                        }
                    }
                } footer: { Text("Shown when a device says its battery is low, or it's under 20%.") }
            }
        }
        .onAppear { home.start() }
    }
}

// MARK: Other tiles

struct BinsDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let now = Date()
        let items = model.household.dashboard.recurring
        List {
            if items.isEmpty {
                Text("Add your bin days in the dashboard's settings (the cog in edit mode).").foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                Section {
                    ForEach(item.upcoming(4, from: now), id: \.self) { day in
                        HStack {
                            Text(DayText.relative(day, now: now))
                            Spacer()
                            Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label(item.name, systemImage: item.icon)
                } footer: {
                    Text(item.everyWeeks == 1 ? "Every week" : item.everyWeeks == 2 ? "Every fortnight" : "Every \(item.everyWeeks) weeks")
                }
            }
        }
        .environment(\.locale, Locale(identifier: "en_GB"))
    }
}

/// The guest Wi-Fi code big enough to scan from across the room.
struct WiFiDetailView: View {
    let tile: DashboardTile
    @State private var code: UIImage?

    var body: some View {
        let ssid = tile.options["ssid"] ?? ""
        VStack(spacing: 20) {
            if let code {
                Image(uiImage: code).interpolation(.none).resizable().scaledToFit()
                    .padding(20).background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                    .frame(maxWidth: 420)
                Label(ssid, systemImage: "wifi").font(.title2.weight(.semibold))
                Text("Point a phone's camera at the code to join.").foregroundStyle(.secondary)
            } else {
                Text("Edit this tile to add the Wi-Fi name and password.").foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard !ssid.isEmpty else { return }
            let password = SecretStore.get(SecretStore.wifiAccount(tile.id)) ?? ""
            code = QRCode.image(WiFiQR.payload(ssid: ssid, password: password, hidden: tile.options["hidden"] == "1"))
        }
    }
}

struct ActivityDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let entries = model.household.dashboard.activity
        let now = Date()
        List {
            if entries.isEmpty { Text("Nothing switched yet.").foregroundStyle(.secondary) }
            ForEach(entries) { e in
                HStack(spacing: 12) {
                    Image(systemName: e.icon).foregroundStyle(.secondary).frame(width: 24)
                    Text(e.text)
                    Spacer(minLength: 4)
                    Text(DayText.relative(e.date, now: now) + ", " + WorldClockTile.time(e.date, Calendar.plate.timeZone))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }
}
