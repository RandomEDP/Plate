import EventKit
import PlateCore
import SwiftUI

/// Today's list: reminders due today (repeating ones included) from the chosen Reminders lists, as bullets to tick off.
struct ChecklistTile: View {
    let tile: DashboardTile
    @Environment(\.dashStyle) private var style
    private var store: CalendarStore { CalendarStore.shared }

    var body: some View {
        TileCard {
            VStack(alignment: .leading, spacing: 6) {
                TileHeader(title: tile.name("Today"), symbol: "checklist.checked")
                if CalendarTileSettings.reminderLists(tile.options).isEmpty {
                    Text("Edit this tile to choose a Reminders list, such as one you share.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if store.reminderStatus == .denied || store.reminderStatus == .restricted {
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
                try? await Task.sleep(for: .seconds(2 * 60))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await store.refreshReminders(force: true) }
        }
    }

    @ViewBuilder private func list(now: Date) -> some View {
        let items = CalendarTileSettings.dueToday(store.reminders, options: tile.options, now: now, calendar: .plate)
        let limit = tile.size == .large || tile.size == .tall ? 8 : tile.size == .wide ? 3 : 2
        if items.isEmpty {
            Label("All done for today", systemImage: "checkmark.seal.fill").font(.subheadline).foregroundStyle(.green)
        }
        ForEach(items.prefix(limit)) { r in
            ReminderLine(reminder: r, colour: store.listColours[r.listId] ?? style.accent.color, now: now,
                         compact: tile.size == .small || !(r.dueHasTime || r.isOverdue(now: now, calendar: .plate)))
        }
        if items.count > limit { Text("and \(items.count - limit) more").font(.caption).foregroundStyle(.secondary) }
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
            let items = CalendarTileSettings.dueToday(store.reminders, options: tile.options, now: ctx.date, calendar: .plate)
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
                    ForEach(items) { r in
                        ReminderLine(reminder: r, colour: store.listColours[r.listId] ?? .accentColor, now: ctx.date)
                    }
                }
            }
        }
        .task { await store.refreshReminders(ask: true, force: true) }
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
