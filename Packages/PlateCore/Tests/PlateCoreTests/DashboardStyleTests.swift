import XCTest
@testable import PlateCore

final class DashboardStyleTests: XCTestCase {
    // MARK: Colours

    func testHexRoundTrips() {
        XCTAssertEqual(RGB(hex: "#FF8000")?.hex, "#FF8000")
        XCTAssertEqual(RGB(hex: "ff8000")?.hex, "#FF8000")
        XCTAssertEqual(RGB(hex: "#abc")?.hex, "#AABBCC")
        XCTAssertEqual(RGB(hex: " #000000 ")?.hex, "#000000")
        XCTAssertNil(RGB(hex: "#GGGGGG"))
        XCTAssertNil(RGB(hex: "12345"))
        XCTAssertNil(RGB(hex: ""))
    }

    func testColourSavesAsHexText() throws {
        let data = try JSONEncoder().encode(["c": RGB(hex: "#102030")!])
        XCTAssertEqual(String(data: data, encoding: .utf8), ##"{"c":"#102030"}"##)
        XCTAssertEqual(try JSONDecoder().decode([String: RGB].self, from: data)["c"]?.hex, "#102030")
    }

    func testOutOfRangeColoursAreClamped() {
        XCTAssertEqual(RGB(2, -1, 0.5).hex, "#FF0080")
    }

    func testHueRoundTrips() {
        for hex in ["#FF0000", "#00FF00", "#0000FF", "#FFD60A", "#7AA2F7", "#333333", "#FFFFFF", "#000000"] {
            let c = RGB(hex: hex)!
            let h = c.hsb
            XCTAssertEqual(RGB(hue: h.hue, saturation: h.saturation, brightness: h.brightness).hex, hex)
        }
        XCTAssertEqual(RGB(hue: 0, saturation: 1, brightness: 1).hex, "#FF0000")
        XCTAssertEqual(RGB(hue: 1.0 / 3, saturation: 1, brightness: 1).hex, "#00FF00")
        XCTAssertEqual(RGB(hue: 1, saturation: 1, brightness: 1).hex, "#FF0000", "A full turn is red again")
    }

    func testTextColourIsReadable() {
        XCTAssertTrue(RGB.white.wantsDarkText)
        XCTAssertFalse(RGB.black.wantsDarkText)
        XCTAssertTrue(RGB(hex: "#FFD60A")!.wantsDarkText, "Yellow needs black text")
        XCTAssertFalse(RGB(hex: "#03045E")!.wantsDarkText, "Navy needs white text")
        XCTAssertEqual(RGB.black.contrast(with: .white), 21, accuracy: 0.01)
        // Whichever text colour is chosen always meets the 4.5:1 accessibility ratio.
        for i in 0..<200 {
            let c = RGB(hue: Double(i) / 200, saturation: Double(i % 7) / 6, brightness: Double(i % 11) / 10)
            XCTAssertGreaterThanOrEqual(c.contrast(with: c.wantsDarkText ? .black : .white), 4.5, c.hex)
        }
    }

    func testMixing() {
        XCTAssertEqual(RGB.black.mixed(with: .white, 0.5).hex, "#808080")
        XCTAssertEqual(RGB.black.mixed(with: .white, 2).hex, "#FFFFFF")
    }

    // MARK: Style

    func testOldDashboardGetsTheDefaultLook() throws {
        let d = try JSONDecoder().decode(HomeDashboard.self, from: Data(#"{"tiles":[]}"#.utf8))
        XCTAssertEqual(d.style, DashboardStyle())
        XCTAssertTrue(d.pages.isEmpty)
        XCTAssertTrue(d.timers.isEmpty)
    }

    func testStyleRoundTripsAndSurvivesUnknownValues() throws {
        var s = ThemePreset.all.first { $0.id == "ocean" }!.style
        s.backgroundPhotoId = "ABC/L0/001"
        s.tileColor = RGB(hex: "#123456")
        XCTAssertEqual(try JSONDecoder().decode(DashboardStyle.self, from: JSONEncoder().encode(s)), s)

        let json = ##"{"accent":"#FF0000","background":"hologram","tileLook":"glass","cornerRadius":"round","sounds":{"pack":"kazoo","volume":0.2}}"##
        let odd = try JSONDecoder().decode(DashboardStyle.self, from: Data(json.utf8))
        XCTAssertEqual(odd.accent.hex, "#FF0000")
        XCTAssertEqual(odd.background, .system, "A background this version doesn't know falls back to plain")
        XCTAssertEqual(odd.tileLook, .glass)
        XCTAssertEqual(odd.cornerRadius, 22)
        XCTAssertEqual(odd.sounds.pack, .soft)
        XCTAssertEqual(odd.sounds.volume, 0.2)
    }

    func testClamping() {
        var s = DashboardStyle()
        s.cornerRadius = 500; s.spacing = 0; s.tileOpacity = 0; s.backgroundDim = 3; s.sounds.volume = -1
        let c = s.clamped
        XCTAssertEqual(c.cornerRadius, 40)
        XCTAssertEqual(c.spacing, 6)
        XCTAssertEqual(c.tileOpacity, 0.2)
        XCTAssertEqual(c.backgroundDim, 0.9)
        XCTAssertEqual(c.sounds.volume, 0)
    }

    func testPresetsAreDistinctAndReadable() {
        XCTAssertEqual(Set(ThemePreset.all.map(\.id)).count, ThemePreset.all.count)
        XCTAssertEqual(ThemePreset.all.first?.style, DashboardStyle(), "Classic is the default look")
        for p in ThemePreset.all {
            XCTAssertEqual(p.style, p.style.clamped, p.name)
            // A lit tile's text must be readable on the "on" colour.
            let on = p.style.onColor
            XCTAssertGreaterThanOrEqual(on.contrast(with: on.wantsDarkText ? .black : .white), 4.5, p.name)
        }
    }

    func testApplyingAPresetKeepsYourPhotoAndVolume() {
        var mine = DashboardStyle()
        mine.backgroundPhotoId = "photo-1"; mine.sounds.volume = 0.15; mine.sounds.haptics = false; mine.showGreeting = false
        let s = ThemePreset.all.first { $0.id == "terminal" }!.applied(to: mine)
        XCTAssertEqual(s.backgroundPhotoId, "photo-1")
        XCTAssertEqual(s.sounds.volume, 0.15)
        XCTAssertFalse(s.sounds.haptics)
        XCTAssertFalse(s.showGreeting)
        XCTAssertEqual(s.sounds.pack, .retro)
        XCTAssertEqual(s.font, .mono)
    }

    func testTileTextFollowsWhatIsBehindIt() {
        var s = DashboardStyle()
        XCTAssertNil(s.tileTextIsDark(fill: nil), "Default look follows the device's light or dark mode")
        XCTAssertEqual(s.tileTextIsDark(fill: RGB(hex: "#FFD60A")), true, "Lit yellow tile: dark text")
        s.tileColor = RGB(hex: "#101010")
        XCTAssertEqual(s.tileTextIsDark(fill: nil), false)
        s = ThemePreset.all.first { $0.id == "midnight" }!.style
        XCTAssertEqual(s.backgroundIsDark, true)
        XCTAssertEqual(s.tileTextIsDark(fill: nil), false, "Glass over a dark gradient: light text")
        s = ThemePreset.all.first { $0.id == "candy" }!.style
        XCTAssertEqual(s.tileTextIsDark(fill: nil), true)
        s = DashboardStyle(background: .photo, tileLook: .outline)
        XCTAssertEqual(s.tileTextIsDark(fill: nil), false, "Photos are dimmed, so text over them is light")
    }

    func testDensityChangesHowManyTilesFit() {
        let w = 820.0
        XCTAssertGreaterThan(DashboardGrid.columns(forWidth: w, minTile: TileDensity.compact.minTile),
                             DashboardGrid.columns(forWidth: w, minTile: TileDensity.regular.minTile))
        XCTAssertGreaterThan(DashboardGrid.columns(forWidth: w, minTile: TileDensity.regular.minTile),
                             DashboardGrid.columns(forWidth: w, minTile: TileDensity.roomy.minTile))
    }

    // MARK: Sounds

    func testSilentPackMakesNoSound() {
        for e in SoundEvent.allCases { XCTAssertNil(SoundPack.off.recipe(for: e)) }
    }

    func testEveryPackHasEverySoundAndNeverClips() {
        for pack in SoundPack.allCases where pack != .off {
            for event in SoundEvent.allCases {
                let recipe = pack.recipe(for: event)
                XCTAssertNotNil(recipe, "\(pack) \(event)")
                let samples = ToneSynth.render(recipe!, sampleRate: 8000)
                XCTAssertFalse(samples.isEmpty)
                XCTAssertLessThanOrEqual(samples.map { abs($0) }.max()!, 0.9001, "\(pack) \(event)")
                XCTAssertGreaterThan(samples.map { abs($0) }.max()!, 0.05, "\(pack) \(event) is audible")
                XCTAssertEqual(abs(samples.last!), 0, accuracy: 0.05, "\(pack) \(event) ends quietly, with no click")
                XCTAssertEqual(abs(samples.first!), 0, accuracy: 0.05, "\(pack) \(event) starts quietly")
                XCTAssertLessThan(recipe!.length, 3, "Short enough for a system sound")
            }
        }
    }

    func testOnRisesAndOffFalls() {
        for pack in SoundPack.allCases where pack != .off {
            let on = pack.recipe(for: .on)!.tones, off = pack.recipe(for: .off)!.tones
            XCTAssertLessThan(on.first!.frequency, on.last!.frequency, "\(pack)")
            XCTAssertGreaterThan(off.first!.frequency, off.last!.frequency, "\(pack)")
        }
    }

    func testVolumeScalesTheSound() {
        let r = SoundPack.soft.recipe(for: .scene)!
        let loud = ToneSynth.render(r, sampleRate: 8000, volume: 1).map { abs($0) }.max()!
        let quiet = ToneSynth.render(r, sampleRate: 8000, volume: 0.25).map { abs($0) }.max()!
        XCTAssertEqual(quiet, loud * 0.25, accuracy: 0.001)
        XCTAssertEqual(ToneSynth.render(r, sampleRate: 8000, volume: 0).map { abs($0) }.max()!, 0)
    }

    func testWavFile() {
        let samples: [Float] = [0, 0.5, -0.5, 1, -1, 2]
        let d = ToneSynth.wav(samples, sampleRate: 8000)
        XCTAssertEqual(d.count, 44 + samples.count * 2)
        XCTAssertEqual(String(decoding: d.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: d[8..<12], as: UTF8.self), "WAVE")
        func u32(_ at: Int) -> UInt32 { d[at..<(at + 4)].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) } }
        func i16(_ at: Int) -> Int16 { Int16(bitPattern: UInt16(d[at]) | UInt16(d[at + 1]) << 8) }
        XCTAssertEqual(u32(4), UInt32(d.count - 8))
        XCTAssertEqual(u32(24), 8000)
        XCTAssertEqual(u32(40), UInt32(samples.count * 2))
        XCTAssertEqual(i16(44), 0)
        XCTAssertEqual(i16(50), 32767)
        XCTAssertEqual(i16(52), -32767)
        XCTAssertEqual(i16(54), 32767, "Anything over full volume is held at full volume")
    }
}
