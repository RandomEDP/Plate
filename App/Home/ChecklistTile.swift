import EventKit
import PlateCore
import SwiftUI

/// Today's list: reminders due today (repeating ones included) from the chosen Reminders lists, as bullets to tick off,
/// with today's calendar events slotted in by time.
struct ChecklistTile: View {
    let tile: DashboardTile
    @Environment(\.dashStyle) private var style
    private var store: CalendarStore { CalendarStore.shared }

    var body: some View {
        TileCard {
            VStack(alignment: .leading, spacing: 6) {
                TileHeader(title: tile.name("Today"), symbol: "checklist.checked")
                let lists = !CalendarTileSettings.reminderLists(tile.options).isEmpty
                if !lists && !CalendarTileSettings.showsEvents(tile.options) {
                    Text("Edit this tile to choose a Reminders list, such as one you share.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if lists && (store.reminderStatus == .denied || store.reminderStatus == .restricted) {
                    Text("Plate isn't allowed to see your reminders. Turn on Full Access in Settings → Privacy & Security → Reminders → Plate.")
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
                await store.refreshReminders(ask: true)
                if CalendarTileSettings.showsEvents(tile.options) { await store.refresh() }
                try? await Task.sleep(for: .seconds(2 * 60))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task {
                await store.refreshReminders(force: true)
                await store.refresh(force: true)
            }
        }
    }

    @ViewBuilder private func list(now: Date) -> some View {
        let items = CalendarTileSettings.todayList(events: store.events, reminders: store.reminders, options: tile.options,
                                                   now: now, calendar: .plate)
        let limit = tile.size == .large || tile.size == .tall ? 8 : tile.size == .wide ? 3 : 2
        let stats = Habits.stats(store.done, options: tile.options, now: now, calendar: .plate)
        if items.isEmpty {
            Label("All done for today", systemImage: "checkmark.seal.fill").font(.subheadline).foregroundStyle(.green)
        }
        ForEach(items.prefix(limit)) { item in
            switch item {
            case .event(let e):
                HStack(spacing: 8) {
                    Capsule().fill(store.colours[e.calendarId] ?? style.accent.color).frame(width: 4, height: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(e.title).font(.subheadline.weight(.medium)).lineLimit(1)
                        if tile.size != .small {
                            Text(Self.when(e, now: now)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            case .reminder(let r):
                ReminderLine(reminder: r, colour: store.listColours[r.listId] ?? style.accent.color, now: now,
                             compact: tile.size == .small || !(r.dueHasTime || r.isOverdue(now: now, calendar: .plate)),
                             streak: Habits.streak(for: r.title, in: stats))
            }
        }
        if items.count > limit { Text("and \(items.count - limit) more").font(.caption).foregroundStyle(.secondary) }
    }

    /// "All day", "Now, until 14:00" or "18:00 to 19:30".
    static func when(_ e: CalendarEvent, now: Date) -> String {
        let t = { (d: Date) in HeaderClock.timeText(d, calendar: .plate) }
        if e.allDay { return "All day" }
        if e.start <= now { return "Now, until \(t(e.end))" }
        return "\(t(e.start)) to \(t(e.end))"
    }
}

/// The bigger view of today's list: everything due today, and a box to add one, repeating if you like.
struct ChecklistDetailView: View {
    let tile: DashboardTile
    @State private var title = ""
    @State private var repeats: ReminderRepeat = .never
    @State private var listId: String?
    private var store: CalendarStore { CalendarStore.shared }

    var body: some View {
        let lists = store.reminderLists.filter { CalendarTileSettings.reminderLists(tile.options).contains($0.id) }
        TimelineView(.everyMinute) { ctx in
            let items = CalendarTileSettings.todayList(events: store.events, reminders: store.reminders, options: tile.options,
                                                       now: ctx.date, calendar: .plate)
            let stats = Habits.stats(store.done, options: tile.options, now: ctx.date, calendar: .plate)
            List {
                if !lists.isEmpty {
                    Section {
                        TextField("Add something, such as Drink a protein shake", text: $title)
                            .submitLabel(.done)
                            .onSubmit { add(lists) }
                        Picker("Repeat", selection: $repeats) {
                            ForEach(ReminderRepeat.allCases) { r in
                                Text(r.title(startingOn: ctx.date, calendar: .plate)).tag(r)
                            }
                        }
                        if lists.count > 1 {
                            Picker("List", selection: Binding(get: { listId ?? lists[0].id }, set: { listId = $0 })) {
                                ForEach(lists) { Text($0.title).tag($0.id) }
                            }
                        }
                        Button("Add to today's list", systemImage: "plus.circle.fill") { add(lists) }
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    } footer: {
                        Text("Repeating ones come back by themselves on their next day once ticked off. They're ordinary Reminders, so you can change them in the Reminders app too.")
                    }
                }
                Section("Today") {
                    if items.isEmpty { Label("All done for today", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                    ForEach(items) { item in
                        switch item {
                        case .event(let e): EventRow(event: e, now: ctx.date)
                        case .reminder(let r):
                            ReminderLine(reminder: r, colour: store.listColours[r.listId] ?? .accentColor, now: ctx.date,
                                         streak: Habits.streak(for: r.title, in: stats))
                        }
                    }
                }
                if !stats.isEmpty {
                    Section {
                        ForEach(stats) { s in
                            HStack(spacing: 12) {
                                Image(systemName: s.doneToday ? "checkmark.circle.fill" : "circle.dashed")
                                    .foregroundStyle(s.doneToday ? Color.green : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.title)
                                    Text(Habits.summary(s, now: ctx.date, calendar: .plate)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                WeekDots(title: s.title, done: store.done, now: ctx.date)
                            }
                        }
                    } header: { Text("How it's going") } footer: {
                        Text("From what's been ticked off in the last 30 days, here or on anyone's phone.")
                    }
                }
            }
        }
        .task {
            await store.refreshReminders(ask: true, force: true)
            if CalendarTileSettings.showsEvents(tile.options) { await store.refresh(force: true) }
        }
    }

    private func add(_ lists: [CalendarStore.Source]) {
        guard let target = listId ?? lists.first?.id else { return }
        let text = title, rep = repeats
        title = ""
        repeats = .never
        // Added from here it's for today: a one-off is due today, a repeating one starts today.
        Task { await store.add(text, to: target, due: Date(), repeats: rep) }
    }
}

/// Seven dots for the last seven days, filled where it was done.
private struct WeekDots: View {
    let title: String
    let done: [ReminderDone]
    let now: Date

    var body: some View {
        let key = Habits.key(title)
        let days = Set(done.filter { Habits.key($0.title) == key }.map { Calendar.plate.startOfDay(for: $0.completed) })
        let today = Calendar.plate.startOfDay(for: now)
        HStack(spacing: 4) {
            ForEach((0..<7).reversed(), id: \.self) { back in
                let day = Calendar.plate.date(byAdding: .day, value: -back, to: today) ?? today
                Circle().fill(days.contains(day) ? Color.green : Color.secondary.opacity(0.25)).frame(width: 9, height: 9)
            }
        }
        .accessibilityHidden(true)
    }
}
