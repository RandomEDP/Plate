import XCTest
@testable import PlateCore

final class DashboardTests: XCTestCase {
    // MARK: Grid

    private func ids(_ n: Int) -> [UUID] { (0..<n).map { _ in UUID() } }

    func testSmallTilesFillRowsLeftToRight() {
        let i = ids(5)
        let p = DashboardGrid.place(i.map { ($0, TileSize.small) }, columns: 4)
        XCTAssertEqual(p.map { [$0.column, $0.row] }, [[0, 0], [1, 0], [2, 0], [3, 0], [0, 1]])
        XCTAssertEqual(DashboardGrid.rowCount(p), 2)
    }

    func testSmallTilesFillTheGapBesideALargeOne() {
        let i = ids(4)
        let p = DashboardGrid.place([(i[0], .large), (i[1], .small), (i[2], .small), (i[3], .small)], columns: 3)
        // Large takes columns 0-1 on rows 0-1; the smalls go down column 2, then onto row 2.
        XCTAssertEqual(p[0], TilePlacement(id: i[0], column: 0, row: 0, columns: 2, rows: 2))
        XCTAssertEqual(p.dropFirst().map { [$0.column, $0.row] }, [[2, 0], [2, 1], [0, 2]])
    }

    func testWideTileSkipsAOneCellGap() {
        let i = ids(3)
        let p = DashboardGrid.place([(i[0], .small), (i[1], .small), (i[2], .wide)], columns: 3)
        XCTAssertEqual([p[2].column, p[2].row], [0, 1])
    }

    func testTilesNeverOverlap() {
        let sizes: [TileSize] = [.large, .small, .tall, .wide, .small, .large, .wide, .tall, .small, .small, .wide]
        for cols in 2...7 {
            let p = DashboardGrid.place(sizes.map { (UUID(), $0) }, columns: cols)
            var cells = Set<[Int]>()
            for t in p {
                XCTAssertLessThanOrEqual(t.column + t.columns, cols)
                for r in t.row..<(t.row + t.rows) {
                    for c in t.column..<(t.column + t.columns) {
                        XCTAssertTrue(cells.insert([r, c]).inserted, "Overlap at \(r),\(c) with \(cols) columns")
                    }
                }
            }
        }
    }

    func testTooWideTileIsNarrowedOnASingleColumn() {
        let p = DashboardGrid.place([(UUID(), .large)], columns: 1)
        XCTAssertEqual(p[0].columns, 1)
        XCTAssertEqual(p[0].rows, 2)
    }

    func testColumnsForScreenWidths() {
        XCTAssertEqual(DashboardGrid.columns(forWidth: 1180), 7)  // 11-inch iPad, landscape
        XCTAssertEqual(DashboardGrid.columns(forWidth: 820), 5)   // 11-inch iPad, portrait
        XCTAssertEqual(DashboardGrid.columns(forWidth: 390), 2)   // iPhone
        XCTAssertEqual(DashboardGrid.columns(forWidth: 0), 2)
    }

    /// Any screen, from a small phone to a foldable opened out or a big iPad, in either direction: tiles never get
    /// narrower than the minimum, a wider screen never gets fewer columns, and the grid still fits.
    func testColumnsAdaptToEveryWidth() {
        var previous = 0
        for width in stride(from: 320.0, through: 1400, by: 10) {
            let cols = DashboardGrid.columns(forWidth: width)
            XCTAssertGreaterThanOrEqual(cols, previous, "Width \(width)")
            previous = cols
            let tile = (width - 16 * Double(cols - 1)) / Double(cols)
            XCTAssertGreaterThanOrEqual(tile, width < 316 ? 0 : 150, "Width \(width)")
            let p = DashboardGrid.place(TileSize.allCases.map { (UUID(), $0) }, columns: cols)
            XCTAssertTrue(p.allSatisfy { $0.column + $0.columns <= cols }, "Width \(width)")
        }
    }

