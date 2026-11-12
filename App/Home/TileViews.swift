import AVKit
import HomeKit
import MusicKit
import PlateCore
import SwiftUI

/// One tile on the dashboard. In edit mode taps do nothing, so tiles can be moved and resized without switching things.
struct TileView: View {
    let tile: DashboardTile
    let editing: Bool
    @Environment(HomeStore.self) private var home

    var body: some View {
        Group {
            switch tile.kind {
            case .accessory: AccessoryTile(tile: tile, editing: editing)
            case .scene: SceneTile(tile: tile, editing: editing)
            case .room: RoomTile(tile: tile, editing: editing)
            case .musicAlbum: AlbumTile(tile: tile, editing: editing)
            case .clock: ClockTile(large: tile.size == .large)
            case .todaysMeals: MealsTile()
            case .shoppingList: ShoppingTile()
            case .useSoon: UseSoonTile()
            case .note: NoteTile(tile: tile)
            case .nowPlaying: NowPlayingTile(editing: editing)
            case .weather: WeatherTile(large: tile.size == .large || tile.size == .tall)
            case .unknown: Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// The rounded card every tile sits on. `lit` makes it bright, like a light that's on.
struct TileBackground: View {
    var lit = false
    var tint: Color = .yellow
    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(lit ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
    }
}

/// Icon at the top, name and state at the bottom: the layout the Home app uses, so it reads the same.
struct ControlTileLabel: View {
    let symbol: String
    let title: String
    let detail: String?
    var lit = false
    var dimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(lit ? Color.black.opacity(0.75) : Color.secondary)
            Spacer(minLength: 4)
            Text(title)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundStyle(lit ? Color.black : Color.primary)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(lit ? Color.black.opacity(0.6) : Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
        .opacity(dimmed ? 0.45 : 1)
    }
}

// MARK: HomeKit tiles

struct AccessoryTile: View {
    let tile: DashboardTile
    let editing: Bool
    @Environment(HomeStore.self) private var home
    @State private var confirmUnlock = false

    var body: some View {
        if let a = home.accessory(tile.ref) {
            let s = home.state(of: a)
            let cat = HomeStore.category(of: a)
            Button {
                if cat == .lock && s.isOn == true { confirmUnlock = true } else { Task { await home.toggle(a) } }
            } label: {
                ZStack {
                    TileBackground(lit: s.isOn == true && cat != .lock, tint: cat == .light ? .yellow : .teal)
                    ControlTileLabel(symbol: s.symbol, title: a.name, detail: s.reachable ? s.detail : "Not responding",
                                     lit: s.isOn == true && cat != .lock, dimmed: !s.reachable)
                }
            }
            .buttonStyle(.plain)
            .disabled(editing || s.isOn == nil)
            .contextMenu { if !editing { menu(a, cat) } }
            .confirmationDialog("Unlock \(a.name)?", isPresented: $confirmUnlock, titleVisibility: .visible) {
                Button("Unlock") { Task { await home.toggle(a) } }
            }
        } else {
            MissingTile(tile: tile)
        }
    }

    @ViewBuilder func menu(_ a: HMAccessory, _ cat: AccessorySummary.Category) -> some View {
        if cat == .light, HomeStore.characteristic(HMCharacteristicTypeBrightness, in: a) != nil {
            ForEach([100, 75, 50, 25, 10], id: \.self) { p in
                Button("\(p)%") { Task { await home.setBrightness(a, to: p) } }
            }
        }
        if cat == .thermostat {
            Button("Warmer (+0.5°)", systemImage: "plus") { Task { await home.nudgeTemperature(a, by: 0.5) } }
            Button("Cooler (−0.5°)", systemImage: "minus") { Task { await home.nudgeTemperature(a, by: -0.5) } }
        }
    }
}

struct SceneTile: View {
    let tile: DashboardTile
    let editing: Bool
    @Environment(HomeStore.self) private var home
    @State private var flash = false

    var body: some View {
        if let scene = home.scene(tile.ref) {
            Button {
                Task {
                    await home.run(scene)
                    withAnimation { flash = true }
                    try? await Task.sleep(for: .seconds(1))
                    withAnimation { flash = false }
                }
            } label: {
                ZStack {
                    TileBackground(lit: flash, tint: .orange)
                    ControlTileLabel(symbol: Self.symbol(for: scene), title: scene.name, detail: flash ? "Done" : "Scene", lit: flash)
                }
            }
            .buttonStyle(.plain)
            .disabled(editing)
        } else {
            MissingTile(tile: tile)
        }
    }

    static func symbol(for scene: HMActionSet) -> String {
        switch scene.actionSetType {
        case HMActionSetTypeWakeUp: return "sunrise.fill"
        case HMActionSetTypeSleep: return "moon.fill"
        case HMActionSetTypeHomeArrival: return "house.fill"
        case HMActionSetTypeHomeDeparture: return "figure.walk.departure"
        default:
            let n = scene.name.lowercased()
            if n.contains("night") || n.contains("bed") { return "moon.fill" }
            if n.contains("morning") { return "sunrise.fill" }
            if n.contains("film") || n.contains("movie") || n.contains("tv") { return "tv.fill" }
            if n.contains("relax") || n.contains("chill") { return "sofa.fill" }
            if n.contains("dinner") || n.contains("cook") { return "fork.knife" }
            return "sparkles"
        }
    }
}

struct RoomTile: View {
    let tile: DashboardTile
    let editing: Bool
    @Environment(HomeStore.self) private var home

    var body: some View {
        if let room = home.room(tile.ref) {
            let on = home.isOn(room)
            Button { Task { await home.toggle(room) } } label: {
                ZStack {
                    TileBackground(lit: on)
                    ControlTileLabel(symbol: on ? "lightbulb.2.fill" : "lightbulb.2", title: room.name,
                                     detail: on ? "Lights on" : "Lights off", lit: on)
                }
            }
            .buttonStyle(.plain)
            .disabled(editing)
        } else {
            MissingTile(tile: tile)
        }
    }
}

/// A tile for something removed in the Home app (or a home that hasn't loaded yet).
struct MissingTile: View {
    let tile: DashboardTile
    @Environment(HomeStore.self) private var home

    var body: some View {
        ZStack {
            TileBackground()
            ControlTileLabel(symbol: "questionmark.square.dashed", title: tile.title,
                             detail: home.status == .ready ? "Not in this home any more" : "Loading…", dimmed: true)
        }
    }
}

// MARK: Music tiles

struct AlbumTile: View {
    let tile: DashboardTile
    let editing: Bool
    @Environment(MusicStore.self) private var music
    @State private var album: Album?

    var body: some View {
        Button { Task { if let ref = tile.ref { await music.play(ref) } } } label: {
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    if let art = album?.artwork {
                        ArtworkImage(art, width: geo.size.width, height: geo.size.height)
                    } else {
                        Rectangle().fill(Color.pink.gradient)
                        Image(systemName: "music.note").font(.system(size: 40)).foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile.title).font(.headline).lineLimit(1)
                            if let s = tile.subtitle { Text(s).font(.subheadline).opacity(0.8).lineLimit(1) }
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill").font(.system(size: 34))
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .buttonStyle(.plain)
        .disabled(editing)
        .task(id: tile.ref) { if let ref = tile.ref { album = await music.album(ref) } }
    }
}

struct NowPlayingTile: View {
    let editing: Bool
    @Environment(MusicStore.self) private var music
    @ObservedObject private var state = ApplicationMusicPlayer.shared.state
    @ObservedObject private var queue = ApplicationMusicPlayer.shared.queue

    var body: some View {
        let entry = queue.currentEntry
        ZStack {
            TileBackground()
            HStack(spacing: 14) {
                Group {
                    if let art = entry?.artwork {
                        ArtworkImage(art, width: 90, height: 90)
                    } else {
                        RoundedRectangle(cornerRadius: 10).fill(Color.pink.gradient)
                            .overlay(Image(systemName: "music.note").foregroundStyle(.white))
                    }
                }
                .frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry?.title ?? "Nothing playing").font(.headline).lineLimit(1)
                    Text(entry?.subtitle ?? "Tap a pinned album to play it").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    HStack(spacing: 22) {
                        Button { Task { try? await music.player.skipToPreviousEntry() } } label: { Image(systemName: "backward.fill") }
                        Button { Task { await music.togglePlayPause() } } label: {
                            Image(systemName: state.playbackStatus == .playing ? "pause.fill" : "play.fill")
                        }
                        Button { Task { try? await music.player.skipToNextEntry() } } label: { Image(systemName: "forward.fill") }
                        RoutePicker().frame(width: 30, height: 30)
                    }
                    .font(.title2)
                    .buttonStyle(.plain)
                    .disabled(editing || entry == nil)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }
}

/// The AirPlay button, to send music to a HomePod or other speaker.
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.prioritizesVideoDevices = false
        v.tintColor = .label
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: Plate tiles

struct ClockTile: View {
    var large = true
    var body: some View {
        ZStack {
            TileBackground()
            TimelineView(.everyMinute) { ctx in
                VStack(spacing: 4) {
                    Text(ctx.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                        .font(.system(size: large ? 76 : 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                    Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(large ? .title3 : .subheadline)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.7)
                }
                .lineLimit(1)
                .environment(\.locale, Locale(identifier: "en_GB"))
                .padding(12)
            }
        }
    }
}

struct MealsTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let day = model.dayIndex(for: Date())
        let entries = model.household.plan.entries.filter { $0.day == day }
            .sorted { MealType.allCases.firstIndex(of: $0.meal)! < MealType.allCases.firstIndex(of: $1.meal)! }
        ZStack(alignment: .topLeading) {
            TileBackground()
            VStack(alignment: .leading, spacing: 10) {
                Label("Today's meals", systemImage: "fork.knife").font(.headline)
                if entries.isEmpty {
                    Text("Nothing planned. Plan the week in Plate's Plan tab.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(entries) { e in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.meal.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(model.recipe(e.recipeId)?.name ?? "A removed recipe")
                            .font(.body).lineLimit(2).strikethrough(e.cooked)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }
}

struct ShoppingTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let list = model.household.lists.max { $0.createdAt < $1.createdAt }
        ZStack(alignment: .topLeading) {
            TileBackground()
            VStack(alignment: .leading, spacing: 8) {
                Label(list?.name ?? "Shopping", systemImage: "cart").font(.headline).lineLimit(1)
                if let list {
                    let toBuy = model.result(for: list).toBuy.filter { !list.checked.contains($0.key) }
                    if toBuy.isEmpty { Text("All done.").foregroundStyle(.secondary) }
                    ForEach(toBuy.prefix(9)) { line in
                        Label(line.name, systemImage: "circle").font(.subheadline).lineLimit(1)
                    }
                    if toBuy.count > 9 { Text("and \(toBuy.count - 9) more").font(.caption).foregroundStyle(.secondary) }
                } else {
                    Text("No list yet. Make one in Plate's Shop tab.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }
}

struct UseSoonTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let soon = Kitchen.expiringSoon(model.household.inventory, within: 3, now: Date())
        ZStack(alignment: .topLeading) {
            TileBackground()
            VStack(alignment: .leading, spacing: 6) {
                Label("Use soon", systemImage: "clock.badge.exclamationmark").font(.headline)
                if soon.isEmpty { Text("Nothing's about to go off.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(soon.prefix(5)) { item in
                    HStack {
                        Text(item.name).lineLimit(1)
                        Spacer()
                        ExpiryBadge(date: item.expiry)
                    }
                    .font(.subheadline)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }
}

struct NoteTile: View {
    let tile: DashboardTile
    var body: some View {
        ZStack(alignment: .topLeading) {
            TileBackground(lit: true, tint: .yellow.opacity(0.6))
            Text(tile.subtitle ?? tile.title)
                .font(.title3.weight(.medium))
                .foregroundStyle(.black)
                .minimumScaleFactor(0.6)
                .padding(16)
        }
    }
}
