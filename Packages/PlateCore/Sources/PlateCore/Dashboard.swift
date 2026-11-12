import Foundation

// The home dashboard: a grid of tiles for a wall-mounted iPad (or the Home tab on a phone), plus the idle mode that
// shows artwork after a while and goes back to the dashboard when tapped. Everything here is plain Swift so the layout,
// idle timing, night dimming and slideshow order are tested on Linux. HomeKit, Apple Music and Photos live in the app.

/// What a tile shows. Saved as text, so a file written by a newer Plate with tile kinds this version doesn't know still
/// opens: those tiles are kept as `.unknown` and simply not drawn.
public enum TileKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// One HomeKit accessory (a light, plug, lock, thermostat…). `ref` is its HomeKit identifier.
    case accessory
    /// A HomeKit scene. `ref` is the scene's identifier.
    case scene
    /// Every light and switch in a room, together. `ref` is the room's identifier.
    case room
    /// An Apple Music album: tap to play. `ref` is its Apple Music id.
    case musicAlbum
    /// The time and date, large.
    case clock
    /// What's on the meal plan today.
    case todaysMeals
    /// The newest shopping list.
    case shoppingList
    /// Food that goes off in the next few days.
    case useSoon
    /// A note you type yourself ("Bins out Thursday").
    case note
    /// Music playing right now, with play/pause and skip.
    case nowPlaying
    /// The weather where the device is (Apple Weather, through WeatherKit).
    case weather
    /// Kitchen timers: start one, see them count down, hear when they finish.
    case timer
    /// Days until (or since) a date. `options["date"]` is the day.
    case countdown
    /// The next few events from the device's calendar.
    case calendar
    /// The flat's chores and whose turn each one is.
    case chores
    /// Things that come round on a schedule, such as which bin goes out this week.
    case bins
    /// The guest Wi-Fi as a QR code to scan.
    case wifi
    /// A HomeKit camera: a picture that refreshes, tap for live video. `ref` is the camera accessory.
    case camera
    /// Temperature and humidity from every sensor in the home.
    case climate
    /// How many lights are on, and one tap to turn them all off.
    case allOff
    /// A photo album shown as a small picture frame. `ref` is the album.
    case photoFrame
    /// The time somewhere else. `options["tz"]` is the time zone.
    case worldClock
    /// The next few days of weather.
    case forecast
    /// Sunrise and sunset today.
    case sun
    /// An Apple Music playlist or station. `ref` is its id, `options["type"]` is "playlist" or "station".
    case playlist
    /// Today's calories and protein against the targets.
    case macros
    /// The best thing to cook from what's in the kitchen.
    case cookNow
    /// Opens a link or runs one of Apple's Shortcuts. `options["url"]` or `options["shortcut"]`.
    case shortcut
    /// One of Plate's own routines (several actions from one tap). `ref` is the routine.
    case routine
    /// A moving light effect across the colour lights. `options["show"]` is which.
    case lightShow
    /// What's been switched recently.
    case activity
    /// A box to type what you want: "kitchen off", "play Blue", "pasta 10 min".
    case command
    /// Says the weather, today's meals and whose chores are due.
    case briefing
    /// Accessories with a low battery.
    case battery
    /// Several accessories switched together. `options["ids"]` lists them.
    case group
    /// A title across the grid, to split it into sections.
    case heading
    /// An empty gap.
    case spacer
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TileKind(rawValue: raw) ?? .unknown
    }

    /// Tiles that point at something outside Plate (HomeKit, Music, Photos) and can go missing if it's deleted there.
    public var needsRef: Bool {
        switch self {
        case .accessory, .scene, .room, .musicAlbum, .camera, .photoFrame, .playlist, .routine: return true
        default: return false
        }
    }

    /// Tiles you can have any number of, each set up differently.
    public var canRepeat: Bool {
        switch self {
        case .note, .countdown, .worldClock, .shortcut, .lightShow, .group, .heading, .spacer, .wifi: return true
        default: return false
        }
    }

    /// Tiles that only make sense once, such as the clock.
    public var isSingle: Bool {
        switch self {
        case .clock, .todaysMeals, .shoppingList, .useSoon, .nowPlaying, .weather, .timer, .calendar, .chores, .bins,
             .climate, .allOff, .forecast, .sun, .macros, .cookNow, .activity, .command, .briefing, .battery: return true
        default: return false
        }
    }
}

