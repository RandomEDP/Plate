import CoreImage.CIFilterBuiltins
import Combine
import EventKit
import HomeKit
import Observation
import PlateCore
import SwiftUI

// The tiles beyond the basics: timers, countdowns, the calendar, chores, bin days, guest Wi-Fi, cameras, sensors,
// world clocks, the forecast, routines, light shows, typed commands and the rest.

// MARK: Timers

struct TimerTile: View {
    let tile: DashboardTile
    let editing: Bool
    @Environment(AppModel.self) private var model
    @Environment(DashboardEngine.self) private var engine
    @State private var asking = false
    @State private var text = ""

    private static let quick: [Double] = [1, 3, 5, 10, 15, 20, 30]

    var body: some View {
        let timers = model.household.dashboard.timers
        let room = tile.size == .large || tile.size == .tall ? 6 : 2
        TileCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TileHeader(title: tile.name("Timers"), symbol: "timer")
                    Spacer()
                    Menu {
                        ForEach(Self.quick, id: \.self) { m in
                            Button("\(Int(m)) min") { engine.startTimer(label: "Timer", seconds: m * 60) }
                        }
                        Button("Something else…", systemImage: "keyboard") { asking = true }
                    } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                    .disabled(editing)
                }
                if timers.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Self.quick.prefix(tile.size == .small ? 2 : 5), id: \.self) { m in
                            Button { engine.startTimer(label: "Timer", seconds: m * 60) } label: {
                                Text("\(Int(m))").font(.title3.weight(.semibold).monospacedDigit())
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(Int(m)) minute timer")
                        }
                    }
                    .disabled(editing)
                    Text("Minutes. Tap + for a named one, like “pasta 10 min”.").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        VStack(spacing: 6) {
                            ForEach(timers.prefix(room)) { t in row(t, now: ctx.date) }
                            if timers.count > room { Text("and \(timers.count - room) more").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .alert("New timer", isPresented: $asking) {
            TextField("pasta 10 min", text: $text)
            Button("Start") {
                if let t = TimerParser.parse(text) { engine.startTimer(label: t.label, seconds: t.seconds) }
                else { Feedback.shared.play(.error) }
                text = ""
            }
            Button("Cancel", role: .cancel) { text = "" }
        } message: { Text("Type what it's for and how long: “eggs 6 min”, “1 hr 30”, “tea 4:00”.") }
    }

    private func row(_ t: DashTimer, now: Date) -> some View {
        let done = t.isFinished(now: now)
        return HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 4)
                Circle().trim(from: 0, to: t.progress(now: now)).stroke(done ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 26, height: 26)
            Text(t.label).font(.subheadline.weight(.medium)).lineLimit(1)
            Spacer(minLength: 4)
            Text(done ? "Done" : DashTimer.text(t.remaining(now: now)))
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(done ? Color.green : Color.primary)
            if !done {
                Button { engine.togglePause(t.id) } label: { Image(systemName: t.isPaused ? "play.fill" : "pause.fill") }
                    .accessibilityLabel(t.isPaused ? "Resume \(t.label)" : "Pause \(t.label)")
            }
            Button { engine.cancelTimer(t.id) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .accessibilityLabel("Remove \(t.label) timer")
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Add 1 minute") { engine.addTime(t.id, seconds: 60) }
            Button("Add 5 minutes") { engine.addTime(t.id, seconds: 300) }
        }
    }
}

// MARK: Dates

