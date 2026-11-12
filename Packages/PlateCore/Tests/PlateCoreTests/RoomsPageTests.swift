import Foundation
import XCTest
@testable import PlateCore

final class RoomsPageTests: XCTestCase {
    let flat = [RoomsPage.Room(id: "k", name: "Kitchen"), RoomsPage.Room(id: "b", name: "Bedroom"), RoomsPage.Room(id: "l", name: "Living room")]

    func testEveryRoomByNameWhenNoneChosen() {
        XCTAssertEqual(RoomsPage.columns(chosen: [], available: flat).map(\.name), ["Bedroom", "Kitchen", "Living room"])
    }

    func testChosenRoomsKeepTheirOrderAndSkipGoneOnes() {
        XCTAssertEqual(RoomsPage.columns(chosen: ["l", "gone", "k", "l"], available: flat).map(\.id), ["l", "k"])
        // Only rooms that have gone: show them all rather than an empty page.
        XCTAssertEqual(RoomsPage.columns(chosen: ["gone"], available: flat).count, 3)
    }

    func testTickingAndUntickingRooms() {
        var chosen = RoomsPage.toggle("k", chosen: [], available: flat)
        XCTAssertEqual(chosen, ["b", "l"])
        chosen = RoomsPage.toggle("k", chosen: chosen, available: flat)
        XCTAssertEqual(chosen, ["b", "l", "k"])
        // The last room stays.
        XCTAssertEqual(RoomsPage.toggle("b", chosen: ["b"], available: flat), ["b"])
    }

    func testMovingARoomLeftAndRight() {
        XCTAssertEqual(RoomsPage.move("k", by: -1, chosen: [], available: flat), ["k", "b", "l"])
        XCTAssertEqual(RoomsPage.move("l", by: 1, chosen: ["b", "k", "l"], available: flat), ["b", "k", "l"])
    }

    func testLightsComeFirstAndSensorsLast() {
        let things = [
            AccessorySummary(id: "1", name: "Motion", category: .sensor),
            AccessorySummary(id: "2", name: "Thermostat", category: .thermostat),
            AccessorySummary(id: "3", name: "Lamp", category: .light),
            AccessorySummary(id: "4", name: "Ceiling", category: .light),
            AccessorySummary(id: "5", name: "Kettle", category: .outlet),
        ]
        XCTAssertEqual(RoomsPage.sorted(things).map(\.name), ["Ceiling", "Lamp", "Kettle", "Thermostat", "Motion"])
    }

    func testColumnsStackOnANarrowScreen() {
        XCTAssertTrue(RoomsPage.sideBySide(width: 1100, rooms: 3))
        XCTAssertFalse(RoomsPage.sideBySide(width: 390, rooms: 3))
        XCTAssertTrue(RoomsPage.sideBySide(width: 390, rooms: 1))
    }

    func testRoomsPagesAreSavedAndOldPagesAreTilePages() throws {
        var d = HomeDashboard()
        let id = d.addPage(named: "Rooms", icon: "house", layout: .rooms)
        d.updatePage(id) { $0.rooms = ["l", "k"] }
        let back = try JSONDecoder().decode(HomeDashboard.self, from: JSONEncoder().encode(d))
        let page = try XCTUnwrap(back.pages.first { $0.id == id })
        XCTAssertEqual(page.layout, .rooms)
        XCTAssertEqual(page.rooms, ["l", "k"])

        let old = try JSONDecoder().decode(DashboardPage.self, from: Data(#"{"id":"\#(UUID().uuidString)","name":"Old"}"#.utf8))
        XCTAssertEqual(old.layout, .tiles)
        XCTAssertEqual(old.rooms, [])
    }

    func testChangingTheBuiltInPageSavesIt() {
        var d = HomeDashboard()
        d.updatePage(HomeDashboard.firstPageId) { $0.layout = .rooms }
        XCTAssertEqual(d.pageList.first?.layout, .rooms)
    }
}