/// How much of the grid a tile takes, in grid cells (columns × rows).
public enum TileSize: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case small   // 1 × 1
    case wide    // 2 × 1
    case tall    // 1 × 2
    case large   // 2 × 2

    public var id: String { rawValue }
    public var columns: Int { self == .wide || self == .large ? 2 : 1 }
    public var rows: Int { self == .tall || self == .large ? 2 : 1 }
    public var title: String {
        switch self {
        case .small: return "Small"
        case .wide: return "Wide"
        case .tall: return "Tall"
        case .large: return "Large"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TileSize(rawValue: raw) ?? .small
    }
}

public struct DashboardTile: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: TileKind
    /// The HomeKit / Apple Music / Photos identifier, for tiles that point at something.
    public var ref: String?
    /// Name shown on the tile. Kept so a tile still has a sensible label before HomeKit has loaded.
    public var title: String
    /// A second line, such as the room or the album's artist; for a note, the note itself.
    public var subtitle: String?
    public var size: TileSize
    /// Your own name for the tile, shown instead of the HomeKit or album name.
    public var label: String?
    /// Your own icon (an SF Symbol name).
    public var icon: String?
    /// Your own colour for the tile.
    public var tint: RGB?
    /// Which page the tile is on. nil is the first page.
    public var pageId: UUID?
    /// Settings particular to the kind of tile (a countdown's date, a world clock's time zone…), kept as text.
    public var options: [String: String]
    public var updatedAt: Date

    public init(id: UUID = UUID(), kind: TileKind, ref: String? = nil, title: String, subtitle: String? = nil,
                size: TileSize? = nil, label: String? = nil, icon: String? = nil, tint: RGB? = nil, pageId: UUID? = nil,
                options: [String: String] = [:], updatedAt: Date = Date()) {
        self.id = id; self.kind = kind; self.ref = ref; self.title = title; self.subtitle = subtitle
        self.size = size ?? DashboardTile.defaultSize(for: kind)
        self.label = label; self.icon = icon; self.tint = tint; self.pageId = pageId; self.options = options
        self.updatedAt = updatedAt
    }

    /// The name to show: your own if you've set one, otherwise `fallback` (the live HomeKit name) or the saved title.
    public func name(_ fallback: String? = nil) -> String {
        if let label, !label.trimmingCharacters(in: .whitespaces).isEmpty { return label }
        return fallback ?? title
    }

    public static func defaultSize(for kind: TileKind) -> TileSize {
        switch kind {
        case .clock, .musicAlbum, .todaysMeals, .shoppingList, .camera, .photoFrame, .playlist, .calendar, .chores,
             .wifi: return .large
        case .nowPlaying, .useSoon, .note, .room, .weather, .timer, .bins, .climate, .forecast, .activity, .command,
             .heading, .cookNow, .macros: return .wide
        default: return .small
        }
    }

    enum CodingKeys: String, CodingKey { case id, kind, ref, title, subtitle, size, label, icon, tint, pageId, options, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(TileKind.self, forKey: .kind) ?? .unknown
        ref = try c.decodeIfPresent(String.self, forKey: .ref)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        size = try c.decodeIfPresent(TileSize.self, forKey: .size) ?? DashboardTile.defaultSize(for: kind)
        label = c.optional(.label)
        icon = c.optional(.icon)
        tint = c.optional(.tint)
        pageId = c.optional(.pageId)
        options = c.value(.options, default: [:])
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

/// What idle mode shows: the cover of whatever's playing, otherwise the photo album, otherwise just the clock.
public enum IdleArtwork: Hashable, Sendable {
    case nowPlaying
    case photos
    case clockOnly

    public static func choose(musicPlaying: Bool, hasNowPlayingArtwork: Bool, photoCount: Int) -> IdleArtwork {
        if musicPlaying && hasNowPlayingArtwork { return .nowPlaying }
        if photoCount > 0 { return .photos }
        return .clockOnly
    }
}

public enum ClockFace: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case digital, analogue, words, flip
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .digital: return "Digital"
        case .analogue: return "Analogue"
        case .words: return "In words"
        case .flip: return "Flip clock"
        }
    }
}