    func testFoldingChangesTheLayoutButNotTheOrder() {
        let i = ids(6)
        let sizes: [TileSize] = [.large, .small, .small, .wide, .small, .tall]
        let folded = DashboardGrid.place(Array(zip(i, sizes)).map { ($0.0, $0.1) }, columns: 2)
        let open = DashboardGrid.place(Array(zip(i, sizes)).map { ($0.0, $0.1) }, columns: 4)
        XCTAssertEqual(folded.map(\.id), i)
        XCTAssertEqual(open.map(\.id), i)
        XCTAssertLessThan(DashboardGrid.rowCount(open), DashboardGrid.rowCount(folded), "Opened out, more fits on screen")
    }

    // MARK: Editing

    func testAddingTheSameThingTwiceKeepsOne() {
        var d = HomeDashboard()
        XCTAssertTrue(d.add(DashboardTile(kind: .scene, ref: "A", title: "Relax")))
        XCTAssertFalse(d.add(DashboardTile(kind: .scene, ref: "A", title: "Relax")))
        XCTAssertTrue(d.add(DashboardTile(kind: .scene, ref: "B", title: "Bedtime")))
        XCTAssertTrue(d.add(DashboardTile(kind: .clock, title: "Clock")))
        XCTAssertFalse(d.add(DashboardTile(kind: .clock, title: "Clock")))
        XCTAssertTrue(d.add(DashboardTile(kind: .note, title: "Note", subtitle: "Bins")))
        XCTAssertTrue(d.add(DashboardTile(kind: .note, title: "Note", subtitle: "Bins")), "Notes can repeat")
        XCTAssertEqual(d.tiles.count, 5)
    }

    func testMoveForwardsAndBackwards() {
        var d = HomeDashboard(tiles: ["A", "B", "C", "D"].map { DashboardTile(kind: .note, title: $0) })
        let id = { (t: String) in d.tiles.first { $0.title == t }!.id }
        d.move(id("A"), before: id("C"))
        XCTAssertEqual(d.tiles.map(\.title), ["B", "C", "A", "D"])
        d.move(id("D"), before: id("B"))
        XCTAssertEqual(d.tiles.map(\.title), ["D", "B", "C", "A"])
        d.move(id("D"), before: id("D"))
        XCTAssertEqual(d.tiles.map(\.title), ["D", "B", "C", "A"])
    }

    func testShiftStopsAtTheEnds() {
        var d = HomeDashboard(tiles: ["A", "B", "C"].map { DashboardTile(kind: .note, title: $0) })
        let a = d.tiles[0].id
        d.shift(a, by: -1)
        XCTAssertEqual(d.tiles.map(\.title), ["A", "B", "C"])
        d.shift(a, by: 1)
        XCTAssertEqual(d.tiles.map(\.title), ["B", "A", "C"])
    }

    func testResizeAndRemove() {
        var d = HomeDashboard(tiles: [DashboardTile(kind: .scene, ref: "S", title: "Relax")])
        XCTAssertEqual(d.tiles[0].size, .small)
        d.resize(d.tiles[0].id, to: .wide)
        XCTAssertEqual(d.tiles[0].size, .wide)
        d.remove(d.tiles[0].id)
        XCTAssertTrue(d.tiles.isEmpty)
    }

    func testMissingHomeTilesOnlyCountsHomeKitTiles() {
        let d = HomeDashboard(tiles: [
            DashboardTile(kind: .accessory, ref: "lamp", title: "Lamp"),
            DashboardTile(kind: .scene, ref: "gone", title: "Old scene"),
            DashboardTile(kind: .musicAlbum, ref: "123", title: "Album"),
            DashboardTile(kind: .clock, title: "Clock"),
        ])
        XCTAssertEqual(d.missingHomeTiles(knownIds: ["lamp"]).map(\.title), ["Old scene"])
    }

    // MARK: Saving

