import XCTest
@testable import PlateCore

final class TrainTests: XCTestCase {
    /// A cut-down reply in the feed's own shape: a stopping Elizabeth line train, a fast Great Western one that's
    /// running late, a cancelled one, and one going the other way.
    static let reply = ##"""
    {
      "locationName": "Reading", "crs": "RDG",
      "nrccMessages": [{"Value": "<p>Lifts at <a href=\"#\">Reading</a> are out of order &amp; being fixed.</p>"}],
      "trainServices": [
        {"std": "10:02", "etd": "On time", "platform": "14", "operator": "Elizabeth line", "operatorCode": "XR", "serviceID": "a1", "length": 9,
         "isCancelled": false, "destination": [{"locationName": "Abbey Wood", "crs": "ABW"}],
         "subsequentCallingPoints": [{"callingPoint": [
            {"locationName": "Twyford", "crs": "TWY", "st": "10:08", "et": "On time"},
            {"locationName": "Maidenhead", "crs": "MAI", "st": "10:16", "et": "On time"},
            {"locationName": "Slough", "crs": "SLO", "st": "10:24", "et": "On time"},
            {"locationName": "London Paddington", "crs": "PAD", "st": "10:55", "et": "On time"},
            {"locationName": "Abbey Wood", "crs": "ABW", "st": "11:25", "et": "On time"}]}]},
        {"std": "10:05", "etd": "10:09", "platform": "10", "operator": "Great Western Railway", "operatorCode": "GW", "serviceID": "b2",
         "destination": [{"locationName": "London Paddington", "crs": "PAD"}],
         "subsequentCallingPoints": [{"callingPoint": [{"locationName": "London Paddington", "crs": "PAD", "st": "10:30", "et": "10:34"}]}]},
        {"std": "10:12", "etd": "Cancelled", "operator": "Great Western Railway", "operatorCode": "GW", "serviceID": "c3", "isCancelled": true,
         "destination": [{"locationName": "London Paddington", "crs": "PAD"}],
         "subsequentCallingPoints": [{"callingPoint": [{"locationName": "London Paddington", "crs": "PAD", "st": "10:38", "et": "Cancelled"}]}]},
        {"std": "10:15", "etd": "Delayed", "platform": "8", "operator": "Great Western Railway", "operatorCode": "GW", "serviceID": "d4",
         "destination": [{"locationName": "Bristol Temple Meads", "crs": "BRI"}],
         "subsequentCallingPoints": [{"callingPoint": [{"locationName": "Swindon", "crs": "SWI", "st": "10:40", "et": "Delayed"}]}]}
      ]
    }
    """##

    func board() throws -> TrainBoard { try Trains.parse(Data(Self.reply.utf8)) }

    func testReadsTheFeed() throws {
        let b = try board()
        XCTAssertEqual(b.station, "Reading")
        XCTAssertEqual(b.departures.count, 4)
        let first = b.departures[0]
        XCTAssertEqual(first.scheduled, "10:02")
        XCTAssertEqual(first.platform, "14")
        XCTAssertEqual(first.operatorCode, "XR")
        XCTAssertEqual(first.destination, "Abbey Wood")
        XCTAssertEqual(first.calls.count, 5)
        XCTAssertEqual(first.length, 9)
        XCTAssertNil(b.departures[2].platform)
        XCTAssertTrue(b.departures[2].isCancelled)
        XCTAssertEqual(b.messages, ["Lifts at Reading are out of order & being fixed."])
    }

    func testOddRepliesDoNotCrash() throws {
        XCTAssertEqual(try Trains.parse(Data("{}".utf8)).departures.count, 0)
        XCTAssertEqual(try Trains.parse(Data(#"{"trainServices":null,"locationName":"X"}"#.utf8)).station, "X")
        XCTAssertThrowsError(try Trains.parse(Data("[1,2]".utf8)))
        XCTAssertThrowsError(try Trains.parse(Data("not json".utf8)))
        // A train with no stop details and no destination still shows.
        let bare = try Trains.parse(Data(#"{"trainServices":[{"std":"09:00"}]}"#.utf8))
        XCTAssertEqual(bare.departures.first?.expected, "On time")
        XCTAssertEqual(bare.departures.first?.destination, "Unknown")
    }

    func testStatusAndLateness() throws {
        let d = try board().departures
        XCTAssertEqual(d[0].status, "On time")
        XCTAssertEqual(d[1].status, "4 min late")
        XCTAssertEqual(d[1].leaves, "10:09")
        XCTAssertEqual(d[2].status, "Cancelled")
        XCTAssertEqual(d[3].status, "Delayed")
        XCTAssertNil(d[3].minutesLate)
        XCTAssertEqual(d[3].leaves, "10:15", "With no new time, the timetable is all there is")
    }

    func testTimes() {
        XCTAssertEqual(TrainTime.minutes("09:05"), 545)
        XCTAssertNil(TrainTime.minutes("On time"))
        XCTAssertNil(TrainTime.minutes("25:00"))
        XCTAssertEqual(TrainTime.forward(from: 23 * 60 + 50, to: 10), 20, "Past midnight")
        XCTAssertEqual(TrainTime.signed(from: 600, to: 598), -2, "Left two minutes ago")
        XCTAssertEqual(TrainTime.signed(from: 23 * 60 + 58, to: 3), 5)
        XCTAssertEqual(TrainTime.countdown(0), "Due")
        XCTAssertEqual(TrainTime.countdown(7), "7 min")
        XCTAssertEqual(TrainTime.countdown(72), "1 hr 12 min")
    }

    func testIntoLondonMarksTheFastTrain() throws {
        let rows = Trains.rows(try board(), query: TrainQuery(from: "rdg", to: "pad"), nowMinutes: 10 * 60)
        XCTAssertEqual(rows.map(\.id), ["a1", "b2", "c3"], "The Bristol train doesn't go to Paddington")
        XCTAssertFalse(rows[0].isFast)
        XCTAssertEqual(rows[0].stops, 3)
        XCTAssertEqual(rows[0].journeyMinutes, 53)
        XCTAssertEqual(rows[0].arrival, "10:55")
        XCTAssertTrue(rows[1].isFast, "25 minutes against 53")
        XCTAssertEqual(rows[1].stops, 0)
        XCTAssertEqual(rows[1].arrival, "10:34", "Uses the expected arrival when the train is late")
        XCTAssertEqual(rows[1].journeyMinutes, 25)
        XCTAssertEqual(Trains.stopsText(0), "Non-stop")
        XCTAssertEqual(Trains.stopsText(3), "3 stops")
    }

    func testChoosingOperatorsAndFastOnly() throws {
        let b = try board()
        let lizzie = Trains.rows(b, query: TrainQuery(from: "RDG", to: "PAD", operators: ["xr"]), nowMinutes: 600)
        XCTAssertEqual(lizzie.map(\.id), ["a1"])
        let gw = Trains.rows(b, query: TrainQuery(from: "RDG", to: "PAD", operators: ["GW"]), nowMinutes: 600)
        XCTAssertEqual(gw.map(\.id), ["b2", "c3"])
        XCTAssertTrue(gw[0].isFast, "Still fast compared with the stopping train that isn't shown")
        let fast = Trains.rows(b, query: TrainQuery(from: "RDG", to: "PAD", fastOnly: true), nowMinutes: 600)
        XCTAssertEqual(fast.map(\.id), ["b2", "c3"])
        let all = Trains.rows(b, query: TrainQuery(from: "RDG"), nowMinutes: 600)
        XCTAssertEqual(all.count, 4)
        XCTAssertFalse(all.contains(where: \.isFast), "Nothing is fast without somewhere to be fast to")
    }

    func testTrainsThatHaveGoneDropOffAndOrderFollowsRealDepartures() throws {
        let b = try board()
        XCTAssertEqual(Trains.rows(b, query: TrainQuery(from: "RDG", to: "PAD"), nowMinutes: 10 * 60 + 4).map(\.id), ["b2", "c3"])
        // 10:05 running at 10:09 leaves after nothing else here, but a late train sorts by when it really goes.
        var late = b
        late.departures[0].expected = "10:20"
        XCTAssertEqual(Trains.rows(late, query: TrainQuery(from: "RDG", to: "PAD"), nowMinutes: 600).map(\.id), ["b2", "c3", "a1"])
    }

    func testAllSlowTrainsMeansNoneAreFast() {
        func train(_ id: String, _ std: String, arrive: String) -> TrainDeparture {
            TrainDeparture(id: id, scheduled: std, expected: "On time", operatorName: "X", operatorCode: "XX", destination: "B",
                           calls: [TrainCall(name: "B", crs: "BBB", scheduled: arrive)])
        }
        let b = TrainBoard(station: "A", departures: [train("1", "10:00", arrive: "10:30"), train("2", "10:10", arrive: "10:38")])
        XCTAssertFalse(Trains.rows(b, query: TrainQuery(from: "AAA", to: "BBB"), nowMinutes: 590).contains(where: \.isFast))
    }

    func testRequest() {
        let url = Trains.url(for: TrainQuery(from: "rdg", to: "pad"))
        XCTAssertEqual(url?.host, "api1.raildata.org.uk")
        XCTAssertEqual(url?.path, "/1010-live-departure-board-dep1_2/LDBWS/api/20220120/GetDepBoardWithDetails/RDG")
        XCTAssertTrue(url?.query?.contains("filterCrs=PAD") == true)
        XCTAssertTrue(url?.query?.contains("filterType=to") == true)
        XCTAssertEqual(Trains.url(for: TrainQuery(from: "RDG"), details: false)?.path.hasSuffix("/GetDepartureBoard/RDG"), true)
        XCTAssertFalse(Trains.url(for: TrainQuery(from: "RDG"))?.query?.contains("filterCrs") == true)
        XCTAssertNil(Trains.url(for: TrainQuery(from: "")))
        XCTAssertNil(Trains.url(for: TrainQuery(from: "R/G")), "Only letters go into the address")
    }

    func testTileSettings() {
        let q = TrainQuery(options: ["from": "rdg", "to": "pad", "ops": "xr, gw", "fast": "1"])
        XCTAssertEqual(q.from, "RDG")
        XCTAssertEqual(q.operators, ["XR", "GW"])
        XCTAssertTrue(q.fastOnly)
        XCTAssertEqual(q.title, "Reading to London Paddington")
        XCTAssertFalse(TrainQuery(options: [:]).isReady)
    }

    func testStationSearch() {
        XCTAssertEqual(TrainStation.search("padd").first?.crs, "PAD")
        XCTAssertEqual(TrainStation.search("RDG").first?.name, "Reading")
        XCTAssertEqual(TrainStation.search("zzq").first?.crs, "ZZQ", "Any three-letter code can be used")
        XCTAssertEqual(TrainStation.search("").count, TrainStation.common.count)
        XCTAssertEqual(Set(TrainStation.common.map(\.crs)).count, TrainStation.common.count, "No code twice")
        XCTAssertEqual(Trains.operators(on: try! board()).map(\.code), ["XR", "GW"])
    }

    func testEmptyMusicTilesCanBeAddedMoreThanOnce() {
        var d = HomeDashboard()
        XCTAssertTrue(d.add(DashboardTile(kind: .musicAlbum, title: "Album")))
        XCTAssertTrue(d.add(DashboardTile(kind: .musicAlbum, title: "Album")), "Two empty album tiles, each to be chosen later")
        XCTAssertTrue(d.add(DashboardTile(kind: .musicAlbum, ref: "1", title: "Blue")))
        XCTAssertFalse(d.add(DashboardTile(kind: .musicAlbum, ref: "1", title: "Blue")), "The same album twice is still a duplicate")
        XCTAssertTrue(d.add(DashboardTile(kind: .trains, title: "Trains")))
        XCTAssertTrue(d.add(DashboardTile(kind: .trains, title: "Trains")))
    }

    // MARK: Folders

    func testFolderHoldsTilesAndGivesThemBack() throws {
        var d = HomeDashboard()
        let folder = DashboardTile(kind: .folder, title: "Evening")
        let scene = DashboardTile(kind: .scene, ref: "s1", title: "Relax")
        let lamp = DashboardTile(kind: .accessory, ref: "a1", title: "Lamp")
        let clock = DashboardTile(kind: .clock, title: "Clock")
        for t in [folder, scene, lamp, clock] { d.add(t) }
        d.moveTile(scene.id, toFolder: folder.id)
        d.moveTile(lamp.id, toFolder: folder.id)
        XCTAssertEqual(d.tiles(onPage: HomeDashboard.firstPageId).map(\.id), [folder.id, clock.id], "What's in a folder isn't on the page")
        XCTAssertEqual(d.tiles(inFolder: folder.id).map(\.id), [scene.id, lamp.id])
        XCTAssertEqual(d.folders.map(\.id), [folder.id])

        // It survives saving and opening again.
        let back = try JSONDecoder().decode(HomeDashboard.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back.tiles(inFolder: folder.id).count, 2)

        d.moveTile(lamp.id, toFolder: nil)
        XCTAssertEqual(d.tiles(inFolder: folder.id).map(\.id), [scene.id])
        XCTAssertTrue(d.tiles(onPage: HomeDashboard.firstPageId).contains { $0.id == lamp.id })

        d.remove(folder.id)
        XCTAssertTrue(d.tiles(onPage: HomeDashboard.firstPageId).contains { $0.id == scene.id }, "Removing a folder keeps what was in it")
        XCTAssertNil(d.tiles.first { $0.id == scene.id }?.folderId)
    }

    func testFoldersDoNotNestAndFollowTheirPage() {
        var d = HomeDashboard()
        let a = DashboardTile(kind: .folder, title: "A"), b = DashboardTile(kind: .folder, title: "B")
        let note = DashboardTile(kind: .note, title: "Note")
        for t in [a, b, note] { d.add(t) }
        d.moveTile(a.id, toFolder: b.id)
        XCTAssertNil(d.tiles.first { $0.id == a.id }?.folderId, "A folder can't go in a folder")
        d.moveTile(note.id, toFolder: note.id)
        d.moveTile(note.id, toFolder: UUID())
        XCTAssertNil(d.tiles.first { $0.id == note.id }?.folderId, "Nor into something that isn't a folder")

        d.moveTile(note.id, toFolder: a.id)
        let music = d.addPage(named: "Music")
        d.moveTile(a.id, toPage: music)
        XCTAssertEqual(d.tiles(onPage: music).map(\.id), [a.id])
        XCTAssertEqual(d.tiles.first { $0.id == note.id }?.pageId, music, "The contents go with the folder")
        // A tile whose folder has vanished (an old or hand-edited file) shows on its page again.
        d.tiles.removeAll { $0.id == a.id }
        XCTAssertTrue(d.tiles(onPage: music).contains { $0.id == note.id })
        XCTAssertEqual(Set(TileKind.allCases.map(\.symbol)).contains(""), false)
    }
}