/// How the wall iPad behaves when nobody is using it.
public struct IdleSettings: Codable, Hashable, Sendable {
    /// Minutes without a touch before the artwork shows. 0 means never.
    public var minutes: Int
    /// The photo album used for artwork (its local identifier), and its name for display.
    public var photoAlbumId: String?
    public var photoAlbumTitle: String?
    /// How long each picture stays up.
    public var secondsPerSlide: Int
    public var showClock: Bool
    /// Dim the screen overnight.
    public var nightDim: Bool
    /// Night runs from this time to `nightEnd`, as minutes after midnight (23:00 to 07:00 by default).
    public var nightStart: Int
    public var nightEnd: Int
    /// How dark the screen gets at night, 0 (not at all) to 1 (black).
    public var nightDarkness: Double
    /// How the time is shown on the artwork screen.
    public var clockFace: ClockFace
    /// Show the weather next to the time.
    public var showWeather: Bool
    /// Slowly zoom and drift the pictures, and nudge the clock around so nothing marks the screen.
    public var drift: Bool
    /// Come back to the dashboard when a HomeKit motion sensor sees someone.
    public var wakeOnMotion: Bool
    /// What to show when there's no photo album and no music: moving colours rather than a plain backdrop.
    public var aurora: Bool

    public init(minutes: Int = 3, photoAlbumId: String? = nil, photoAlbumTitle: String? = nil,
                secondsPerSlide: Int = 20, showClock: Bool = true, nightDim: Bool = true,
                nightStart: Int = 23 * 60, nightEnd: Int = 7 * 60, nightDarkness: Double = 0.8,
                clockFace: ClockFace = .digital, showWeather: Bool = true, drift: Bool = true, wakeOnMotion: Bool = false,
                aurora: Bool = true) {
        self.minutes = minutes; self.photoAlbumId = photoAlbumId; self.photoAlbumTitle = photoAlbumTitle
        self.secondsPerSlide = secondsPerSlide; self.showClock = showClock; self.nightDim = nightDim
        self.nightStart = nightStart; self.nightEnd = nightEnd; self.nightDarkness = nightDarkness
        self.clockFace = clockFace; self.showWeather = showWeather; self.drift = drift; self.wakeOnMotion = wakeOnMotion
        self.aurora = aurora
    }

    enum CodingKeys: String, CodingKey {
        case minutes, photoAlbumId, photoAlbumTitle, secondsPerSlide, showClock, nightDim, nightStart, nightEnd, nightDarkness,
             clockFace, showWeather, drift, wakeOnMotion, aurora
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = IdleSettings()
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? d.minutes
        photoAlbumId = try c.decodeIfPresent(String.self, forKey: .photoAlbumId)
        photoAlbumTitle = try c.decodeIfPresent(String.self, forKey: .photoAlbumTitle)
        secondsPerSlide = try c.decodeIfPresent(Int.self, forKey: .secondsPerSlide) ?? d.secondsPerSlide
        showClock = try c.decodeIfPresent(Bool.self, forKey: .showClock) ?? d.showClock
        nightDim = try c.decodeIfPresent(Bool.self, forKey: .nightDim) ?? d.nightDim
        nightStart = try c.decodeIfPresent(Int.self, forKey: .nightStart) ?? d.nightStart
        nightEnd = try c.decodeIfPresent(Int.self, forKey: .nightEnd) ?? d.nightEnd
        nightDarkness = try c.decodeIfPresent(Double.self, forKey: .nightDarkness) ?? d.nightDarkness
        clockFace = c.value(.clockFace, default: d.clockFace)
        showWeather = c.value(.showWeather, default: d.showWeather)
        drift = c.value(.drift, default: d.drift)
        wakeOnMotion = c.value(.wakeOnMotion, default: d.wakeOnMotion)
        aurora = c.value(.aurora, default: d.aurora)
    }
}

