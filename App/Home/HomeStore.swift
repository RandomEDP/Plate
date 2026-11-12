import Foundation
import HomeKit
import Observation
import PlateCore

/// Plate's view of the flat through HomeKit: the home's rooms, accessories and scenes, what they're doing now, and
/// switching them. Devices are still added and automated in Apple's Home app; Plate only shows and controls them.
@MainActor
@Observable
final class HomeStore: NSObject {
    enum Status: Equatable {
        /// HomeKit hasn't been touched yet, so iOS hasn't asked for permission.
        case notStarted
        case loading
        case ready
        /// Permission was turned off in Settings → Privacy & Security → HomeKit.
        case denied
        /// HomeKit works but there's no home set up in the Home app yet.
        case noHome
    }

    var status: Status = .notStarted
    /// Bumped whenever HomeKit reports a change, so tiles redraw with the new state.
    private(set) var revision = 0
    /// The last thing that went wrong, shown briefly on the dashboard.
    var problem: String?

    private var manager: HMHomeManager?
    private var watched = Set<ObjectIdentifier>()

    /// Which home the dashboard shows, when there's more than one. Kept per device.
    var homeId: String? {
        didSet { UserDefaults.standard.set(homeId, forKey: "dashboardHomeId"); revision += 1 }
    }

    override init() {
        super.init()
        homeId = UserDefaults.standard.string(forKey: "dashboardHomeId")
        // Only start HomeKit (and so the permission prompt) straight away if it has been used before.
        if UserDefaults.standard.bool(forKey: "homeKitStarted") { start() }
    }

    /// Starts HomeKit. The first time, iOS asks "Allow Plate to access your Home data?".
    func start() {
        guard manager == nil else { return }
        UserDefaults.standard.set(true, forKey: "homeKitStarted")
        status = .loading
        let m = HMHomeManager()
        m.delegate = self
        manager = m
    }

    var homes: [HMHome] { manager?.homes ?? [] }

    var home: HMHome? {
        homes.first { $0.uniqueIdentifier.uuidString == homeId } ?? homes.first
    }

    // MARK: Looking things up

    func accessory(_ id: String?) -> HMAccessory? {
        guard let id else { return nil }
        return home?.accessories.first { $0.uniqueIdentifier.uuidString == id }
    }

    func scene(_ id: String?) -> HMActionSet? {
        guard let id else { return nil }
        return home?.actionSets.first { $0.uniqueIdentifier.uuidString == id }
    }

    func room(_ id: String?) -> HMRoom? {
        guard let id else { return nil }
        return home?.rooms.first { $0.uniqueIdentifier.uuidString == id }
    }

    /// Every id the dashboard can point at, to spot tiles for things removed in the Home app.
    var knownIds: Set<String> {
        guard let home else { return [] }
        return Set(home.accessories.map(\.uniqueIdentifier.uuidString)
            + home.actionSets.map(\.uniqueIdentifier.uuidString)
            + home.rooms.map(\.uniqueIdentifier.uuidString))
    }

    /// Scenes you'd tap from a wall: the ones you made, plus Apple's built-in ones that have something in them.
    var scenes: [HMActionSet] {
        (home?.actionSets ?? []).filter { !$0.actions.isEmpty }.sorted { $0.name < $1.name }
    }

    var rooms: [HMRoom] { (home?.rooms ?? []).sorted { $0.name < $1.name } }

    func accessories(in room: HMRoom) -> [HMAccessory] {
        room.accessories.sorted { $0.name < $1.name }
    }

    var summaries: [AccessorySummary] {
        (home?.accessories ?? []).map {
            AccessorySummary(id: $0.uniqueIdentifier.uuidString, name: $0.name, room: $0.room?.name, category: Self.category(of: $0))
        }
    }

    var sceneSummaries: [SceneSummary] {
        scenes.map { SceneSummary(id: $0.uniqueIdentifier.uuidString, name: $0.name) }
    }

    // MARK: What an accessory is doing

    struct State {
        var symbol: String
        /// nil when the accessory doesn't switch on and off (a sensor, a thermostat).
        var isOn: Bool?
        /// "70%", "21.5°", "Locked"…
        var detail: String?
        var reachable: Bool
    }