enum TileDates {
    /// Day-only dates are saved as "2026-12-25".
    static func day(_ text: String?) -> Date? {
        guard let text else { return nil }
        let f = DateFormatter()
        f.calendar = .plate; f.timeZone = Calendar.plate.timeZone; f.locale = Locale(identifier: "en_GB_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: text)
    }

    static func text(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = .plate; f.timeZone = Calendar.plate.timeZone; f.locale = Locale(identifier: "en_GB_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

struct CountdownTile: View {
    let tile: DashboardTile
    var body: some View {
        TileCard {
            TimelineView(.everyMinute) { ctx in
                VStack(alignment: .leading, spacing: 2) {
                    TileHeader(title: tile.name("Countdown"), symbol: "calendar.badge.clock")
                    Spacer(minLength: 0)
                    if let date = TileDates.day(tile.options["date"]) {
                        let c = DayText.countdown(to: date, now: ctx.date)
                        Text(c.number).font(.system(size: 44, weight: .bold)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                        Text(c.caption).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text("Edit this tile to choose the day.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
    }
}

struct WorldClockTile: View {
    let tile: DashboardTile
    var body: some View {
        let zone = TimeZone(identifier: tile.options["tz"] ?? "") ?? .current
        TileCard {
            TimelineView(.everyMinute) { ctx in
                VStack(alignment: .leading, spacing: 2) {
                    TileHeader(title: tile.name(Self.city(zone)), symbol: "globe")
                    Spacer(minLength: 0)
                    Text(Self.time(ctx.date, zone)).font(.system(size: 38, weight: .semibold)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    Text(Self.difference(ctx.date, zone)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(16)
            }
        }
    }

    static func city(_ zone: TimeZone) -> String {
        (zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier).replacingOccurrences(of: "_", with: " ")
    }

    static func time(_ date: Date, _ zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB_POSIX"); f.timeZone = zone; f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// "Tomorrow, 9 hr ahead" / "Today, same time".
    static func difference(_ date: Date, _ zone: TimeZone) -> String {
        let here = Calendar.plate.timeZone
        let diff = zone.secondsFromGMT(for: date) - here.secondsFromGMT(for: date)
        var there = Calendar(identifier: .gregorian)
        there.timeZone = zone
        let d1 = there.dateComponents([.year, .month, .day], from: date), d2 = Calendar.plate.dateComponents([.year, .month, .day], from: date)
        let day = d1 == d2 ? "Today" : diff > 0 ? "Tomorrow" : "Yesterday"
        if diff == 0 { return "\(day), same time" }
        let hours = Double(abs(diff)) / 3600
        let h = hours == hours.rounded() ? "\(Int(hours))" : String(format: "%.1f", hours)
        return "\(day), \(h) hr \(diff > 0 ? "ahead" : "behind")"
    }
}

// MARK: Calendar

/// The device's calendars, for the calendar tiles: every calendar set up in Settings → Calendar, including ones shared
/// with you in iCloud, Google or Exchange calendars and subscribed ones. Asked for once; Plate only reads them.
@MainActor
@Observable
final class CalendarStore {
    static let shared = CalendarStore()

    struct Source: Identifiable, Hashable {
        var id: String
        var title: String
        /// The account it belongs to, such as iCloud or Google.
        var account: String
        var color: Color
        var subscribed: Bool
    }

    var status = EKEventStore.authorizationStatus(for: .event)
    private(set) var events: [CalendarEvent] = []
    private(set) var calendars: [Source] = []
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var fetched: Date?

    var colours: [String: Color] { Dictionary(calendars.map { ($0.id, $0.color) }, uniquingKeysWith: { a, _ in a }) }
    var canRead: Bool { status == .fullAccess }

    /// Reads the next month of events from every calendar. Each tile picks its own calendars and days from these.
    func refresh(force: Bool = false) async {
        if status == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
            status = EKEventStore.authorizationStatus(for: .event)
        }
        guard status == .fullAccess else { events = []; calendars = []; return }
        if !force, let fetched, Date().timeIntervalSince(fetched) < 60 { return }
        fetched = Date()
        store.refreshSourcesIfNecessary()
        let cals = store.calendars(for: .event)
        calendars = cals.map {
            Source(id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "On this iPad",
                   color: Color(cgColor: $0.cgColor), subscribed: $0.isSubscribed)
        }
        .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
        let start = Calendar.plate.startOfDay(for: Date())
        let end = Calendar.plate.date(byAdding: .day, value: 32, to: start) ?? start
        let found = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
        events = found.prefix(400).enumerated().map { i, e in
            CalendarEvent(id: "\(i)-\(e.eventIdentifier ?? "")-\(e.startDate.timeIntervalSince1970)",
                          calendarId: e.calendar.calendarIdentifier, title: e.title ?? "Event",
                          start: e.startDate, end: e.endDate, allDay: e.isAllDay, location: e.location)
        }
    }
}

struct CalendarTile: View {
    let tile: DashboardTile
    @Environment(\.dashStyle) private var style
    private var calendar: CalendarStore { CalendarStore.shared }

    var body: some View {
        TileCard {
            VStack(alignment: .leading, spacing: 6) {
                TileHeader(title: tile.name("Calendar"), symbol: "calendar")
                if calendar.status == .denied || calendar.status == .restricted || calendar.status == .writeOnly {
                    Text("Plate isn't allowed to see your calendars. Turn on Full Access in Settings → Privacy & Security → Calendars → Plate.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    TimelineView(.everyMinute) { ctx in list(now: ctx.date) }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .task {
            while !Task.isCancelled {
                await calendar.refresh()
                try? await Task.sleep(for: .seconds(5 * 60))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await calendar.refresh(force: true) }
        }
    }

    @ViewBuilder private func list(now: Date) -> some View {
        let shown = CalendarTileSettings.events(calendar.events, options: tile.options, now: now, calendar: .plate)
        let limit = tile.size == .large || tile.size == .tall ? 7 : tile.size == .wide ? 3 : 2
        let colours = calendar.colours
        if shown.isEmpty {
            let days = CalendarTileSettings.days(tile.options)
            Text(days == 1 ? "Nothing else today." : "Nothing in the next \(days) days.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(shown.prefix(limit).enumerated()), id: \.element.id) { i, e in
                let heading = CalendarTileSettings.dayHeading(e.start, now: now, calendar: .plate)
                if tile.size != .small, i == 0 || heading != CalendarTileSettings.dayHeading(shown[i - 1].start, now: now, calendar: .plate) {
                    Text(heading).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, i == 0 ? 0 : 4)
                }
                HStack(spacing: 8) {
                    Capsule().fill(colours[e.calendarId] ?? style.accent.color).frame(width: 4, height: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(e.title).font(.subheadline.weight(.medium)).lineLimit(1)
                        Text(detail(e, now: now)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    /// "19:00 to 20:30 · The Pub", "All day", or "Tomorrow at 09:00" on a small tile (which has no day headings).
    private func detail(_ e: CalendarEvent, now: Date) -> String {
        let time: String
        if e.allDay {
            time = "All day"
        } else if e.start <= now {
            time = "Now, until \(HeaderClock.timeText(e.end, calendar: .plate))"
        } else {
            time = "\(HeaderClock.timeText(e.start, calendar: .plate)) to \(HeaderClock.timeText(e.end, calendar: .plate))"
        }
        var parts = [tile.size == .small ? CalendarTileSettings.dayHeading(e.start, now: now, calendar: .plate) + ", " + time : time]
        if tile.size != .small, let place = e.location?.split(separator: "\n").first, !place.isEmpty { parts.append(String(place)) }
        return parts.joined(separator: " · ")
    }
}

/// The calendar tile's settings: which calendars (shared ones included) and how far ahead.
struct CalendarSettings: View {
    @Binding var options: [String: String]
    private var store: CalendarStore { CalendarStore.shared }

    var body: some View {
        Section {
            Picker("Show", selection: Binding(get: { CalendarTileSettings.days(options) },
                                              set: { options["days"] = $0 == CalendarTileSettings.defaultDays ? nil : "\($0)" })) {
                ForEach(CalendarTileSettings.dayChoices, id: \.self) { d in
                    Text(d == 1 ? "Today only" : d == 7 ? "The next week" : d == 14 ? "The next two weeks" : d == 31 ? "The next month" : "The next \(d) days").tag(d)
                }
            }
        } header: { Text("How far ahead") }
        Section {
            if store.canRead {
                let all = store.calendars.map(\.id)
                let chosen = CalendarTileSettings.calendars(options)
                Button { CalendarTileSettings.setCalendars([], in: &options) } label: { tick("Every calendar", chosen.isEmpty) }
                    .foregroundStyle(.primary)
                ForEach(Dictionary(grouping: store.calendars, by: \.account).sorted { $0.key < $1.key }, id: \.key) { account, cals in
                    ForEach(cals) { c in
                        Button { CalendarTileSettings.toggle(c.id, all: all, in: &options) } label: {
                            HStack {
                                Circle().fill(c.color).frame(width: 12, height: 12)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(c.title)
                                    Text(c.subscribed ? "\(account) · subscribed" : account).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if chosen.isEmpty || chosen.contains(c.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            } else if store.status == .notDetermined {
                Button("Allow Plate to see your calendars") { Task { await store.refresh(force: true) } }
            } else {
                Text("Plate isn't allowed to see your calendars. Turn on Full Access in Settings → Privacy & Security → Calendars → Plate.")
            }
        } header: { Text("Calendars") } footer: {
            Text("Every calendar on this iPad is here, including ones shared with you. A calendar someone shares in iCloud appears once you've accepted the invitation in the Calendar app. Google and Outlook calendars appear once the account is added in Settings → Calendar → Accounts.")
        }
        .task { await store.refresh(force: true) }
    }

    private func tick(_ title: String, _ on: Bool) -> some View {
        HStack { Text(title); Spacer(); if on { Image(systemName: "checkmark").foregroundStyle(.tint) } }
    }
}

// MARK: Chores and bins

struct ChoresTile: View {
    let tile: DashboardTile
    let editing: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let chores = model.household.dashboard.chores
        let now = Date()
        TileCard {
            VStack(alignment: .leading, spacing: 8) {
                TileHeader(title: tile.name("Chores"), symbol: "checklist")
                if chores.isEmpty {
                    Text("Add chores in the dashboard's settings (the cog in edit mode), and say whose turn it is.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(chores.prefix(tile.size == .large || tile.size == .tall ? 6 : 2)) { c in
                    let done = c.isDone(on: now)
                    Button { toggle(c) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(done ? Color.green : Color.secondary)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(c.name).font(.subheadline.weight(.medium)).strikethrough(done).lineLimit(1)
                                Text(Self.detail(c, done: done, now: now)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: c.icon).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(editing)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }

    static func detail(_ c: Chore, done: Bool, now: Date) -> String {
        let who = c.assignee(on: now)
        if done { return "Done" + (c.lastDoneBy.map { " by \($0)" } ?? "") }
        let left = c.daysLeft(on: now)
        let when = left <= 1 ? "due today" : "\(left) days left"
        return who.map { "\($0), \(when)" } ?? when.capitalizedFirst
    }

    private func toggle(_ c: Chore) {
        guard let i = model.household.dashboard.chores.firstIndex(where: { $0.id == c.id }) else { return }
        let now = Date()
        if c.isDone(on: now) {
            model.household.dashboard.chores[i].lastDone = nil
            model.household.dashboard.chores[i].lastDoneBy = nil
            Feedback.shared.play(.off)
        } else {
            model.household.dashboard.chores[i].lastDone = now
            model.household.dashboard.chores[i].lastDoneBy = c.assignee(on: now)
            Feedback.shared.play(.on)
            model.household.dashboard.log("\(c.name) done" + (c.assignee(on: now).map { " by \($0)" } ?? ""), icon: c.icon)
        }
    }
}

struct BinsTile: View {
    let tile: DashboardTile
    @Environment(AppModel.self) private var model

    var body: some View {
        TileCard {
            TimelineView(.everyMinute) { ctx in
                let items = model.household.dashboard.recurring
                    .map { (item: $0, next: $0.next(onOrAfter: ctx.date)) }.sorted { $0.next < $1.next }
                VStack(alignment: .leading, spacing: 8) {
                    TileHeader(title: tile.name("Bin days"), symbol: "trash")
                    if items.isEmpty {
                        Text("Add your bin days in the dashboard's settings (the cog in edit mode).")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(items.prefix(tile.size == .large || tile.size == .tall ? 6 : 2), id: \.item.id) { entry in
                        let soon = Calendar.plate.isDate(entry.next, inSameDayAs: ctx.date)
                            || Calendar.plate.isDate(entry.next, inSameDayAs: ctx.date.addingTimeInterval(86_400))
                        HStack(spacing: 10) {
                            Image(systemName: entry.item.icon)
                                .foregroundStyle(entry.item.tint?.color ?? Color.secondary)
                                .frame(width: 24)
                            Text(entry.item.name).font(.subheadline.weight(.medium)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(DayText.relative(entry.next, now: ctx.date))
                                .font(.subheadline.weight(soon ? .bold : .regular))
                                .foregroundStyle(soon ? Color.primary : Color.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
        }
    }
}

// MARK: Guest Wi-Fi

/// Small secrets kept in the keychain on this device (the guest Wi-Fi password), never in the household file.
enum SecretStore {
    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Keychain.service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ account: String, _ value: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Keychain.service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func wifiAccount(_ tile: UUID) -> String { "wifi-\(tile.uuidString)" }
}

enum QRCode {
    static func image(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct WiFiTile: View {
    let tile: DashboardTile
    @State private var code: UIImage?

    var body: some View {
        let ssid = tile.options["ssid"] ?? ""
        TileCard(alignment: .center) {
            VStack(spacing: 8) {
                if let code {
                    Image(uiImage: code).interpolation(.none).resizable().scaledToFit()
                        .padding(8).background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    if tile.size != .small {
                        Label(tile.name(ssid), systemImage: "wifi").font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("Point a phone camera here to join").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else {
                    Image(systemName: "wifi").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Edit this tile to add the Wi-Fi name and password.").font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(12)
        }
        .task(id: tile.updatedAt) {
            guard !ssid.isEmpty else { code = nil; return }
            let password = SecretStore.get(SecretStore.wifiAccount(tile.id)) ?? ""
            code = QRCode.image(WiFiQR.payload(ssid: ssid, password: password, hidden: tile.options["hidden"] == "1"))
        }
    }
}

// MARK: Cameras, sensors, whole home

struct CameraTile: View {
    let tile: DashboardTile
    let editing: Bool
    @Environment(HomeStore.self) private var home
    @Environment(\.dashStyle) private var style
    @State private var feed = CameraFeed()

    var body: some View {
        let accessory = home.accessory(tile.ref)
        Button { if feed.isLive { feed.stopLive() } else { feed.startLive() } } label: {
            ZStack(alignment: .bottomLeading) {
                Color.black
                if feed.source != nil {
                    CameraSourceView(source: feed.source)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "video.slash").font(.title)
                        Text(feed.problem ?? (accessory == nil ? "Camera not found" : "Waiting for a picture…")).font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
                HStack {
                    Text(tile.name(accessory?.name)).font(.subheadline.weight(.semibold))
                    Spacer()
                    if feed.isLive {
                        Text("LIVE").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                    } else {
                        Image(systemName: "play.circle.fill")
                    }
                }
                .foregroundStyle(.white)
                .padding(10)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(editing || accessory == nil)
        .task(id: "\(tile.ref ?? "")-\(home.status == .ready)") {
            feed.attach(home.accessory(tile.ref))
            // A fresh still every 20 seconds; tap for live video.
            while !Task.isCancelled {
                feed.snapshot()
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .onDisappear { if feed.isLive { feed.stopLive() } }
    }
}

struct ClimateTile: View {
    let tile: DashboardTile
    @Environment(HomeStore.self) private var home

    var body: some View {
        let readings = home.readings
        TileCard {
            VStack(alignment: .leading, spacing: 6) {
                TileHeader(title: tile.name("Climate"), symbol: "thermometer.medium")
                if readings.isEmpty {
                    Text(home.status == .ready ? "Nothing in your home measures temperature or humidity." : "Loading…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(readings.prefix(tile.size == .large || tile.size == .tall ? 7 : 3)) { r in
                    HStack {
                        Text(r.room ?? r.name).font(.subheadline).lineLimit(1)
                        Spacer(minLength: 4)
                        if let h = r.humidity { Label("\(h)%", systemImage: "humidity").font(.caption).foregroundStyle(.secondary) }
                        if let t = r.temperature { Text(HomeStore.degrees(t)).font(.subheadline.weight(.semibold).monospacedDigit()) }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .onAppear { home.start() }
    }
}

struct AllOffTile: View {
    let tile: DashboardTile
    let editing: Bool
    @Environment(HomeStore.self) private var home

    var body: some View {
        let on = home.lightsOnCount
        Button { Task { await home.allLightsOff() } } label: {
            TileCard(lit: (on ?? 0) > 0) {
                ControlTileLabel(symbol: (on ?? 0) > 0 ? "lightbulb.fill" : "lightbulb.slash", title: tile.name("All lights"),
                                 detail: on.map { $0 == 0 ? "All off" : $0 == 1 ? "1 on · tap for off" : "\($0) on · tap for off" } ?? "Loading…")
            }
        }
        .buttonStyle(.plain)
        .disabled(editing || (on ?? 0) == 0)
        .onAppear { home.start() }
    }
}

struct BatteryTile: View {
    let tile: DashboardTile
    @Environment(HomeStore.self) private var home

    var body: some View {
        let low = home.lowBatteries
        TileCard(lit: !low.isEmpty, litColor: RGB(hex: "#FF9F0A")) {
            if low.isEmpty {
                ControlTileLabel(symbol: "battery.100", title: tile.name("Batteries"), detail: home.status == .ready ? "All fine" : "Loading…")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    TileHeader(title: low.count == 1 ? "1 low battery" : "\(low.count) low batteries", symbol: "battery.25")
                    ForEach(low.prefix(tile.size == .small ? 2 : 5)) { b in
                        Text(b.name + (b.level.map { " (\($0)%)" } ?? "")).font(.subheadline).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
        }
        .onAppear { home.start() }
    }
}

// MARK: Photos

struct PhotoFrameTile: View {
    let tile: DashboardTile
    @Environment(PhotoStore.self) private var photos
    @Environment(\.dashStyle) private var style
    @State private var image: UIImage?
    @State private var shownId: String?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(Color.gray.opacity(0.25))
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                        .id(shownId).transition(.opacity)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle").font(.title)
                        Text(photos.canRead ? "No pictures in this album" : "Allow Photos in the dashboard's settings").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .animation(.easeInOut(duration: 1), value: shownId)
        }
        .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .task(id: tile.ref) {
            guard photos.canRead else { return }
            var show = Slideshow(items: photos.photoIds(in: tile.ref))
            let seconds = Double(tile.options["seconds"] ?? "") ?? 30
            while !Task.isCancelled {
                if let id = show.next(), let picture = await photos.image(id, size: CGSize(width: 900, height: 900)) {
                    shownId = id
                    image = picture
                }
                try? await Task.sleep(for: .seconds(max(5, seconds)))
            }
        }
    }
}

// MARK: Weather extras

struct ForecastTile: View {
    let tile: DashboardTile
    @Environment(WeatherStore.self) private var weather

    var body: some View {
        TileCard {
            GeometryReader { geo in
                let days = weather.now?.days ?? []
                let count = max(2, min(7, Int(geo.size.width / 58)))
                VStack(alignment: .leading, spacing: 6) {
                    if geo.size.height > 170 { TileHeader(title: tile.name("This week"), symbol: "calendar.day.timeline.left") }
                    if days.isEmpty {
                        Text(weather.problem ?? "Getting the forecast…").font(.caption).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 0) {
                            ForEach(Array(days.prefix(count).enumerated()), id: \.offset) { i, d in
                                VStack(spacing: 5) {
                                    Text(i == 0 ? "Today" : String(DayText.weekday(d.date).prefix(3)))
                                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    Image(systemName: d.symbol).symbolRenderingMode(.multicolor).font(.title3).frame(height: 26)
                                    Text(WeatherText.temperature(d.high)).font(.subheadline.weight(.semibold).monospacedDigit())
                                    Text(WeatherText.temperature(d.low)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    if geo.size.height > 130 {
                                        Text(d.precipitationChance >= 0.2 ? "\(Int((d.precipitationChance * 100).rounded()))%" : " ")
                                            .font(.caption2).foregroundStyle(.blue)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .padding(12)
            }
        }
        .task {
            while !Task.isCancelled {
                await weather.refresh()
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }
}

struct SunTile: View {
    let tile: DashboardTile
    @Environment(WeatherStore.self) private var weather

    var body: some View {
        TileCard {
            TimelineView(.everyMinute) { ctx in
                let w = weather.now
                if let next = WeatherText.nextSun(sunrise: w?.sunrise, sunset: w?.sunset, tomorrowSunrise: w?.tomorrowSunrise, now: ctx.date) {
                    ControlTileLabel(symbol: next.title == "Sunrise" ? "sunrise.fill" : "sunset.fill",
                                     title: "\(next.title) \(WorldClockTile.time(next.at, Calendar.plate.timeZone))",
                                     detail: "in " + DashTimer.words((next.at.timeIntervalSince(ctx.date) / 60).rounded(.up) * 60))
                } else {
                    ControlTileLabel(symbol: "sun.horizon", title: tile.name("Sun"), detail: weather.problem == nil ? "Loading…" : "No weather")
                }
            }
        }
        .task { await weather.refresh() }
    }
}

// MARK: Kitchen

struct MacrosTile: View {
    let tile: DashboardTile
    @Environment(AppModel.self) private var model

    var body: some View {
        let eaten = model.totals(on: Date())
        let target = model.targets
        TileCard {
            VStack(alignment: .leading, spacing: 8) {
                TileHeader(title: tile.name("Today's food"), symbol: "flame")
                bar("Calories", eaten.kcal, target.kcal, unit: "")
                bar("Protein", eaten.protein, target.protein, unit: " g")
                if tile.size == .large || tile.size == .tall {
                    bar("Carbs", eaten.carbs, target.carbs, unit: " g")
                    bar("Fat", eaten.fat, target.fat, unit: " g")
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }

    private func bar(_ name: String, _ value: Double, _ target: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(.caption.weight(.semibold))
                Spacer()
                Text("\(Int(value.rounded()))\(unit) of \(Int(target.rounded()))\(unit)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: min(1, target > 0 ? value / target : 0))
        }
    }
}

struct CookNowTile: View {
    let tile: DashboardTile
    @Environment(AppModel.self) private var model

    var body: some View {
        let best = Suggestions.rank(model.recipes, inventory: model.household.inventory,
                                    servings: model.household.planSettings.people, now: Date()).first
        TileCard {
            VStack(alignment: .leading, spacing: 4) {
                TileHeader(title: tile.name("Cook now"), symbol: "frying.pan")
                Spacer(minLength: 0)
                if let best {
                    Text(best.recipe.name).font(.title3.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.8)
                    Text(best.missing.isEmpty ? "You have everything for it"
                         : "Missing " + Briefing.list(best.missing.prefix(3).map { $0.name.lowercased() }))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("Add some recipes and stock the kitchen first.").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }
}

// MARK: Buttons

struct ShortcutTile: View {
    let tile: DashboardTile
    let editing: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        let shortcut = tile.options["shortcut"] ?? ""
        let link = tile.options["url"] ?? ""
        Button {
            Feedback.shared.play(.tap)
            if !shortcut.isEmpty {
                var c = URLComponents(string: "shortcuts://run-shortcut")
                c?.queryItems = [URLQueryItem(name: "name", value: shortcut)]
                if let url = c?.url { openURL(url) }
            } else if let url = URL(string: link.contains("://") ? link : "https://" + link), !link.isEmpty {
                openURL(url)
            }
        } label: {
            TileCard {
                ControlTileLabel(symbol: shortcut.isEmpty ? "link" : "square.2.layers.3d.top.filled", title: tile.name("Shortcut"),
                                 detail: shortcut.isEmpty ? (link.isEmpty ? "Edit to set it up" : "Open") : "Run shortcut")
            }
        }
        .buttonStyle(.plain)
        .disabled(editing || (shortcut.isEmpty && link.isEmpty))
    }
}

struct RoutineTile: View {
    let tile: DashboardTile
    let editing: Bool
    @Environment(AppModel.self) private var model
    @Environment(DashboardEngine.self) private var engine
    @Environment(\.dashStyle) private var style

    var body: some View {
        let routine = model.household.dashboard.routines.first { $0.id.uuidString == tile.ref }
        if let routine {
            let running = engine.runningRoutine == routine.id
            let schedule = model.household.dashboard.schedules.first { $0.routineId == routine.id && $0.enabled }
            Button { Task { await engine.run(routine) } } label: {
                TileCard(lit: running, litColor: style.accent) {
                    ControlTileLabel(symbol: routine.icon, title: tile.name(routine.name),
                                     detail: running ? "Running…" : schedule?.summary ?? "\(routine.actions.count) step\(routine.actions.count == 1 ? "" : "s")")
                }
            }
            .buttonStyle(.plain)
            .disabled(editing || running)
        } else {
            TileCard { ControlTileLabel(symbol: "questionmark.square.dashed", title: tile.name(), detail: "Routine deleted", dimmed: true) }
        }
    }
}

struct LightShowTile: View {
    let tile: DashboardTile
    let editing: Bool
    @Environment(HomeStore.self) private var home
    @Environment(DashboardEngine.self) private var engine

    var body: some View {
        let show = LightShow(rawValue: tile.options["show"] ?? "") ?? .party
        let on = engine.lightShow.active == show
        Button {
            home.start()
            if on { engine.lightShow.stop(home: home); Feedback.shared.play(.off) }
            else { engine.lightShow.start(show, home: home); Feedback.shared.play(.scene) }
        } label: {
            TileCard(lit: on, litColor: RGB(hex: "#BF5AF2")) {
                ControlTileLabel(symbol: show.icon, title: tile.name(show.title), detail: on ? "Tap to stop" : "Light show")
            }
        }
        .buttonStyle(.plain)
        .disabled(editing)
    }
}

struct BriefingTile: View {
    let tile: DashboardTile
    let editing: Bool
    @Environment(DashboardEngine.self) private var engine

    var body: some View {
        Button { Feedback.shared.play(.tap); engine.briefing() } label: {
            TileCard { ControlTileLabel(symbol: "speaker.wave.2.bubble", title: tile.name("Briefing"), detail: "Hear today") }
        }
        .buttonStyle(.plain)
        .disabled(editing)
        .contextMenu { Button("Stop talking", systemImage: "speaker.slash") { Feedback.shared.stopSpeaking() } }
    }
}

// MARK: Lists and text

struct ActivityTile: View {
    let tile: DashboardTile
    @Environment(AppModel.self) private var model

    var body: some View {
        let entries = model.household.dashboard.activity
        TileCard {
            VStack(alignment: .leading, spacing: 6) {
                TileHeader(title: tile.name("Recently"), symbol: "clock.arrow.circlepath")
                if entries.isEmpty { Text("Nothing switched yet.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(entries.prefix(tile.size == .large || tile.size == .tall ? 8 : 3)) { e in
                    HStack(spacing: 8) {
                        Image(systemName: e.icon).font(.caption).foregroundStyle(.secondary).frame(width: 18)
                        Text(e.text).font(.subheadline).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(WorldClockTile.time(e.date, Calendar.plate.timeZone)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }
}

/// A box to type what you want. Plate matches the words to your home; no AI and no internet.
struct CommandTile: View {
    let tile: DashboardTile
    let editing: Bool
    @Environment(DashboardEngine.self) private var engine
    @State private var text = ""
    @State private var reply: String?
    @FocusState private var focused: Bool

    var body: some View {
        TileCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "text.cursor").foregroundStyle(.secondary)
                    TextField("kitchen off, lamp 30%, pasta 10 min…", text: $text)
                        .focused($focused)
                        .submitLabel(.go)
                        .autocorrectionDisabled()
                        .onSubmit(send)
                    if !text.isEmpty {
                        Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title2) }.buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                .disabled(editing)
                Text(reply ?? "Type what you'd like. Join several with commas: “lights off, play Blue”.")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }

    private func send() {
        let typed = text
        guard !typed.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        text = ""
        Task { reply = await engine.command(typed) }
    }
}

struct HeadingTile: View {
    let tile: DashboardTile
    @Environment(\.dashStyle) private var style
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = style.backgroundIsDark ?? (scheme == .dark)
        HStack(spacing: 10) {
            if let icon = tile.icon { Image(systemName: icon) }
            Text(tile.name()).lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .font(.system(size: 30, weight: .bold))
        .foregroundStyle(tile.tint?.color ?? (dark ? Color.white : Color.black))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.horizontal, 4).padding(.bottom, 6)
    }
}

struct SpacerTile: View {
    let editing: Bool
    @Environment(\.dashStyle) private var style
    var body: some View {
        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            .strokeBorder(Color.secondary.opacity(editing ? 0.6 : 0), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .overlay { if editing { Text("Gap").font(.caption).foregroundStyle(.secondary) } }
    }
}
