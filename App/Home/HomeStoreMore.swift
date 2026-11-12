import HomeKit
import Observation
import PlateCore
import SwiftUI

// More of what the dashboard does with HomeKit: colours and positions, whole-home summaries, sensors, batteries,
// cameras and light shows.

extension HomeStore {
    // MARK: Whole home

    var lights: [HMAccessory] {
        (home?.accessories ?? []).filter { Self.category(of: $0) == .light }
    }

    /// Lights that can change colour.
    var colourLights: [HMAccessory] {
        lights.filter { Self.characteristic(HMCharacteristicTypeHue, in: $0) != nil }
    }

    /// How many lights are on, or nil before HomeKit has loaded.
    var lightsOnCount: Int? {
        _ = revision
        guard status == .ready else { return nil }
        return lights.filter { (Self.characteristic(HMCharacteristicTypePowerState, in: $0)?.value as? NSNumber)?.boolValue == true }.count
    }

    func allLightsOff() async {
        let on = lights.filter { (Self.characteristic(HMCharacteristicTypePowerState, in: $0)?.value as? NSNumber)?.boolValue == true }
        Feedback.shared.play(.off)
        onActivity?(on.isEmpty ? "All lights already off" : "Turned off \(on.count) light\(on.count == 1 ? "" : "s")", "lightbulb.slash.fill")
        for a in on { await set(a, on: false, quiet: true) }
    }

    /// Switches an accessory to a particular state (routines and typed commands use this; a tap uses `toggle`).
    func set(_ a: HMAccessory, on: Bool, quiet: Bool = false) async {
        let s = state(of: a)
        guard let isOn = s.isOn else { return }
        // Locks count "locked" as on, blinds "open" as on, so the same call works for all of them.
        if isOn == on { return }
        if quiet {
            do {
                if let c = Self.characteristic(HMCharacteristicTypePowerState, in: a) { try await write(c, on) }
                else if let c = Self.characteristic(HMCharacteristicTypeActive, in: a) { try await write(c, on ? 1 : 0) }
            } catch { report(error, doing: "switch \(a.name)", reachable: a.isReachable) }
        } else {
            await toggle(a)
        }
    }

    func set(_ room: HMRoom, on: Bool) async {
        if isOn(room) != on { await toggle(room) }
        else if on {
            // Some are on already: make sure they all are.
            for c in switchables(in: room) where (c.value as? NSNumber)?.boolValue != true { try? await write(c, true) }
        }
    }

    // MARK: Colour, warmth and position

    struct LightDetail {
        var brightness: Int?
        var hue: Double?
        var saturation: Double?
        /// Colour temperature in mireds, with the range the bulb allows.
        var mired: Int?
        var miredRange: ClosedRange<Double>?
    }

    func detail(of a: HMAccessory) -> LightDetail {
        _ = revision
        func num(_ type: String) -> NSNumber? { Self.characteristic(type, in: a)?.value as? NSNumber }
        var d = LightDetail(brightness: num(HMCharacteristicTypeBrightness)?.intValue, hue: num(HMCharacteristicTypeHue)?.doubleValue,
                            saturation: num(HMCharacteristicTypeSaturation)?.doubleValue, mired: num(HMCharacteristicTypeColorTemperature)?.intValue)
        if let m = Self.characteristic(HMCharacteristicTypeColorTemperature, in: a)?.metadata,
           let lo = m.minimumValue?.doubleValue, let hi = m.maximumValue?.doubleValue, lo < hi {
            d.miredRange = lo...hi
        }
        return d
    }

    func has(_ type: String, _ a: HMAccessory) -> Bool { Self.characteristic(type, in: a) != nil }