    static func category(of a: HMAccessory) -> AccessorySummary.Category {
        switch a.category.categoryType {
        case HMAccessoryCategoryTypeLightbulb: return .light
        case HMAccessoryCategoryTypeOutlet: return .outlet
        case HMAccessoryCategoryTypeSwitch, HMAccessoryCategoryTypeProgrammableSwitch: return .switchControl
        case HMAccessoryCategoryTypeFan, HMAccessoryCategoryTypeAirPurifier: return .fan
        case HMAccessoryCategoryTypeDoorLock: return .lock
        case HMAccessoryCategoryTypeThermostat, HMAccessoryCategoryTypeAirHeater, HMAccessoryCategoryTypeAirConditioner: return .thermostat
        case HMAccessoryCategoryTypeWindowCovering, HMAccessoryCategoryTypeWindow: return .blinds
        case HMAccessoryCategoryTypeSensor: return .sensor
        default:
            return characteristic(HMCharacteristicTypePowerState, in: a) != nil ? .switchControl : .other
        }
    }

    static func characteristic(_ type: String, in a: HMAccessory) -> HMCharacteristic? {
        for s in a.services { if let c = s.characteristics.first(where: { $0.characteristicType == type }) { return c } }
        return nil
    }

    func state(of a: HMAccessory) -> State {
        _ = revision
        let cat = Self.category(of: a)
        let power = Self.characteristic(HMCharacteristicTypePowerState, in: a)
        let on = (power?.value as? NSNumber)?.boolValue
        switch cat {
        case .light:
            let b = (Self.characteristic(HMCharacteristicTypeBrightness, in: a)?.value as? NSNumber)?.intValue
            return State(symbol: on == true ? "lightbulb.fill" : "lightbulb", isOn: on ?? false,
                         detail: on == true ? b.map { "\($0)%" } ?? "On" : "Off", reachable: a.isReachable)
        case .outlet:
            return State(symbol: on == true ? "poweroutlet.type.g.fill" : "poweroutlet.type.g", isOn: on ?? false,
                         detail: on == true ? "On" : "Off", reachable: a.isReachable)
        case .switchControl:
            return State(symbol: on == true ? "switch.2" : "switch.2", isOn: on ?? false, detail: on == true ? "On" : "Off",
                         reachable: a.isReachable)
        case .fan:
            let active = (Self.characteristic(HMCharacteristicTypeActive, in: a)?.value as? NSNumber)?.boolValue ?? on ?? false
            return State(symbol: active ? "fan.fill" : "fan", isOn: active, detail: active ? "On" : "Off", reachable: a.isReachable)
        case .lock:
            let current = (Self.characteristic(HMCharacteristicTypeCurrentLockMechanismState, in: a)?.value as? NSNumber)?.intValue
            let locked = current == 1
            let text = current == 1 ? "Locked" : current == 0 ? "Unlocked" : current == 2 ? "Jammed" : "Unknown"
            return State(symbol: locked ? "lock.fill" : "lock.open", isOn: locked, detail: text, reachable: a.isReachable)
        case .thermostat:
            let now = (Self.characteristic(HMCharacteristicTypeCurrentTemperature, in: a)?.value as? NSNumber)?.doubleValue
            let target = (Self.characteristic(HMCharacteristicTypeTargetTemperature, in: a)?.value as? NSNumber)?.doubleValue
            var text = now.map { Self.degrees($0) } ?? "–"
            if let target { text += " → \(Self.degrees(target))" }
            return State(symbol: "thermometer.medium", isOn: nil, detail: text, reachable: a.isReachable)
        case .blinds:
            let pos = (Self.characteristic(HMCharacteristicTypeCurrentPosition, in: a)?.value as? NSNumber)?.intValue
            let open = (pos ?? 0) > 0
            return State(symbol: open ? "blinds.horizontal.open" : "blinds.horizontal.closed", isOn: open,
                         detail: pos.map { $0 >= 100 ? "Open" : $0 == 0 ? "Closed" : "\($0)% open" }, reachable: a.isReachable)
        case .sensor, .other:
            if let t = (Self.characteristic(HMCharacteristicTypeCurrentTemperature, in: a)?.value as? NSNumber)?.doubleValue {
                return State(symbol: "thermometer.medium", isOn: nil, detail: Self.degrees(t), reachable: a.isReachable)
            }
            if let h = (Self.characteristic(HMCharacteristicTypeCurrentRelativeHumidity, in: a)?.value as? NSNumber)?.intValue {
                return State(symbol: "humidity", isOn: nil, detail: "\(h)%", reachable: a.isReachable)
            }
            if let m = (Self.characteristic(HMCharacteristicTypeMotionDetected, in: a)?.value as? NSNumber)?.boolValue {
                return State(symbol: m ? "figure.walk.motion" : "figure.stand", isOn: nil, detail: m ? "Movement" : "Still",
                             reachable: a.isReachable)
            }
            if let c = (Self.characteristic(HMCharacteristicTypeContactState, in: a)?.value as? NSNumber)?.intValue {
                return State(symbol: c == 0 ? "door.left.hand.closed" : "door.left.hand.open", isOn: nil,
                             detail: c == 0 ? "Closed" : "Open", reachable: a.isReachable)
            }
            return State(symbol: "house", isOn: on, detail: on.map { $0 ? "On" : "Off" }, reachable: a.isReachable)
        }
    }