    func testOldHouseholdFileWithoutADashboardStillOpens() throws {
        let json = #"{"name":"Flat","extras":{}}"#
        let h = try JSONDecoder().decode(Household.self, from: Data(json.utf8))
        XCTAssertEqual(h.name, "Flat")
        XCTAssertTrue(h.dashboard.tiles.isEmpty)
        XCTAssertEqual(h.dashboard.idle.minutes, 3)
    }

    func testDashboardRoundTrips() throws {
        var h = Household()
        h.dashboard.add(DashboardTile(kind: .musicAlbum, ref: "1440", title: "Blue", subtitle: "Joni Mitchell"))
        h.dashboard.idle.photoAlbumId = "ABC/L0/001"
        let back = try JSONDecoder().decode(Household.self, from: JSONEncoder().encode(h))
        XCTAssertEqual(back.dashboard, h.dashboard)
    }

    func testTileKindsFromANewerPlateAreKeptButHidden() throws {
        let json = """
        {"tiles":[{"kind":"hologram","title":"Hologram","size":"huge"},{"kind":"clock","title":"Clock"}],
         "idle":{"minutes":5,"lasers":true}}
        """
        let d = try JSONDecoder().decode(HomeDashboard.self, from: Data(json.utf8))
        XCTAssertEqual(d.tiles.count, 2)
        XCTAssertEqual(d.tiles[0].kind, .unknown)
        XCTAssertEqual(d.tiles[0].size, .small)
        XCTAssertEqual(d.tiles[1].size, .large, "A clock with no size saved gets the clock's usual size")
        XCTAssertEqual(d.visibleTiles.map(\.kind), [.clock])
        XCTAssertEqual(d.idle.minutes, 5)
        XCTAssertEqual(d.idle.secondsPerSlide, 20)
    }

    // MARK: Starting layout

    func testStarterLayoutPutsScenesThenRoomsAndSkipsSensors() {
        let tiles = DashboardStarter.layout(
            accessories: [
                AccessorySummary(id: "1", name: "Ceiling", room: "Living room", category: .light),
                AccessorySummary(id: "2", name: "Motion", room: "Hall", category: .sensor),
                AccessorySummary(id: "3", name: "Lamp", room: "Bedroom", category: .light),
                AccessorySummary(id: "4", name: "Kettle", room: "Kitchen", category: .outlet),
                AccessorySummary(id: "5", name: "Front door", room: "Hall", category: .lock),
            ],
            scenes: [SceneSummary(id: "a", name: "Goodnight"), SceneSummary(id: "b", name: "Good morning"),
                     SceneSummary(id: "c", name: "Party")])
        XCTAssertEqual(tiles.first?.kind, .clock)
        XCTAssertEqual(tiles.filter { $0.kind == .scene }.map(\.title), ["Good morning", "Goodnight", "Party"])
        XCTAssertEqual(tiles.filter { $0.kind == .accessory }.map(\.title), ["Lamp", "Front door", "Kettle", "Ceiling"])
        XCTAssertEqual(tiles.suffix(2).map(\.kind), [.todaysMeals, .useSoon])
    }

    func testStarterLayoutCapsAccessories() {
        let many = (0..<30).map { AccessorySummary(id: "\($0)", name: "Light \($0)", room: "Room", category: .light) }
        let tiles = DashboardStarter.layout(accessories: many, scenes: [], maxAccessories: 8)
        XCTAssertEqual(tiles.filter { $0.kind == .accessory }.count, 8)
    }

    // MARK: Idle

    func testIdleAfterTheSetMinutes() {
        let s = IdleSettings(minutes: 3)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(IdleMode.isIdle(lastTouch: t0, now: t0.addingTimeInterval(179), settings: s))
        XCTAssertTrue(IdleMode.isIdle(lastTouch: t0, now: t0.addingTimeInterval(180), settings: s))
        XCTAssertEqual(IdleMode.secondsUntilIdle(lastTouch: t0, now: t0.addingTimeInterval(60), settings: s), 120)
        XCTAssertEqual(IdleMode.secondsUntilIdle(lastTouch: t0, now: t0.addingTimeInterval(500), settings: s), 0)
    }