    /// Sets a light's colour: hue in degrees, saturation in percent.
    func setColour(_ a: HMAccessory, hue: Double, saturation: Double, brightness: Double? = nil, quiet: Bool = false) async {
        do {
            if let p = Self.characteristic(HMCharacteristicTypePowerState, in: a), (p.value as? NSNumber)?.boolValue != true {
                try await write(p, true)
            }
            if let c = Self.characteristic(HMCharacteristicTypeHue, in: a) { try await write(c, hue) }
            if let c = Self.characteristic(HMCharacteristicTypeSaturation, in: a) { try await write(c, saturation) }
            if let brightness, let c = Self.characteristic(HMCharacteristicTypeBrightness, in: a) { try await write(c, Int(brightness)) }
        } catch {
            if !quiet { report(error, doing: "change the colour of \(a.name)", reachable: a.isReachable) }
        }
    }

    func setWarmth(_ a: HMAccessory, kelvin: Double) async {
        guard let c = Self.characteristic(HMCharacteristicTypeColorTemperature, in: a) else { return }
        let lo = c.metadata?.minimumValue?.doubleValue ?? 140, hi = c.metadata?.maximumValue?.doubleValue ?? 500
        do {
            if let p = Self.characteristic(HMCharacteristicTypePowerState, in: a), (p.value as? NSNumber)?.boolValue != true {
                try await write(p, true)
            }
            try await write(c, LightColor.mired(kelvin: kelvin, min: lo, max: hi))
        } catch { report(error, doing: "change \(a.name)", reachable: a.isReachable) }
    }

    /// Opens blinds to a percentage.
    func setPosition(_ a: HMAccessory, to percent: Int) async {
        guard let c = Self.characteristic(HMCharacteristicTypeTargetPosition, in: a) else { return }
        do { try await write(c, percent) } catch { report(error, doing: "move \(a.name)", reachable: a.isReachable) }
    }

    func setTargetTemperature(_ a: HMAccessory, to value: Double) async {
        guard let c = Self.characteristic(HMCharacteristicTypeTargetTemperature, in: a) else { return }
        do { try await write(c, value) } catch { report(error, doing: "change \(a.name)", reachable: a.isReachable) }
    }

    // MARK: Sensors and batteries

    struct Reading: Identifiable {
        var id: String
        var name: String
        var room: String?
        var temperature: Double?
        var humidity: Int?
    }

    /// Every accessory that reports a temperature or humidity, by room.
    var readings: [Reading] {
        _ = revision
        return (home?.accessories ?? []).compactMap { a in
            let t = (Self.characteristic(HMCharacteristicTypeCurrentTemperature, in: a)?.value as? NSNumber)?.doubleValue
            let h = (Self.characteristic(HMCharacteristicTypeCurrentRelativeHumidity, in: a)?.value as? NSNumber)?.intValue
            guard t != nil || h != nil else { return nil }
            return Reading(id: a.uniqueIdentifier.uuidString, name: a.name, room: a.room?.name, temperature: t, humidity: h)
        }
        .sorted { ($0.room ?? $0.name) < ($1.room ?? $1.name) }
    }

    /// The average temperature indoors, if anything measures it.
    var insideTemperature: Double? {
        let t = readings.compactMap(\.temperature)
        return t.isEmpty ? nil : t.reduce(0, +) / Double(t.count)
    }

    struct Battery: Identifiable {
        var id: String
        var name: String
        var level: Int?
    }

    /// Accessories saying their battery is low (or under 20%).
    var lowBatteries: [Battery] {
        _ = revision
        return (home?.accessories ?? []).compactMap { a in
            let low = (Self.characteristic(HMCharacteristicTypeStatusLowBattery, in: a)?.value as? NSNumber)?.intValue == 1
            let level = (Self.characteristic(HMCharacteristicTypeBatteryLevel, in: a)?.value as? NSNumber)?.intValue
            guard low || (level ?? 100) < 20 else { return nil }
            return Battery(id: a.uniqueIdentifier.uuidString, name: a.name, level: level)
        }
    }

    var cameras: [HMAccessory] {
        (home?.accessories ?? []).filter { !($0.cameraProfiles ?? []).isEmpty }.sorted { $0.name < $1.name }
    }
}