    static func degrees(_ c: Double) -> String { String(format: "%.1f°", c) }

    /// Whether any light or switch in the room is on.
    func isOn(_ room: HMRoom) -> Bool {
        _ = revision
        return switchables(in: room).contains { ($0.value as? NSNumber)?.boolValue == true }
    }

    private func switchables(in room: HMRoom) -> [HMCharacteristic] {
        room.accessories.filter { [.light, .outlet, .switchControl].contains(Self.category(of: $0)) }
            .compactMap { Self.characteristic(HMCharacteristicTypePowerState, in: $0) }
    }

    // MARK: Doing things

    /// The tap on a tile: lights, plugs and fans on/off, locks locked/unlocked, blinds open/closed.
    func toggle(_ a: HMAccessory) async {
        let s = state(of: a)
        guard let on = s.isOn else { return }
        do {
            switch Self.category(of: a) {
            case .lock:
                guard let c = Self.characteristic(HMCharacteristicTypeTargetLockMechanismState, in: a) else { return }
                try await write(c, on ? 0 : 1)
            case .blinds:
                guard let c = Self.characteristic(HMCharacteristicTypeTargetPosition, in: a) else { return }
                try await write(c, on ? 0 : 100)
            case .fan:
                if let c = Self.characteristic(HMCharacteristicTypeActive, in: a) { try await write(c, on ? 0 : 1) }
                else if let c = Self.characteristic(HMCharacteristicTypePowerState, in: a) { try await write(c, !on) }
            default:
                guard let c = Self.characteristic(HMCharacteristicTypePowerState, in: a) else { return }
                try await write(c, !on)
            }
        } catch {
            report(error, doing: "switch \(a.name)", reachable: a.isReachable)
        }
    }

    func setBrightness(_ a: HMAccessory, to percent: Int) async {
        do {
            if let p = Self.characteristic(HMCharacteristicTypePowerState, in: a), (p.value as? NSNumber)?.boolValue != true {
                try await write(p, true)
            }
            if let c = Self.characteristic(HMCharacteristicTypeBrightness, in: a) { try await write(c, percent) }
        } catch {
            report(error, doing: "dim \(a.name)", reachable: a.isReachable)
        }
    }

    /// Nudges a thermostat's target temperature up or down by half a degree.
    func nudgeTemperature(_ a: HMAccessory, by delta: Double) async {
        guard let c = Self.characteristic(HMCharacteristicTypeTargetTemperature, in: a) else { return }
        let current = (c.value as? NSNumber)?.doubleValue ?? 20
        let lo = c.metadata?.minimumValue?.doubleValue ?? 10
        let hi = c.metadata?.maximumValue?.doubleValue ?? 30
        do { try await write(c, min(hi, max(lo, current + delta))) } catch {
            report(error, doing: "change \(a.name)", reachable: a.isReachable)
        }
    }

