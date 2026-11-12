import XCTest
@testable import PlateCore

final class CommandTests: XCTestCase {
    private typealias N = CommandNames.Named
    private let names = CommandNames(
        accessories: [N(id: "a1", name: "Lamp", room: "Bedroom"), N(id: "a2", name: "Lamp", room: "Living Room"),
                      N(id: "a3", name: "Ceiling Light", room: "Kitchen"), N(id: "a4", name: "Front Door", room: "Hall"),
                      N(id: "a5", name: "Ethan's Desk", room: "Bedroom"), N(id: "a6", name: "Blind", room: "Bedroom")],
        rooms: [N(id: "r1", name: "Bedroom"), N(id: "r2", name: "Living Room"), N(id: "r3", name: "Kitchen"), N(id: "r4", name: "Hall")],
        scenes: [N(id: "s1", name: "Good Night"), N(id: "s2", name: "Relax"), N(id: "s3", name: "Party")],
        routines: [N(id: "x1", name: "Movie night")],
        music: [N(id: "m1", name: "Blue"), N(id: "m2", name: "Salt and Pepper"), N(id: "m3", name: "The Dark Side of the Moon")])

    private func run(_ s: String) -> [CommandAction] { CommandParser.parse(s, names: names).actions }

    func testRoomsOnAndOff() {
        XCTAssertEqual(run("kitchen off"), [.room(id: "r3", on: false)])
        XCTAssertEqual(run("Turn the living room on, please"), [.room(id: "r2", on: true)])
        XCTAssertEqual(run("living room lights off"), [.room(id: "r2", on: false)])
        XCTAssertEqual(run("Kitchen 40%"), [.roomBrightness(id: "r3", percent: 40)])
        XCTAssertEqual(CommandParser.parse("kitchen off", names: names).reply, "Kitchen off")
    }

    func testAccessories() {
        XCTAssertEqual(run("ceiling light on"), [.accessory(id: "a3", on: true)])
        XCTAssertEqual(run("turn off the ceiling light"), [.accessory(id: "a3", on: false)])
        XCTAssertEqual(run("ceiling light"), [.accessory(id: "a3", on: nil)], "No on or off means switch it")
        XCTAssertEqual(run("ethans desk on"), [.accessory(id: "a5", on: true)], "Apostrophes don't matter")
        XCTAssertEqual(run("Ethan's desk off"), [.accessory(id: "a5", on: false)])
    }

    func testTheRoomPicksBetweenTwoLampsWithTheSameName() {
        XCTAssertEqual(run("bedroom lamp off"), [.accessory(id: "a1", on: false)])
        XCTAssertEqual(run("lamp in the living room on"), [.accessory(id: "a2", on: true)])
    }

    func testBrightness() {
        XCTAssertEqual(run("ceiling light 30%"), [.brightness(id: "a3", percent: 30)])
        XCTAssertEqual(run("set ceiling light to 70 percent"), [.brightness(id: "a3", percent: 70)])
        XCTAssertEqual(run("ceiling light 45"), [.brightness(id: "a3", percent: 45)])
        XCTAssertEqual(run("dim the ceiling light"), [.brightness(id: "a3", percent: 25)])
        XCTAssertEqual(run("ceiling light full"), [.brightness(id: "a3", percent: 100)])
        XCTAssertEqual(run("ceiling light 0%"), [.accessory(id: "a3", on: false)])
        XCTAssertEqual(run("ceiling light 250%"), [.brightness(id: "a3", percent: 100)])
    }

    func testLocksAndBlinds() {
        XCTAssertEqual(run("lock the front door"), [.accessory(id: "a4", on: true)])
        XCTAssertEqual(run("unlock front door"), [.accessory(id: "a4", on: false)])
        XCTAssertEqual(CommandParser.parse("unlock front door", names: names).reply, "Front Door unlocked")
        XCTAssertEqual(run("open the blind"), [.accessory(id: "a6", on: true)])
        XCTAssertEqual(run("close blind"), [.accessory(id: "a6", on: false)])
    }

    func testEverythingOff() {
        XCTAssertEqual(run("everything off"), [.allLightsOff])
        XCTAssertEqual(run("all lights off"), [.allLightsOff])
        XCTAssertEqual(run("lights off"), [.allLightsOff])
    }

    func testScenesAndRoutines() {
        XCTAssertEqual(run("good night"), [.scene(id: "s1")])
        XCTAssertEqual(run("Run Relax"), [.scene(id: "s2")])
        XCTAssertEqual(run("movie night"), [.routine(id: "x1")])
        XCTAssertEqual(run("start movie night routine"), [.routine(id: "x1")])
        XCTAssertEqual(run("party"), [.scene(id: "s3")], "A scene called Party beats the party light show")
        XCTAssertEqual(run("let's do movie night"), [.routine(id: "x1")])
    }

    func testMusic() {
        XCTAssertEqual(run("play blue"), [.play(id: "m1")])
        XCTAssertEqual(run("play salt and pepper"), [.play(id: "m2")], "Names with “and” in them aren't split")
        XCTAssertEqual(run("play The Dark Side of the Moon"), [.play(id: "m3")])
        XCTAssertEqual(run("blue"), [.play(id: "m1")])
        XCTAssertEqual(run("pause"), [.pause])
        XCTAssertEqual(run("skip"), [.next])
        XCTAssertEqual(run("play"), [.resume])
        XCTAssertTrue(run("play something I haven't pinned").isEmpty)
    }

    func testTimers() {
        XCTAssertEqual(run("pasta 10 min"), [.timer(label: "Pasta", seconds: 600)])
        XCTAssertEqual(run("timer 5"), [.timer(label: "Timer", seconds: 300)])
        XCTAssertEqual(run("set a timer for 1h30"), [.timer(label: "Timer", seconds: 5400)])
        XCTAssertEqual(run("kitchen timer 3 min"), [.timer(label: "Kitchen", seconds: 180)], "A room name with a time is a timer's label")
    }

    func testLightShows() {
        XCTAssertEqual(run("disco"), [.lightShow(.party)])
        XCTAssertEqual(run("rainbow light show"), [.lightShow(.rainbow)])
        XCTAssertEqual(run("candlelight"), [.lightShow(.candle)])
        XCTAssertEqual(run("stop the light show"), [.stopLightShow])
        XCTAssertEqual(run("show artwork"), [.showArtwork])
    }

    func testSeveralAtOnce() {
        XCTAssertEqual(run("kitchen off, then play blue"), [.room(id: "r3", on: false), .play(id: "m1")])
        XCTAssertEqual(run("good night, pasta 10"), [.scene(id: "s1"), .timer(label: "Pasta", seconds: 600)])
        let r = CommandParser.parse("kitchen off, make me a sandwich", names: names)
        XCTAssertEqual(r.actions, [.room(id: "r3", on: false)])
        XCTAssertEqual(r.reply, "Kitchen off. I didn't understand “make me a sandwich”")
    }

    func testNonsenseAndEmpty() {
        XCTAssertFalse(CommandParser.parse("", names: names).understood)
        XCTAssertFalse(CommandParser.parse("   ", names: names).understood)
        XCTAssertFalse(CommandParser.parse("what is the meaning of life", names: names).understood)
        XCTAssertFalse(CommandParser.parse("kitchen", names: names).understood, "A room with nothing to do isn't guessed at")
        XCTAssertFalse(CommandParser.parse("lights off", names: CommandNames()).actions.isEmpty, "Works in an empty home too")
    }

    func testBriefing() {
        XCTAssertEqual(run("briefing"), [.briefing])
        XCTAssertEqual(run("what's on today"), [.briefing])
    }
}