/// One camera's picture: a snapshot that can be refreshed, or live video.
@MainActor
@Observable
final class CameraFeed: NSObject {
    var source: HMCameraSource?
    var isLive = false
    var problem: String?
    @ObservationIgnored private var profile: HMCameraProfile?

    func attach(_ accessory: HMAccessory?) {
        let p = accessory?.cameraProfiles?.first
        guard p !== profile else { return }
        profile = p
        p?.snapshotControl?.delegate = self
        p?.streamControl?.delegate = self
        source = p?.snapshotControl?.mostRecentSnapshot
    }

    func snapshot() {
        guard !isLive else { return }
        profile?.snapshotControl?.takeSnapshot()
    }

    func startLive() {
        guard let stream = profile?.streamControl else { return }
        stream.startStream()
    }

    func stopLive() {
        profile?.streamControl?.stopStream()
        isLive = false
        source = profile?.snapshotControl?.mostRecentSnapshot
        snapshot()
    }
}

extension CameraFeed: HMCameraSnapshotControlDelegate, HMCameraStreamControlDelegate {
    nonisolated func cameraSnapshotControl(_ control: HMCameraSnapshotControl, didTake snapshot: HMCameraSnapshot?, error: Error?) {
        Task { @MainActor in
            if let snapshot, !self.isLive { self.source = snapshot; self.problem = nil }
            else if let error, self.source == nil { self.problem = error.localizedDescription }
        }
    }

    nonisolated func cameraStreamControlDidStartStream(_ control: HMCameraStreamControl) {
        Task { @MainActor in
            self.isLive = true
            self.source = control.cameraStream
        }
    }

    nonisolated func cameraStreamControl(_ control: HMCameraStreamControl, didStopStreamWithError error: Error?) {
        Task { @MainActor in
            self.isLive = false
            if let error { self.problem = "The live view stopped: \(error.localizedDescription)" }
        }
    }
}

struct CameraSourceView: UIViewRepresentable {
    let source: HMCameraSource?
    func makeUIView(context: Context) -> HMCameraView { HMCameraView() }
    func updateUIView(_ view: HMCameraView, context: Context) { view.cameraSource = source }
}

/// Runs a light show: changes the colour lights every couple of seconds until stopped, then puts them back.
@MainActor
@Observable
final class LightShowRunner {
    private(set) var active: LightShow?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var before: [(HMAccessory, hue: Double?, saturation: Double?, brightness: Int?, on: Bool)] = []

    func start(_ show: LightShow, home: HomeStore) {
        let lights = home.colourLights.filter(\.isReachable)
        guard !lights.isEmpty else {
            home.problem = "A light show needs at least one colour light that's switched on at the wall."
            Feedback.shared.play(.error)
            return
        }
        let wasRunning = active != nil
        task?.cancel()
        if !wasRunning {
            before = lights.map { a in
                let d = home.detail(of: a)
                return (a, d.hue, d.saturation, d.brightness, home.state(of: a).isOn == true)
            }
        }
        active = show
        home.onActivity?("\(show.title) light show started", show.icon)
        task = Task {
            var step = 0
            while !Task.isCancelled {
                for (i, a) in lights.enumerated() {
                    let c = show.color(step: step, light: i, of: lights.count)
                    await home.setColour(a, hue: c.hue, saturation: c.saturation, brightness: c.brightness, quiet: true)
                }
                step += 1
                try? await Task.sleep(for: .seconds(show.interval))
            }
        }
    }

    func stop(home: HomeStore) {
        guard active != nil else { return }
        task?.cancel()
        task = nil
        active = nil
        let saved = before
        before = []
        Task {
            for (a, hue, saturation, brightness, on) in saved {
                if let hue, let saturation {
                    await home.setColour(a, hue: hue, saturation: saturation, brightness: brightness.map(Double.init), quiet: true)
                }
                if !on { await home.set(a, on: false, quiet: true) }
            }
        }
    }
}
