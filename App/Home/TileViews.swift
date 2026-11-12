import AVKit
import HomeKit
import MusicKit
import PlateCore
import SwiftUI

/// One tile on the dashboard. In edit mode taps do nothing, so tiles can be moved and resized without switching things.
struct TileView: View {
    let tile: DashboardTile
    let editing: Bool

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.tileTint, tile.tint)
            .environment(\.tileIcon, tile.icon)
    }

    @ViewBuilder private var content: some View {
        switch tile.kind {
        case .accessory: AccessoryTile(tile: tile, editing: editing)
        case .scene: SceneTile(tile: tile, editing: editing)
        case .room: RoomTile(tile: tile, editing: editing)
        case .musicAlbum, .playlist: AlbumTile(tile: tile, editing: editing)
        case .clock: ClockTile(tile: tile)
        case .todaysMeals: MealsTile()
        case .shoppingList: ShoppingTile()
        case .useSoon: UseSoonTile()
        case .note: NoteTile(tile: tile)
        case .nowPlaying: NowPlayingTile(editing: editing)
        case .weather: WeatherTile(large: tile.size == .large || tile.size == .tall)
        case .timer: TimerTile(tile: tile, editing: editing)
        case .countdown: CountdownTile(tile: tile)
        case .calendar: CalendarTile(tile: tile)
        case .chores: ChoresTile(tile: tile, editing: editing)
        case .bins: BinsTile(tile: tile)
        case .wifi: WiFiTile(tile: tile)
        case .camera: CameraTile(tile: tile, editing: editing)
        case .climate: ClimateTile(tile: tile)
        case .allOff: AllOffTile(tile: tile, editing: editing)
        case .photoFrame: PhotoFrameTile(tile: tile)
        case .worldClock: WorldClockTile(tile: tile)
        case .forecast: ForecastTile(tile: tile)
        case .sun: SunTile(tile: tile)
        case .macros: MacrosTile(tile: tile)
        case .cookNow: CookNowTile(tile: tile)
        case .shortcut: ShortcutTile(tile: tile, editing: editing)
        case .routine: RoutineTile(tile: tile, editing: editing)
        case .lightShow: LightShowTile(tile: tile, editing: editing)
        case .activity: ActivityTile(tile: tile)
        case .command: CommandTile(tile: tile, editing: editing)
        case .briefing: BriefingTile(tile: tile, editing: editing)
        case .battery: BatteryTile(tile: tile)
        case .group: GroupTile(tile: tile, editing: editing)
        case .heading: HeadingTile(tile: tile)
        case .spacer: SpacerTile(editing: editing)
        case .unknown: Color.clear
        }
    }
}

/// Icon at the top, name and state at the bottom: the layout the Home app uses, so it reads the same.
/// The colours come from the card it sits on, so it's readable on any theme.
struct ControlTileLabel: View {
    let symbol: String
    let title: String
    let detail: String?
    var dimmed = false
    @Environment(\.tileIcon) private var icon

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon ?? symbol)
                .font(.system(size: 30, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(title)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.primary)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
        .opacity(dimmed ? 0.45 : 1)
    }
}

/// The title line at the top of a list tile.
struct TileHeader: View {
    let title: String
    let symbol: String
    @Environment(\.tileIcon) private var icon
    var body: some View {
        Label(title, systemImage: icon ?? symbol).font(.headline).lineLimit(1)
    }
}

// MARK: HomeKit tiles

struct AccessoryTile: View {
    let tile: DashboardTile
    let editing: Bool
    @Environment(HomeStore.self) private var home
    @State private var confirmUnlock = false
    @State private var showControls = false

    var body: some View {
        if let a = home.accessory(tile.ref) {
            let s = home.state(of: a)
            let cat = HomeStore.category(of: a)
            let lit = s.isOn == true && cat != .lock
            Button {
                if cat == .lock && s.isOn == true { confirmUnlock = true } else { Task { await home.toggle(a) } }
            } label: {
                TileCard(lit: lit, litColor: litColour(a, cat)) {
                    ControlTileLabel(symbol: s.symbol, title: tile.name(a.name), detail: s.reachable ? s.detail : "Not responding",
                                     dimmed: !s.reachable)
                }
            }
            .buttonStyle(.plain)
            .disabled(editing || s.isOn == nil)
            .contextMenu { if !editing { menu(a, cat) } }
            .confirmationDialog("Unlock \(a.name)?", isPresented: $confirmUnlock, titleVisibility: .visible) {
                Button("Unlock") { Task { await home.toggle(a) } }
            }
            .sheet(isPresented: $showControls) { AccessoryControlView(accessoryId: a.uniqueIdentifier.uuidString) }
        } else {
            MissingTile(tile: tile)
        }
    }

