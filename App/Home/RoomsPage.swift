import HomeKit
import PlateCore
import SwiftUI

// A page split into one column per room (three in Ethan's flat), each holding every control in that room: an
// everything on/off switch, the room's scenes and a tile for each light, plug, blind, thermostat, lock and sensor.
// Which rooms and in what order is saved on the page (`DashboardPage.rooms`); the choosing is in `RoomsPage` (PlateCore).

struct RoomsPageView: View {
    let page: DashboardPage
    let width: CGFloat
    let spacing: CGFloat
    let editing: Bool
    let chooseRooms: () -> Void
    @Environment(HomeStore.self) private var home

    var body: some View {
        let available = home.rooms.map { RoomsPage.Room(id: $0.uniqueIdentifier.uuidString, name: $0.name) }
        let columns = RoomsPage.columns(chosen: page.rooms, available: available).compactMap { home.room($0.id) }
        VStack(spacing: spacing) {
            if editing {
                Button(action: chooseRooms) { Label("Choose rooms", systemImage: "checklist") }
                    .buttonStyle(.bordered)
            }
            if columns.isEmpty {
                ContentUnavailableView("No rooms yet", systemImage: "house",
                                       description: Text("Rooms come from Apple's Home app. Put your accessories in rooms there and they'll show up here."))
                    .frame(maxHeight: .infinity)
            } else if RoomsPage.sideBySide(width: Double(width), rooms: columns.count) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(columns, id: \.uniqueIdentifier) { room in
                        RoomColumn(room: room, spacing: spacing, scrolls: true)
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: spacing) {
                        ForEach(columns, id: \.uniqueIdentifier) { room in
                            RoomColumn(room: room, spacing: spacing, scrolls: false)
                        }
                    }
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, spacing)
        .padding(.top, spacing / 2)
        .padding(.bottom, spacing + 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// One room: its name and an everything switch at the top, its scenes, then a tile for each accessory.
private struct RoomColumn: View {
    let room: HMRoom
    let spacing: CGFloat
    /// Side by side, each column scrolls on its own; stacked, the whole page scrolls instead.
    let scrolls: Bool
    @Environment(HomeStore.self) private var home
    @Environment(\.dashStyle) private var style

    var body: some View {
        let accessories = RoomsPage.sorted(home.accessories(in: room).map {
            AccessorySummary(id: $0.uniqueIdentifier.uuidString, name: $0.name, category: HomeStore.category(of: $0))
        })
        let scenes = home.scenes.filter { Self.scene($0, isOnlyIn: room) }
        VStack(alignment: .leading, spacing: spacing * 0.75) {
            header
            if !scenes.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(scenes, id: \.uniqueIdentifier) { scene in
                            Button { Task { await home.run(scene) } } label: {
                                Label(scene.name, systemImage: SceneTile.symbol(for: scene))
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            if accessories.isEmpty {
                Text("Nothing in this room yet.").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if scrolls {
                ScrollView { grid(accessories).padding(.bottom, 8) }
                    .scrollIndicators(.hidden)
            } else {
                grid(accessories)
            }
        }
        .padding(spacing * 0.75)
        .frame(maxWidth: .infinity, maxHeight: scrolls ? .infinity : nil, alignment: .top)
        .background(RoundedRectangle(cornerRadius: style.cornerRadius + 6, style: .continuous).fill(.ultraThinMaterial).opacity(0.7))
    }

    private var header: some View {
        let switchable = !home.switchables(in: room).isEmpty
        let on = home.isOn(room)
        return HStack(alignment: .firstTextBaseline) {
            Text(room.name).font(.title2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            if switchable {
                Button { Task { await home.toggle(room) } } label: {
                    Label(on ? "All off" : "All on", systemImage: on ? "lightbulb.2.fill" : "lightbulb.2")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(on ? AnyShapeStyle(style.onColor.color) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                        .foregroundStyle(on ? (style.onColor.wantsDarkText ? Color.black : Color.white) : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func grid(_ accessories: [AccessorySummary]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: spacing * 0.6)], spacing: spacing * 0.6) {
            ForEach(accessories, id: \.id) { a in
                AccessoryTile(tile: DashboardTile(id: UUID(uuidString: a.id) ?? UUID(), kind: .accessory, ref: a.id, title: a.name),
                              editing: false)
                    .frame(height: 110)
            }
        }
    }

    /// A scene belongs to a room when everything it changes is in that room.
    static func scene(_ scene: HMActionSet, isOnlyIn room: HMRoom) -> Bool {
        let rooms = scene.actions.compactMap { action -> HMRoom? in
            (action as? HMCharacteristicWriteAction<NSCopying>)?.characteristic.service?.accessory?.room
        }
        return !rooms.isEmpty && rooms.count == scene.actions.count && rooms.allSatisfy { $0 == room }
    }
}

/// Which rooms the page shows, and in what order.
struct RoomsPageSettings: View {
    let pageId: UUID
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var home
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let available = home.rooms.map { RoomsPage.Room(id: $0.uniqueIdentifier.uuidString, name: $0.name) }
        let chosen = model.household.dashboard.pageList.first { $0.id == pageId }?.rooms ?? []
        let shown = RoomsPage.columns(chosen: chosen, available: available)
        let hidden = available.filter { r in !shown.contains(r) }
        NavigationStack {
            List {
                Section {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, room in
                        HStack {
                            Button { change { RoomsPage.toggle(room.id, chosen: $0, available: available) } } label: {
                                Label(room.name, systemImage: "checkmark.circle.fill")
                            }
                            .disabled(shown.count == 1)
                            Spacer()
                            Button { change { RoomsPage.move(room.id, by: -1, chosen: $0, available: available) } } label: {
                                Image(systemName: "arrow.left")
                            }
                            .disabled(i == 0)
                            .accessibilityLabel("Move \(room.name) left")
                            Button { change { RoomsPage.move(room.id, by: 1, chosen: $0, available: available) } } label: {
                                Image(systemName: "arrow.right")
                            }
                            .disabled(i == shown.count - 1)
                            .accessibilityLabel("Move \(room.name) right")
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text("On this page, left to right")
                }
                if !hidden.isEmpty {
                    Section("Not shown") {
                        ForEach(hidden, id: \.id) { room in
                            Button { change { RoomsPage.toggle(room.id, chosen: $0, available: available) } } label: {
                                Label(room.name, systemImage: "circle")
                            }
                        }
                    }
                }
                Section {
                    Text("Rooms and what's in them come from Apple's Home app. Move an accessory to another room there and it moves here too.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Rooms")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func change(_ f: @escaping ([String]) -> [String]) {
        model.household.dashboard.updatePage(pageId) { $0.rooms = f($0.rooms) }
    }
}
