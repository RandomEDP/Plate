import XCTest
@testable import PlateCore

/// Tapping a train on the trains tile lists every stop with its times.
final class TrainStopsTests: XCTestCase {
    func board() throws -> TrainBoard { try Trains.parse(Data(TrainTests.reply.utf8)) }

    func testEveryStopAfterTheStationInOrder() throws {
        let d = try board().departures[0]
        let stops = TrainStops.list(d, station: "Reading", crs: "rdg", to: "PAD")
        XCTAssertEqual(stops.map(\.crs), ["RDG", "TWY", "MAI", "SLO", "PAD", "ABW"])
        XCTAssertEqual(stops[0].place, .here)
        XCTAssertEqual(stops[0].platform, "14")
        XCTAssertEqual(stops[0].name, "Reading")
        XCTAssertEqual(stops.map(\.time), ["10:02", "10:08", "10:16", "10:24", "10:55", "11:25"])
        XCTAssertTrue(stops.allSatisfy { $0.status == "On time" })
        XCTAssertEqual(stops.filter(\.isJourneyEnd).map(\.crs), ["PAD"])
        XCTAssertEqual(Set(stops.map(\.id)).count, stops.count)
    }

    func testLateTrainShowsNewTimesAndOldOnes() throws {
        let d = try board().departures[1]
        let stops = TrainStops.list(d, station: "Reading", crs: "RDG")
        XCTAssertEqual(stops[0].time, "10:09")
        XCTAssertEqual(stops[0].oldTime, "10:05")
        XCTAssertEqual(stops[0].status, "4 min late")
        XCTAssertEqual(stops[1].time, "10:34")
        XCTAssertEqual(stops[1].state, .late(4))
        XCTAssertFalse(stops[1].isJourneyEnd, "No journey end chosen")
    }

    func testCancelledAndDelayed() throws {
        let b = try board()
        let cancelled = TrainStops.list(b.departures[2], station: "Reading", crs: "RDG")
        XCTAssertTrue(cancelled.allSatisfy(\.isCancelled))
        XCTAssertNil(cancelled[1].oldTime, "A cancelled stop doesn't cross out its own time")
        let delayed = TrainStops.list(b.departures[3], station: "Reading", crs: "RDG")
        XCTAssertEqual(delayed.map(\.status), ["Delayed", "Delayed"])
        XCTAssertEqual(delayed[1].time, "10:40", "No new time, so the timetable")
    }

    func testOneStopCancelledButTheTrainRuns() {
        let d = TrainDeparture(id: "x", scheduled: "12:00", expected: "On time", operatorName: "c2c", operatorCode: "CC",
                               destination: "Shoeburyness",
                               calls: [TrainCall(name: "Upminster", crs: "UPM", scheduled: "12:10", expected: "Cancelled", cancelled: true),
                                       TrainCall(name: "Grays", crs: "GRY", scheduled: "12:20", expected: "No report")])
        let stops = TrainStops.list(d, station: "", crs: "LST")
        XCTAssertEqual(stops[0].name, "London Liverpool Street", "Name looked up from the code when the board had none")
        XCTAssertEqual(stops.map(\.status), ["On time", "Cancelled", "No report"])
    }

    func testStatesFromTheFeedsWords() {
        XCTAssertEqual(TrainStops.state(scheduled: "10:00", reported: nil, cancelled: false), .onTime)
        XCTAssertEqual(TrainStops.state(scheduled: "10:00", reported: "On time", cancelled: false), .onTime)
        XCTAssertEqual(TrainStops.state(scheduled: "10:00", reported: "09:59", cancelled: false), .onTime, "Early counts as on time")
        XCTAssertEqual(TrainStops.state(scheduled: "23:58", reported: "00:03", cancelled: false), .late(5), "Past midnight")
        XCTAssertEqual(TrainStops.state(scheduled: "10:00", reported: "10:00", cancelled: true), .cancelled)
        XCTAssertEqual(TrainStops.state(scheduled: "10:00", reported: "Delayed", cancelled: false), .delayed)
    }