/// The whole dashboard: its tiles in order, and the idle settings.
public struct HomeDashboard: Codable, Hashable, Sendable {
    public var tiles: [DashboardTile]
    public var idle: IdleSettings
    /// Colours, background, tile shape, font and sounds.
    public var style: DashboardStyle
    /// Extra pages to swipe between. Empty means a single page.
    public var pages: [DashboardPage]
    public var timers: [DashTimer]
    public var chores: [Chore]
    /// Things on a repeating schedule (bins).
    public var recurring: [Recurring]
    public var routines: [Routine]
    public var schedules: [RoutineSchedule]
    /// The most recent things switched from the dashboard, newest first.
    public var activity: [ActivityEntry]
    public var updatedAt: Date

    public init(tiles: [DashboardTile] = [], idle: IdleSettings = IdleSettings(), style: DashboardStyle = DashboardStyle(),
                pages: [DashboardPage] = [], updatedAt: Date = Date()) {
        self.tiles = tiles; self.idle = idle; self.style = style; self.pages = pages
        self.timers = []; self.chores = []; self.recurring = []; self.routines = []; self.schedules = []; self.activity = []
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case tiles, idle, style, pages, timers, chores, recurring, routines, schedules, activity, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tiles = try c.decodeIfPresent([DashboardTile].self, forKey: .tiles) ?? []
        idle = try c.decodeIfPresent(IdleSettings.self, forKey: .idle) ?? IdleSettings()
        style = c.value(.style, default: DashboardStyle())
        pages = c.value(.pages, default: [])
        timers = c.value(.timers, default: [])
        chores = c.value(.chores, default: [])
        recurring = c.value(.recurring, default: [])
        routines = c.value(.routines, default: [])
        schedules = c.value(.schedules, default: [])
        activity = c.value(.activity, default: [])
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    /// The tiles this version of Plate can draw.
    public var visibleTiles: [DashboardTile] { tiles.filter { $0.kind != .unknown } }

    /// Whether this exact thing is already on the dashboard (so the "Add" list can tick it).
    public func contains(_ kind: TileKind, ref: String? = nil) -> Bool {
        tiles.contains { $0.kind == kind && (kind.needsRef ? $0.ref == ref : true) }
    }

    /// Adds a tile, unless the same thing is already there. Returns whether it was added.
    @discardableResult
    public mutating func add(_ tile: DashboardTile) -> Bool {
        if tile.kind.canRepeat || !contains(tile.kind, ref: tile.ref) {
            tiles.append(tile)
            updatedAt = Date()
            return true
        }
        return false
    }

    public mutating func remove(_ id: UUID) {
        tiles.removeAll { $0.id == id }
        updatedAt = Date()
    }

    public mutating func resize(_ id: UUID, to size: TileSize) {
        guard let i = tiles.firstIndex(where: { $0.id == id }) else { return }
        tiles[i].size = size
        tiles[i].updatedAt = Date()
        updatedAt = Date()
    }

    /// Moves a tile to sit where another one is (used when dragging tiles around).
    public mutating func move(_ id: UUID, before target: UUID) {
        guard id != target, let from = tiles.firstIndex(where: { $0.id == id }) else { return }
        let tile = tiles.remove(at: from)
        let to = tiles.firstIndex(where: { $0.id == target }) ?? tiles.endIndex
        // Dragging forwards drops the tile after the target; backwards, before it, which is what a finger expects.
        tiles.insert(tile, at: from <= to ? min(to + 1, tiles.endIndex) : to)
        updatedAt = Date()
    }

    /// Moves a tile one place earlier or later. Used by the arrow buttons in edit mode.
    public mutating func shift(_ id: UUID, by offset: Int) {
        guard let from = tiles.firstIndex(where: { $0.id == id }) else { return }
        let to = max(0, min(tiles.count - 1, from + offset))
        guard to != from else { return }
        tiles.swapAt(from, to)
        updatedAt = Date()
    }

    /// Tiles pointing at HomeKit things that no longer exist, once HomeKit has loaded. They're shown greyed out with a
    /// "Remove" button rather than deleted, in case the home just hasn't loaded fully yet.
    public func missingHomeTiles(knownIds: Set<String>) -> [DashboardTile] {
        tiles.filter { [.accessory, .scene, .room].contains($0.kind) && !knownIds.contains($0.ref ?? "") }
    }

    /// The pinned Apple Music albums, in dashboard order.
    public var pinnedAlbums: [DashboardTile] { tiles.filter { $0.kind == .musicAlbum } }
}

// MARK: - Starting layout

/// A HomeKit accessory, as much as Plate needs to know to suggest tiles. The app fills these in from HomeKit.
public struct AccessorySummary: Hashable, Sendable {
    public enum Category: String, Sendable { case light, outlet, switchControl, fan, lock, thermostat, blinds, sensor, other }
    public var id: String
    public var name: String
    public var room: String?
    public var category: Category
    public init(id: String, name: String, room: String? = nil, category: Category) {
        self.id = id; self.name = name; self.room = room; self.category = category
    }