    func testIdleOffNeverTriggers() {
        let s = IdleSettings(minutes: 0)
        let t0 = Date()
        XCTAssertFalse(IdleMode.isIdle(lastTouch: t0, now: t0.addingTimeInterval(86_400), settings: s))
        XCTAssertNil(IdleMode.secondsUntilIdle(lastTouch: t0, now: t0, settings: s))
    }

    private func at(_ h: Int, _ m: Int) -> Date {
        Calendar.plate.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: h, minute: m))!
    }

    func testNightRunsPastMidnight() {
        let s = IdleSettings(nightStart: 23 * 60, nightEnd: 7 * 60)
        XCTAssertFalse(IdleMode.isNight(at(22, 59), settings: s))
        XCTAssertTrue(IdleMode.isNight(at(23, 0), settings: s))
        XCTAssertTrue(IdleMode.isNight(at(3, 30), settings: s))
        XCTAssertTrue(IdleMode.isNight(at(6, 59), settings: s))
        XCTAssertFalse(IdleMode.isNight(at(7, 0), settings: s))
        XCTAssertFalse(IdleMode.isNight(at(12, 0), settings: s))
    }

    func testNightWithinOneDay() {
        let s = IdleSettings(nightStart: 13 * 60, nightEnd: 14 * 60)
        XCTAssertTrue(IdleMode.isNight(at(13, 30), settings: s))
        XCTAssertFalse(IdleMode.isNight(at(14, 0), settings: s))
        XCTAssertFalse(IdleMode.isNight(at(23, 0), settings: s))
    }

    func testDimmingOffOrSameTimesNeverDims() {
        XCTAssertEqual(IdleMode.dimming(at(2, 0), settings: IdleSettings(nightDim: false)), 0)
        XCTAssertEqual(IdleMode.dimming(at(2, 0), settings: IdleSettings(nightStart: 60, nightEnd: 60)), 0)
        XCTAssertEqual(IdleMode.dimming(at(2, 0), settings: IdleSettings(nightDarkness: 0.5)), 0.5)
        XCTAssertEqual(IdleMode.dimming(at(2, 0), settings: IdleSettings(nightDarkness: 3)), 0.95, "Never fully black")
    }

    func testTimeText() {
        XCTAssertEqual(IdleMode.timeText(23 * 60), "23:00")
        XCTAssertEqual(IdleMode.timeText(7 * 60 + 5), "07:05")
        XCTAssertEqual(IdleMode.timeText(1440 + 30), "00:30")
    }

    func testIdleShowsTheAlbumPlayingOtherwiseThePhotos() {
        XCTAssertEqual(IdleArtwork.choose(musicPlaying: true, hasNowPlayingArtwork: true, photoCount: 40), .nowPlaying)
        XCTAssertEqual(IdleArtwork.choose(musicPlaying: false, hasNowPlayingArtwork: true, photoCount: 40), .photos,
                       "Paused music goes back to the photos")
        XCTAssertEqual(IdleArtwork.choose(musicPlaying: true, hasNowPlayingArtwork: false, photoCount: 40), .photos)
        XCTAssertEqual(IdleArtwork.choose(musicPlaying: true, hasNowPlayingArtwork: false, photoCount: 0), .clockOnly)
        XCTAssertEqual(IdleArtwork.choose(musicPlaying: false, hasNowPlayingArtwork: false, photoCount: 0), .clockOnly)
    }

    // MARK: Weather

    private func hours(from h: Int, chances: [Double], temps: [Double]? = nil) -> [HourForecast] {
        chances.enumerated().map { i, c in
            HourForecast(date: at(h + i, 0), temperature: temps?[i] ?? 10, precipitationChance: c)
        }
    }

    func testRainNote() {
        XCTAssertNil(WeatherText.rainNote(hours(from: 9, chances: [0.1, 0.2, 0.3]), now: at(9, 20)))
        XCTAssertEqual(WeatherText.rainNote(hours(from: 9, chances: [0.1, 0.2, 0.7]), now: at(9, 20)), "Rain likely from 11:00")
        XCTAssertEqual(WeatherText.rainNote(hours(from: 9, chances: [0.8, 0.2]), now: at(9, 40)), "Rain now")
        XCTAssertNil(WeatherText.rainNote(hours(from: 7, chances: [0.9, 0.1, 0.1]), now: at(9, 0)), "Rain that's been and gone")
    }

    func testRainMoreThanTwelveHoursAwayIsIgnored() {
        var h = hours(from: 0, chances: Array(repeating: 0.0, count: 20))
        h[14].precipitationChance = 0.9
        XCTAssertNil(WeatherText.rainNote(h, now: at(1, 0)))
    }

    func testTemperatureText() {
        XCTAssertEqual(WeatherText.temperature(12.4), "12°")
        XCTAssertEqual(WeatherText.temperature(12.5), "13°")
        XCTAssertEqual(WeatherText.temperature(-0.3), "0°")
        XCTAssertEqual(WeatherText.temperature(-3.6), "-4°")
    }

    func testRangeIsTheRestOfToday() {
        let h = hours(from: 6, chances: Array(repeating: 0, count: 6), temps: [3, 5, 9, 14, 12, 8])
        XCTAssertEqual(WeatherText.range(h, now: at(8, 30)).map { [$0.high, $0.low] }, [14, 8])
        XCTAssertNil(WeatherText.range([], now: at(8, 0)))
    }

    func testWeatherIsAWideSingleTile() {
        var d = HomeDashboard()
        XCTAssertTrue(d.add(DashboardTile(kind: .weather, title: "Weather")))
        XCTAssertFalse(d.add(DashboardTile(kind: .weather, title: "Weather")))
        XCTAssertEqual(d.tiles[0].size, .wide)
    }

    // MARK: Slideshow

    func testSlideshowShowsEveryPictureBeforeRepeating() {
        var s = Slideshow(items: ["a", "b", "c", "d", "e"], seed: 42)
        for _ in 0..<4 {
            let round = (0..<5).compactMap { _ in s.next() }
            XCTAssertEqual(Set(round), ["a", "b", "c", "d", "e"])
        }
    }

    func testSlideshowNeverShowsTheSamePictureTwiceInARow() {
        for seed in UInt64(1)...200 {
            var s = Slideshow(items: ["a", "b", "c"], seed: seed)
            var last: String?
            for _ in 0..<30 {
                let n = s.next()
                XCTAssertNotEqual(n, last, "Seed \(seed)")
                last = n
            }
        }
    }

    func testSlideshowIsRepeatableWithASeed() {
        var a = Slideshow(items: ["a", "b", "c", "d"], seed: 7)
        var b = Slideshow(items: ["d", "c", "b", "a"], seed: 7)
        XCTAssertEqual((0..<12).map { _ in a.next() }, (0..<12).map { _ in b.next() })
    }

    func testSlideshowEmptyAndUpdated() {
        var s = Slideshow(items: [], seed: 1)
        XCTAssertNil(s.next())
        s.update(items: ["x"])
        XCTAssertEqual(s.next(), "x")
        XCTAssertEqual(s.next(), "x", "One picture just stays up")
        var t = Slideshow(items: ["a", "b", "c"], seed: 3)
        _ = t.next()
        t.update(items: ["a"])
        XCTAssertEqual(t.next(), "a")
    }

    // MARK: Adding the same tile more than once (Ethan, 12 November 2026: music tiles added twice, then resized
    // and removed together)

    func testAddingTheSameTileTwiceGivesTwoSeparateTiles() {
        var d = HomeDashboard()
        let row = DashboardTile(kind: .musicAlbum, title: "Music tile")
        XCTAssertTrue(d.add(row))
        XCTAssertTrue(d.add(row), "An empty music tile can be added again")
        XCTAssertEqual(d.tiles.count, 2)
        XCTAssertEqual(Set(d.tiles.map(\.id)).count, 2, "Each copy gets its own id")

        d.resize(d.tiles[1].id, to: .small)
        XCTAssertEqual(d.tiles.map(\.size), [.large, .small], "Resizing one leaves the other alone")

        d.remove(d.tiles[0].id)
        XCTAssertEqual(d.tiles.count, 1, "Removing one leaves the other")
        XCTAssertEqual(d.tiles[0].size, .small)
    }

    func testRepeatableTilesAddedTwiceStaySeparate() {
        var d = HomeDashboard()
        let note = DashboardTile(kind: .note, title: "Note")
        d.add(note); d.add(note); d.add(note)
        XCTAssertEqual(Set(d.tiles.map(\.id)).count, 3)
        d.shift(d.tiles[2].id, by: -1)
        XCTAssertEqual(d.tiles.count, 3)
    }

    func testSavedDashboardsWithSharedIdsAreRepaired() throws {
        let id = UUID()
        var d = HomeDashboard()
        d.tiles = [DashboardTile(id: id, kind: .musicAlbum, title: "One"), DashboardTile(id: id, kind: .musicAlbum, title: "Two"),
                   DashboardTile(id: id, kind: .note, title: "Three")]
        let back = try JSONDecoder().decode(HomeDashboard.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back.tiles.map(\.title), ["One", "Two", "Three"], "Nothing is lost")
        XCTAssertEqual(back.tiles[0].id, id, "The first keeps its id")
        XCTAssertEqual(Set(back.tiles.map(\.id)).count, 3)
    }

    // MARK: Moving tiles freely (Ethan, 12 November 2026: drag a tile anywhere; empty spots stay empty)

    private func spots(_ d: HomeDashboard, columns: Int = 4) -> [String: [Int]] {
        let page = d.pageList[0].id
        let tiles = d.tiles(onPage: page)
        let placed = DashboardGrid.place(tiles.map { (id: $0.id, size: $0.size, row: $0.row, column: $0.column) }, columns: columns)
        var out: [String: [Int]] = [:]
        for (t, p) in zip(tiles, placed) { out[t.title] = [p.row, p.column] }
        return out
    }

    private func smallTiles(_ names: [String]) -> HomeDashboard {
        var d = HomeDashboard()
        for n in names { d.add(DashboardTile(kind: .note, title: n, size: .small)) }
        return d
    }

    func testTilesWithASpotKeepItAndLeaveGaps() {
        let a = UUID(), b = UUID(), c = UUID()
        let placed = DashboardGrid.place([(id: a, size: .small, row: 2, column: 3), (id: b, size: .small, row: nil, column: nil),
                                          (id: c, size: .wide, row: 0, column: 1)], columns: 4)
        XCTAssertEqual(placed.map(\.id), [a, b, c], "Same order as asked")
        XCTAssertEqual([placed[0].row, placed[0].column], [2, 3])
        XCTAssertEqual([placed[2].row, placed[2].column], [0, 1])
        XCTAssertEqual([placed[1].row, placed[1].column], [0, 0], "Tiles without a spot fill the first gap")
        XCTAssertEqual(DashboardGrid.rowCount(placed), 3, "The empty row in between is kept")
    }

    func testASpotThatDoesNotFitFallsBackToTheFirstGap() {
        let a = UUID(), b = UUID()
        let placed = DashboardGrid.place([(id: a, size: .wide, row: 0, column: 5), (id: b, size: .small, row: 0, column: 0)], columns: 2)
        XCTAssertEqual([placed[1].row, placed[1].column], [0, 0])
        XCTAssertEqual([placed[0].row, placed[0].column], [1, 0], "Too far right for a phone: it goes in the next gap")
        let clash = DashboardGrid.place([(id: a, size: .small, row: 1, column: 1), (id: b, size: .small, row: 1, column: 1)], columns: 3)
        XCTAssertFalse(DashboardGrid.overlap(clash[0], clash[1]), "Two tiles never share a cell")
    }

    func testDraggingATileToAnEmptyCell() {
        var d = smallTiles(["A", "B", "C"])
        XCTAssertEqual(spots(d), ["A": [0, 0], "B": [0, 1], "C": [0, 2]])
        d.moveTile(d.tiles[0].id, toRow: 2, column: 3, columns: 4)
        XCTAssertEqual(spots(d), ["A": [2, 3], "B": [0, 1], "C": [0, 2]], "The others stay put and A's old spot stays empty")
    }

    func testDraggingOntoAnotherTileSwapsThem() {
        var d = smallTiles(["A", "B", "C"])
        d.moveTile(d.tiles[0].id, toRow: 0, column: 2, columns: 4)
        XCTAssertEqual(spots(d), ["A": [0, 2], "B": [0, 1], "C": [0, 0]])
    }

    func testDraggingABigTileOverSeveralMovesThemOutOfTheWay() {
        var d = smallTiles(["A", "B", "C"])
        d.add(DashboardTile(kind: .note, title: "Big", size: .large))
        XCTAssertEqual(spots(d)["Big"], [1, 0])
        d.moveTile(d.tiles[3].id, toRow: 0, column: 0, columns: 4)
        let s = spots(d)
        XCTAssertEqual(s["Big"], [0, 0])
        XCTAssertEqual(s["C"], [0, 2], "Not in the way, so it stays")
        let placed = DashboardGrid.place(d.tiles.map { (id: $0.id, size: $0.size, row: $0.row, column: $0.column) }, columns: 4)
        for i in placed.indices { for j in placed.indices where i < j { XCTAssertFalse(DashboardGrid.overlap(placed[i], placed[j])) } }
    }

    func testDraggingTooFarRightKeepsTheTileOnTheGrid() {
        var d = smallTiles(["A"])
        d.add(DashboardTile(kind: .note, title: "Wide", size: .wide))
        d.moveTile(d.tiles[1].id, toRow: 1, column: 3, columns: 4)
        XCTAssertEqual(spots(d)["Wide"], [1, 2])
    }

    func testRemovingATileLeavesItsSpaceOnceTilesHaveBeenMoved() {
        var d = smallTiles(["A", "B", "C"])
        d.moveTile(d.tiles[2].id, toRow: 1, column: 0, columns: 4)
        d.remove(d.tiles[0].id)
        XCTAssertEqual(spots(d), ["B": [0, 1], "C": [1, 0]], "B doesn't slide into A's place")
        d.add(DashboardTile(kind: .note, title: "New", size: .small))
        XCTAssertEqual(spots(d)["New"], [0, 0], "A new tile goes in the first gap")
    }

    func testTidyingAPageClosesTheGaps() {
        var d = smallTiles(["A", "B"])
        d.moveTile(d.tiles[1].id, toRow: 3, column: 3, columns: 4)
        d.tidyPage(d.pageList[0].id)
        XCTAssertEqual(spots(d), ["A": [0, 0], "B": [0, 1]])
    }

    func testMovingToAnotherPageOrFolderForgetsTheSpot() {
        var d = smallTiles(["A"])
        d.moveTile(d.tiles[0].id, toRow: 2, column: 2, columns: 4)
        let page = d.addPage(named: "Music")
        d.moveTile(d.tiles[0].id, toPage: page)
        XCTAssertNil(d.tiles[0].row)
        XCTAssertNil(d.tiles[0].column)
    }

    func testSpotsAreSavedAndOldFilesHaveNone() throws {
        var d = smallTiles(["A"])
        d.moveTile(d.tiles[0].id, toRow: 1, column: 2, columns: 4)
        let back = try JSONDecoder().decode(HomeDashboard.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back.tiles[0].row, 1)
        XCTAssertEqual(back.tiles[0].column, 2)
        let old = try JSONDecoder().decode(DashboardTile.self, from: Data(#"{"kind":"note","title":"Old"}"#.utf8))
        XCTAssertNil(old.row)
    }
}