    /// The fuller reply for one train (Service Details), as it looks from Romford: it has been to Shenfield and
    /// Brentwood already.
    static let service = ##"""
    {
      "locationName": "Romford", "crs": "RMF", "std": "12:34", "etd": "12:36", "platform": "2",
      "operator": "Greater Anglia", "operatorCode": "LE", "length": "12", "isCancelled": false,
      "delayReason": "This train has been delayed by a fault with the signalling system",
      "previousCallingPoints": [{"callingPoint": [
        {"locationName": "Colchester", "crs": "COL", "st": "11:50", "at": "On time"},
        {"locationName": "Shenfield", "crs": "SNF", "st": "12:22", "at": "12:24"},
        {"locationName": "Brentwood", "crs": "BRE", "st": "12:26", "et": "12:28"}]}],
      "subsequentCallingPoints": [{"callingPoint": [
        {"locationName": "Stratford", "crs": "SRA", "st": "12:44", "et": "12:46"},
        {"locationName": "London Liverpool Street", "crs": "LST", "st": "12:52", "et": "12:53"}]}]
    }
    """##

    func testReadsOneTrainsFullRun() throws {
        let d = try Trains.parseService(Data(Self.service.utf8), id: "abc")
        XCTAssertEqual(d.id, "abc")
        XCTAssertEqual(d.destination, "London Liverpool Street", "The service reply has no destination list: the last stop is it")
        XCTAssertEqual(d.reason, "This train has been delayed by a fault with the signalling system")
        XCTAssertEqual(d.length, 12)
        let stops = TrainStops.list(d, station: "Romford", crs: "RMF", to: "LST")
        XCTAssertEqual(stops.map(\.crs), ["COL", "SNF", "BRE", "RMF", "SRA", "LST"])
        XCTAssertEqual(stops.map(\.place), [.before, .before, .before, .here, .after, .after])
        XCTAssertEqual(stops[0].status, "Left on time")
        XCTAssertEqual(stops[1].status, "Left 2 min late")
        XCTAssertEqual(stops[1].time, "12:24")
        XCTAssertFalse(stops[2].been)
        XCTAssertEqual(TrainStops.lastSeen(stops)?.name, "Shenfield")
        XCTAssertEqual(stops[3].platform, "2")
        XCTAssertTrue(stops[5].isJourneyEnd)
        XCTAssertEqual(TrainStops.summary(d, to: "LST"), "Calls at 2 stations · gets to London Liverpool Street at 12:53 · 17 min · 12 carriages")
    }

    func testBoardStopsDontPretendToHaveBeen() throws {
        // A board only lists the stops still to come, so none of them has been yet.
        let d = try board().departures[0]
        XCTAssertTrue(d.previous.isEmpty)
        XCTAssertNil(TrainStops.lastSeen(TrainStops.list(d, station: "Reading", crs: "RDG")))
    }

    func testServiceAddressCarriesOnlyTheTrainsId() {
        let url = Trains.serviceURL(id: "1234RMF/+x==")
        XCTAssertEqual(url?.host, "api1.raildata.org.uk")
        XCTAssertTrue(url?.absoluteString.hasSuffix("/GetServiceDetails/1234RMF%2F%2Bx%3D%3D") ?? false, url?.absoluteString ?? "")
        XCTAssertNil(Trains.serviceURL(id: ""))
        XCTAssertThrowsError(try Trains.parseService(Data("{}".utf8), id: "x"))
    }

    func testSummaryOnTheBoard() throws {
        let d = try board().departures[0]
        XCTAssertEqual(TrainStops.summary(d, to: "PAD"), "Calls at 5 stations · gets to London Paddington at 10:55 · 53 min · 9 carriages")
        XCTAssertEqual(TrainStops.summary(d), "Calls at 5 stations · gets to Abbey Wood at 11:25 · 1 h 23 min · 9 carriages")
    }
}