    /// Things worth a tile you can tap: sensors only report, so they aren't suggested.
    public var isControllable: Bool { category != .sensor && category != .other }
}

public struct SceneSummary: Hashable, Sendable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public enum DashboardStarter {
    /// A first dashboard made from the home: a clock, up to four scenes, the controllable accessories grouped by room
    /// (at most `maxAccessories`), then today's meals and food to use soon. Ethan can rearrange it from there.
    public static func layout(accessories: [AccessorySummary], scenes: [SceneSummary], maxAccessories: Int = 12) -> [DashboardTile] {
        var tiles = [DashboardTile(kind: .clock, title: "Clock")]
        let preferredScenes = scenes.sorted { sceneRank($0.name) < sceneRank($1.name) }
        tiles += preferredScenes.prefix(4).map { DashboardTile(kind: .scene, ref: $0.id, title: $0.name) }
        let controllable = accessories.filter(\.isControllable).sorted {
            ($0.room ?? "~", categoryRank($0.category), $0.name) < ($1.room ?? "~", categoryRank($1.category), $1.name)
        }
        tiles += controllable.prefix(maxAccessories).map {
            DashboardTile(kind: .accessory, ref: $0.id, title: $0.name, subtitle: $0.room)
        }
        tiles.append(DashboardTile(kind: .todaysMeals, title: "Today's meals"))
        tiles.append(DashboardTile(kind: .useSoon, title: "Use soon"))
        return tiles
    }

    /// Everyday scenes first: the ones people tap most from a wall panel.
    static func sceneRank(_ name: String) -> Int {
        let n = name.lowercased()
        let order = ["morning", "arrive", "home", "relax", "evening", "dinner", "movie", "film", "night", "bed", "leave", "away"]
        return order.firstIndex { n.contains($0) } ?? order.count
    }

    static func categoryRank(_ c: AccessorySummary.Category) -> Int {
        switch c {
        case .light: return 0
        case .outlet, .switchControl: return 1
        case .fan: return 2
        case .blinds: return 3
        case .thermostat: return 4
        case .lock: return 5
        case .sensor, .other: return 6
        }
    }
}

// MARK: - Grid

/// Where a tile sits on the grid, in cells.
public struct TilePlacement: Hashable, Sendable {
    public var id: UUID
    public var column: Int
    public var row: Int
    public var columns: Int
    public var rows: Int
}

public enum DashboardGrid {
    /// How many columns fit across a given width, with tiles at least `minTile` points wide.
    /// A landscape iPad gets 6, portrait 4 or 5, a phone 2.
    public static func columns(forWidth width: Double, minTile: Double = 150, spacing: Double = 16) -> Int {
        guard width > 0 else { return 2 }
        return max(2, Int((width + spacing) / (minTile + spacing)))
    }