    /// A colour bulb's tile glows the colour the bulb is; everything else uses the theme's "on" colour.
    private func litColour(_ a: HMAccessory, _ cat: AccessorySummary.Category) -> RGB? {
        guard cat == .light else { return nil }
        let d = home.detail(of: a)
        guard let h = d.hue, let s = d.saturation, s > 8 else { return nil }
        return RGB(hue: h / 360, saturation: min(1, s / 100) * 0.85, brightness: 1)
    }

    @ViewBuilder func menu(_ a: HMAccessory, _ cat: AccessorySummary.Category) -> some View {
        if cat == .light || cat == .blinds || cat == .thermostat {
            Button("Colour, brightness and more", systemImage: "slider.horizontal.3") { showControls = true }
        }
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
    @Environment(\.dashStyle) private var style
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
                TileCard(lit: flash, litColor: style.accent) {
                    ControlTileLabel(symbol: Self.symbol(for: scene), title: tile.name(scene.name), detail: flash ? "Done" : "Scene")
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
                TileCard(lit: on) {
                    ControlTileLabel(symbol: on ? "lightbulb.2.fill" : "lightbulb.2", title: tile.name(room.name),
                                     detail: on ? "Lights on" : "Lights off")
                }
            }
            .buttonStyle(.plain)
            .disabled(editing)
            .contextMenu {
                if !editing {
                    ForEach([100, 60, 30, 10], id: \.self) { p in
                        Button("Every light to \(p)%") {
                            Task {
                                for a in room.accessories where HomeStore.category(of: a) == .light { await home.setBrightness(a, to: p) }
                            }
                        }
                    }
                }
            }
        } else {
            MissingTile(tile: tile)
        }
    }
}

/// Several accessories switched together, chosen by you (unlike a room, which is everything in it).
struct GroupTile: View {
    let tile: DashboardTile
    let editing: Bool
    @Environment(HomeStore.self) private var home

    var body: some View {
        let members = (tile.options["ids"] ?? "").split(separator: ",").compactMap { home.accessory(String($0)) }
        let onCount = members.filter { home.state(of: $0).isOn == true }.count
        Button {
            Task {
                let target = onCount == 0
                Feedback.shared.play(target ? .on : .off)
                for a in members { await home.set(a, on: target, quiet: true) }
            }
        } label: {
            TileCard(lit: onCount > 0) {
                ControlTileLabel(symbol: onCount > 0 ? "square.grid.2x2.fill" : "square.grid.2x2", title: tile.name(),
                                 detail: members.isEmpty ? "Edit to choose what's in it"
                                    : onCount == 0 ? "All off" : onCount == members.count ? "All on" : "\(onCount) of \(members.count) on")
            }
        }
        .buttonStyle(.plain)
        .disabled(editing || members.isEmpty)
    }
}

/// A tile for something removed in the Home app (or a home that hasn't loaded yet).
struct MissingTile: View {
    let tile: DashboardTile
    @Environment(HomeStore.self) private var home

    var body: some View {
        TileCard {
            ControlTileLabel(symbol: "questionmark.square.dashed", title: tile.name(),
                             detail: home.status == .ready ? "Not in this home any more" : "Loading…", dimmed: true)
        }
    }
}

// MARK: Music tiles

/// A pinned album, playlist or station: the cover, and a tap plays it.
struct AlbumTile: View {
    let tile: DashboardTile
    let editing: Bool
    @Environment(MusicStore.self) private var music
    @Environment(\.dashStyle) private var style
    @State private var artwork: Artwork?

    private var type: String? { tile.kind == .playlist ? tile.options["type"] ?? "playlist" : nil }

