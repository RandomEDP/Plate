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
        {"tiles":[{"kind":"weather","title":"Weather","size":"huge"},{"kind":"clock","title":"Clock"}],
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
}