    /// Places tiles in order, each in the first gap it fits (reading left to right, top to bottom), so small tiles
    /// fill the holes left beside large ones. A tile wider than the grid is narrowed to fit.
    public static func place(_ tiles: [(id: UUID, size: TileSize)], columns: Int) -> [TilePlacement] {
        let cols = max(1, columns)
        var taken: [[Bool]] = []
        var result: [TilePlacement] = []

        func free(_ r: Int, _ c: Int, _ w: Int, _ h: Int) -> Bool {
            guard c + w <= cols else { return false }
            for rr in r..<(r + h) where rr < taken.count {
                for cc in c..<(c + w) where taken[rr][cc] { return false }
            }
            return true
        }

        for t in tiles {
            let w = min(t.size.columns, cols)
            let h = t.size.rows
            var row = 0
            search: while true {
                for col in 0..<cols where free(row, col, w, h) {
                    while taken.count < row + h { taken.append(Array(repeating: false, count: cols)) }
                    for rr in row..<(row + h) { for cc in col..<(col + w) { taken[rr][cc] = true } }
                    result.append(TilePlacement(id: t.id, column: col, row: row, columns: w, rows: h))
                    break search
                }
                row += 1
            }
        }
        return result
    }

    /// Rows the placed tiles use.
    public static func rowCount(_ placements: [TilePlacement]) -> Int {
        placements.map { $0.row + $0.rows }.max() ?? 0
    }
}

// MARK: - Idle mode

public enum IdleMode {
    /// Whether the artwork should be showing: idle mode is on and nobody has touched the screen for long enough.
    public static func isIdle(lastTouch: Date, now: Date, settings: IdleSettings) -> Bool {
        guard settings.minutes > 0 else { return false }
        return now.timeIntervalSince(lastTouch) >= Double(settings.minutes) * 60
    }

    /// Seconds until the artwork shows, or nil if it never will. Used to set a single timer rather than polling.
    public static func secondsUntilIdle(lastTouch: Date, now: Date, settings: IdleSettings) -> Double? {
        guard settings.minutes > 0 else { return nil }
        return max(0, Double(settings.minutes) * 60 - now.timeIntervalSince(lastTouch))
    }

    /// Whether it's night time, for dimming. Night can run past midnight (23:00 to 07:00) or not (13:00 to 14:00).
    public static func isNight(_ date: Date, settings: IdleSettings, calendar: Calendar = .plate) -> Bool {
        guard settings.nightDim, settings.nightStart != settings.nightEnd else { return false }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if settings.nightStart < settings.nightEnd {
            return m >= settings.nightStart && m < settings.nightEnd
        }
        return m >= settings.nightStart || m < settings.nightEnd
    }

    /// How dark to make the screen right now: 0 in the day, `nightDarkness` at night (kept between 0 and 0.95 so the
    /// clock never disappears completely).
    public static func dimming(_ date: Date, settings: IdleSettings, calendar: Calendar = .plate) -> Double {
        isNight(date, settings: settings, calendar: calendar) ? min(0.95, max(0, settings.nightDarkness)) : 0
    }

    /// "23:00" for minutes after midnight.
    public static func timeText(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}

/// The order pictures are shown in idle mode: every picture once, shuffled, before any repeats, and never the same
/// picture twice in a row across rounds. Seeded so it's testable.
public struct Slideshow: Sendable {
    public private(set) var items: [String]
    private var queue: [String] = []
    private var last: String?
    private var rng: SeededGenerator

    public init(items: [String], seed: UInt64 = UInt64.random(in: 1...UInt64.max - 1)) {
        self.items = Array(Set(items)).sorted()
        self.rng = SeededGenerator(seed: seed)
    }

    /// Swaps in a new set of pictures (say, after an album is pinned), keeping the round going where possible.
    public mutating func update(items new: [String]) {
        let set = Set(new)
        items = set.sorted()
        queue.removeAll { !set.contains($0) }
    }