    /// Switches everything in a room off if anything is on, otherwise on.
    func toggle(_ room: HMRoom) async {
        let target = !isOn(room)
        for c in switchables(in: room) {
            do { try await write(c, target) } catch {
                report(error, doing: "switch \(c.service?.accessory?.name ?? room.name)", reachable: c.service?.accessory?.isReachable ?? true)
            }
        }
    }

    func run(_ scene: HMActionSet) async {
        guard let home else { return }
        do { try await home.executeActionSet(scene) } catch {
            report(error, doing: "run \(scene.name)", reachable: true)
        }
    }

    private func write(_ c: HMCharacteristic, _ value: Any) async throws {
        try await c.writeValue(value)
        revision += 1
    }

    private func report(_ error: Error, doing what: String, reachable: Bool) {
        problem = reachable
            ? "Couldn't \(what): \(error.localizedDescription)"
            : "Couldn't \(what) because it isn't responding. Check it has power and is on Wi-Fi, then try again."
        Task {
            try? await Task.sleep(for: .seconds(5))
            problem = nil
        }
    }

    /// Asks every accessory to report its state now and whenever it changes, so tiles stay current.
    private func watch(_ home: HMHome) {
        for a in home.accessories {
            a.delegate = self
            let types = [HMCharacteristicTypePowerState, HMCharacteristicTypeBrightness, HMCharacteristicTypeActive,
                         HMCharacteristicTypeCurrentLockMechanismState, HMCharacteristicTypeCurrentTemperature,
                         HMCharacteristicTypeTargetTemperature, HMCharacteristicTypeCurrentPosition,
                         HMCharacteristicTypeCurrentRelativeHumidity, HMCharacteristicTypeMotionDetected,
                         HMCharacteristicTypeContactState]
            for s in a.services {
                for c in s.characteristics where types.contains(c.characteristicType) {
                    let key = ObjectIdentifier(c)
                    if c.properties.contains(HMCharacteristicPropertySupportsEventNotification), !watched.contains(key) {
                        watched.insert(key)
                        c.enableNotification(true) { _ in }
                    }
                    c.readValue { [weak self] _ in Task { @MainActor in self?.revision += 1 } }
                }
            }
        }
    }

    fileprivate func homesChanged() {
        guard let manager else { return }
        if manager.authorizationStatus.contains(.determined), !manager.authorizationStatus.contains(.authorized) {
            status = .denied
            return
        }
        if manager.homes.isEmpty {
            status = .noHome
        } else {
            status = .ready
            if let home { home.delegate = self; watch(home) }
        }
        revision += 1
    }
}

extension HomeStore: HMHomeManagerDelegate, HMHomeDelegate, HMAccessoryDelegate {
    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in self.homesChanged() }
    }

    nonisolated func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        Task { @MainActor in self.homesChanged() }
    }

    nonisolated func homeManager(_ manager: HMHomeManager, didAdd home: HMHome) {
        Task { @MainActor in self.homesChanged() }
    }

    nonisolated func homeManager(_ manager: HMHomeManager, didRemove home: HMHome) {
        Task { @MainActor in self.homesChanged() }
    }

    nonisolated func home(_ home: HMHome, didAdd accessory: HMAccessory) {
        Task { @MainActor in self.homesChanged() }
    }

    nonisolated func home(_ home: HMHome, didRemove accessory: HMAccessory) {
        Task { @MainActor in self.homesChanged() }
    }

    nonisolated func home(_ home: HMHome, didAdd actionSet: HMActionSet) {
        Task { @MainActor in self.homesChanged() }
    }

    nonisolated func home(_ home: HMHome, didRemove actionSet: HMActionSet) {
        Task { @MainActor in self.homesChanged() }
    }

    nonisolated func homeDidUpdateName(_ home: HMHome) {
        Task { @MainActor in self.revision += 1 }
    }

    nonisolated func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        Task { @MainActor in self.revision += 1 }
    }

    nonisolated func accessoryDidUpdateReachability(_ accessory: HMAccessory) {
        Task { @MainActor in self.revision += 1 }
    }
}