    var body: some View {
        Button {
            Feedback.shared.play(.tap)
            Task { if let ref = tile.ref { await music.play(ref, type: type) } }
        } label: {
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    if let artwork {
                        ArtworkImage(artwork, width: geo.size.width, height: geo.size.height)
                    } else {
                        Rectangle().fill((tile.tint ?? style.accent).color.gradient)
                        Image(systemName: tile.icon ?? (type == "station" ? "dot.radiowaves.left.and.right" : "music.note"))
                            .font(.system(size: 40)).foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile.name()).font(.headline).lineLimit(1)
                            if let s = tile.subtitle, geo.size.width > 150 { Text(s).font(.subheadline).opacity(0.8).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                        if geo.size.width > 150 { Image(systemName: "play.circle.fill").font(.system(size: 34)) }
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(editing)
        .task(id: tile.ref) {
            guard let ref = tile.ref else { return }
            if type == nil { artwork = await music.album(ref)?.artwork }
            else if type == "playlist" { artwork = await music.playlist(ref)?.artwork }
        }
    }
}

struct NowPlayingTile: View {
    let editing: Bool
    @Environment(MusicStore.self) private var music
    @ObservedObject private var state = ApplicationMusicPlayer.shared.state
    @ObservedObject private var queue = ApplicationMusicPlayer.shared.queue

    var body: some View {
        let entry = queue.currentEntry
        TileCard(alignment: .center) {
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
                        Button {
                            state.shuffleMode = state.shuffleMode == .songs ? .off : .songs
                        } label: {
                            Image(systemName: "shuffle").opacity(state.shuffleMode == .songs ? 1 : 0.4)
                        }
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
    let tile: DashboardTile
    var body: some View {
        let large = tile.size == .large
        let face = ClockFace(rawValue: tile.options["face"] ?? "") ?? .digital
        TileCard(alignment: .center) {
            TimelineView(.periodic(from: .now, by: face == .analogue ? 1 : 15)) { ctx in
                VStack(spacing: 4) {
                    switch face {
                    case .analogue:
                        AnalogueClock(date: ctx.date).padding(4)
                    case .words:
                        let c = Calendar.plate.dateComponents([.hour, .minute], from: ctx.date)
                        Text(DayText.clockWords(hour: c.hour ?? 0, minute: c.minute ?? 0).capitalizedFirst)
                            .font(.system(size: large ? 44 : 24, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.5)
                    default:
                        Text(ctx.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                            .font(.system(size: large ? 76 : 40, weight: .semibold))
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                    if tile.size != .small || face == .digital {
                        Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(large ? .title3 : .subheadline)
                            .foregroundStyle(.secondary)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                }
                .environment(\.locale, Locale(identifier: "en_GB"))
                .padding(12)
            }
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// A clock with hands. Drawn in the text colour of whatever it sits on.
struct AnalogueClock: View {
    let date: Date
    var showSeconds = true
    @Environment(\.dashStyle) private var style

    var body: some View {
        let c = Calendar.plate.dateComponents([.hour, .minute, .second], from: date)
        let angles = WeatherText.clockAngles(hour: c.hour ?? 0, minute: c.minute ?? 0, second: c.second ?? 0)
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: max(1.5, side * 0.012))
                ForEach(0..<12, id: \.self) { i in
                    Capsule().fill(.secondary)
                        .frame(width: max(1.5, side * 0.012), height: side * (i % 3 == 0 ? 0.09 : 0.045))
                        .offset(y: -side * (0.5 - 0.06))
                        .rotationEffect(.degrees(Double(i) * 30))
                }
                hand(length: side * 0.26, width: side * 0.035, angle: angles.hour).foregroundStyle(.primary)
                hand(length: side * 0.38, width: side * 0.022, angle: angles.minute).foregroundStyle(.primary)
                if showSeconds {
                    hand(length: side * 0.4, width: max(1, side * 0.008), angle: angles.second).foregroundStyle(style.accent.color)
                }
                Circle().fill(style.accent.color).frame(width: side * 0.045, height: side * 0.045)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func hand(length: CGFloat, width: CGFloat, angle: Double) -> some View {
        Capsule().frame(width: width, height: length).offset(y: -length / 2).rotationEffect(.degrees(angle))
    }
}

struct MealsTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let day = model.dayIndex(for: Date())
        let entries = model.household.plan.entries.filter { $0.day == day }
            .sorted { MealType.allCases.firstIndex(of: $0.meal)! < MealType.allCases.firstIndex(of: $1.meal)! }
        TileCard {
            VStack(alignment: .leading, spacing: 10) {
                TileHeader(title: "Today's meals", symbol: "fork.knife")
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
        TileCard {
            VStack(alignment: .leading, spacing: 8) {
                TileHeader(title: list?.name ?? "Shopping", symbol: "cart")
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
        TileCard {
            VStack(alignment: .leading, spacing: 6) {
                TileHeader(title: "Use soon", symbol: "clock.badge.exclamationmark")
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
        // A note is a sticky-note yellow unless you've given it its own colour.
        TileCard(lit: tile.tint == nil, litColor: RGB(hex: "#FFE27A")) {
            VStack(alignment: .leading, spacing: 6) {
                if let label = tile.label, !label.isEmpty { Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                Text(tile.subtitle ?? tile.title)
                    .font(.title3.weight(.medium))
                    .minimumScaleFactor(0.6)
            }
            .padding(16)
        }
    }
}