    public mutating func next() -> String? {
        guard !items.isEmpty else { return nil }
        if queue.isEmpty {
            var round = items.shuffled(using: &rng)
            if round.count > 1, round.first == last { round.swapAt(0, round.count - 1) }
            queue = round
        }
        let item = queue.removeFirst()
        last = item
        return item
    }
}

/// A small, repeatable random number generator (SplitMix64) so slideshows and tests are predictable.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Weather

/// One hour of forecast, as much as the weather tile needs. The app fills these in from WeatherKit.
public struct HourForecast: Hashable, Sendable {
    public var date: Date
    /// Degrees Celsius.
    public var temperature: Double
    /// Chance of rain or snow, 0 to 1.
    public var precipitationChance: Double
    public init(date: Date, temperature: Double, precipitationChance: Double) {
        self.date = date; self.temperature = temperature; self.precipitationChance = precipitationChance
    }
}

public enum WeatherText {
    /// "12°", rounded, and never "-0°".
    public static func temperature(_ celsius: Double) -> String {
        let r = Int(celsius.rounded())
        return "\(r == 0 ? 0 : r)°"
    }

    /// A short line about rain in the next 12 hours, the thing worth knowing on the way out of the door:
    /// "Rain now", "Rain likely from 15:00", or nil when it looks dry. "Likely" means a 50% chance or more.
    public static func rainNote(_ hours: [HourForecast], now: Date, threshold: Double = 0.5, calendar: Calendar = .plate) -> String? {
        let thisHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let ahead = hours.filter { $0.date >= thisHour && $0.date < thisHour.addingTimeInterval(12 * 3600) }
            .sorted { $0.date < $1.date }
        guard let wet = ahead.first(where: { $0.precipitationChance >= threshold }) else { return nil }
        if wet.date <= thisHour { return "Rain now" }
        let c = calendar.dateComponents([.hour, .minute], from: wet.date)
        return "Rain likely from \(IdleMode.timeText((c.hour ?? 0) * 60 + (c.minute ?? 0)))"
    }

    /// The highest and lowest temperatures still to come today, for "↑14° ↓6°".
    public static func range(_ hours: [HourForecast], now: Date, calendar: Calendar = .plate) -> (high: Double, low: Double)? {
        let rest = hours.filter { calendar.isDate($0.date, inSameDayAs: now) && $0.date >= (calendar.dateInterval(of: .hour, for: now)?.start ?? now) }
        guard let hi = rest.map(\.temperature).max(), let lo = rest.map(\.temperature).min() else { return nil }
        return (hi, lo)
    }
}

/// One day of forecast for the forecast tile. The app fills these in from WeatherKit.
public struct DayForecast: Hashable, Sendable {
    public var date: Date
    public var high: Double
    public var low: Double
    public var symbol: String
    public var precipitationChance: Double
    public init(date: Date, high: Double, low: Double, symbol: String, precipitationChance: Double) {
        self.date = date; self.high = high; self.low = low; self.symbol = symbol; self.precipitationChance = precipitationChance
    }
}

extension WeatherText {
    /// "Sunset in 2 hr 5 min" / "Sunrise in 40 min": whichever comes next, for the sun tile. nil when neither is known.
    public static func nextSun(sunrise: Date?, sunset: Date?, tomorrowSunrise: Date?, now: Date) -> (title: String, at: Date)? {
        let options: [(String, Date?)] = [("Sunrise", sunrise), ("Sunset", sunset), ("Sunrise", tomorrowSunrise)]
        for (name, date) in options { if let date, date > now { return (name, date) } }
        return nil
    }

    /// The hands of an analogue clock, in degrees clockwise from 12.
    public static func clockAngles(hour: Int, minute: Int, second: Int = 0) -> (hour: Double, minute: Double, second: Double) {
        let m = Double(minute) + Double(second) / 60
        return ((Double(hour % 12) + m / 60) * 30, m * 6, Double(second) * 6)
    }
}
