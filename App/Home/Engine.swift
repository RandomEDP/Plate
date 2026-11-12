import Foundation
import HomeKit
import Observation
import PlateCore
import UserNotifications

/// The part of the dashboard that does things over time: counts timers down and announces them, runs routines and
/// their schedules, carries out typed commands, gives the spoken briefing, and wakes the wall display on movement.
/// One of these lives for as long as the app does.
@MainActor
@Observable
final class DashboardEngine {
    let model: AppModel
    let home: HomeStore
    let music: MusicStore
    let weather: WeatherStore
    let lightShow = LightShowRunner()

    /// Goes up whenever something wants the wall display woken (a motion sensor, a finished timer).
    private(set) var wakeRequests = 0
    /// Goes up whenever something wants the artwork screen shown now.
    private(set) var artworkRequests = 0
    /// The routine that's running, for showing progress on its tile.
    private(set) var runningRoutine: UUID?

    @ObservationIgnored private var lastTick = Date()
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(model: AppModel, home: HomeStore, music: MusicStore, weather: WeatherStore) {
        self.model = model; self.home = home; self.music = music; self.weather = weather
        home.onActivity = { [weak model] text, icon in model?.household.dashboard.log(text, icon: icon) }
        home.onMotion = { [weak self] in
            guard let self, self.model.household.dashboard.idle.wakeOnMotion else { return }
            self.wakeRequests += 1
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    private var dashboard: HomeDashboard {
        get { model.household.dashboard }
        set { model.household.dashboard = newValue }
    }

    func wake() { wakeRequests += 1 }

    // MARK: Every second

    private func tick(now: Date = Date()) {
        Feedback.shared.settings = dashboard.style.sounds
        // Timers that have just finished.
        for t in dashboard.timers where t.isFinished(now: now) && !t.announced {
            if let i = dashboard.timers.firstIndex(where: { $0.id == t.id }) { dashboard.timers[i].announced = true }
            Feedback.shared.play(.timer)
            Feedback.shared.say("\(t.label == "Timer" ? "Your timer" : "\(t.label) timer") has finished")
            dashboard.log("\(t.label) timer finished", icon: "timer")
            wakeRequests += 1
            if let id = t.routineId { Task { await runRoutine(id) } }
        }
        // Finished timers tidy themselves away after ten minutes.
        if dashboard.timers.contains(where: { $0.isFinished(now: now) && now.timeIntervalSince($0.endsAt ?? now) > 600 }) {
            dashboard.timers.removeAll { $0.isFinished(now: now) && now.timeIntervalSince($0.endsAt ?? now) > 600 }
        }
        // Scheduled routines.
        if !dashboard.schedules.isEmpty {
            let w = weather.now
            for s in dashboard.schedules where s.isDue(lastCheck: lastTick, now: now, sunrise: w?.sunrise, sunset: w?.sunset) {
                Task { await runRoutine(s.routineId) }
            }
        }
        lastTick = now
    }

    // MARK: Timers

    @discardableResult
    func startTimer(label: String, seconds: Double, routine: UUID? = nil) -> DashTimer {
        let t = DashTimer(label: label, duration: seconds, routineId: routine)
        dashboard.timers.append(t)
        dashboard.log("\(label) timer for \(DashTimer.words(seconds))", icon: "timer")
        Feedback.shared.play(.tap)
        notify(t)
        return t
    }

    func cancelTimer(_ id: UUID) {
        dashboard.timers.removeAll { $0.id == id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    func togglePause(_ id: UUID) {
        guard let i = dashboard.timers.firstIndex(where: { $0.id == id }) else { return }
        if dashboard.timers[i].isPaused {
            dashboard.timers[i].resume(now: Date())
            notify(dashboard.timers[i])
        } else {
            dashboard.timers[i].pause(now: Date())
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        }
    }

    func addTime(_ id: UUID, seconds: Double) {
        guard let i = dashboard.timers.firstIndex(where: { $0.id == id }) else { return }
        dashboard.timers[i].add(seconds, now: Date())
        if !dashboard.timers[i].isPaused { notify(dashboard.timers[i]) }
    }

    /// A notification for when the timer ends, so it's still heard if Plate isn't on screen.
    private func notify(_ t: DashTimer) {
        let left = t.remaining(now: Date())
        guard left > 1 else { return }
        let centre = UNUserNotificationCenter.current()
        Task {
            guard (try? await centre.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = t.label == "Timer" ? "Timer finished" : "\(t.label) timer finished"
            content.body = "Your \(DashTimer.words(t.duration)) timer is done."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: left, repeats: false)
            try? await centre.add(UNNotificationRequest(identifier: t.id.uuidString, content: content, trigger: trigger))
        }
    }

    // MARK: Routines

    func runRoutine(_ id: UUID) async {
        guard let r = dashboard.routines.first(where: { $0.id == id }) else { return }
        await run(r)
    }

    func run(_ routine: Routine) async {
        guard runningRoutine != routine.id else { return }
        runningRoutine = routine.id
        Feedback.shared.play(.scene)
        dashboard.log("Ran \(routine.name)", icon: routine.icon)
        for action in routine.actions { await perform(action) }
        if runningRoutine == routine.id { runningRoutine = nil }
    }

    func perform(_ a: RoutineAction) async {
        switch a.kind {
        case .scene:
            if let s = home.scene(a.ref) { await home.run(s) } else { missing(a) }
        case .accessoryOn, .accessoryOff:
            if let acc = home.accessory(a.ref) { await home.set(acc, on: a.kind == .accessoryOn, quiet: true) } else { missing(a) }
        case .brightness:
            if let acc = home.accessory(a.ref) { await home.setBrightness(acc, to: Int(a.value ?? 50)) } else { missing(a) }
        case .roomOn, .roomOff:
            if let room = home.room(a.ref) { await home.set(room, on: a.kind == .roomOn) } else { missing(a) }
        case .allLightsOff:
            await home.allLightsOff()
        case .playAlbum:
            if let ref = a.ref { await music.play(ref, type: a.text) }
        case .pauseMusic:
            music.player.pause()
        case .startTimer:
            startTimer(label: (a.text ?? "").isEmpty ? "Timer" : a.text!, seconds: a.value ?? 300)
        case .say:
            Feedback.shared.say(a.text ?? "", force: true)
        case .wait:
            try? await Task.sleep(for: .seconds(min(3600, max(0, a.value ?? 5))))
        case .lightShow:
            lightShow.start(LightShow(rawValue: a.text ?? "") ?? .party, home: home)
        case .stopLightShow:
            lightShow.stop(home: home)
        case .showArtwork:
            artworkRequests += 1
        }
    }

    private func missing(_ a: RoutineAction) {
        home.problem = "“\(a.name ?? "Something")” in this routine isn't in your home any more. Edit the routine to fix it."
    }

    // MARK: Typed commands

    var commandNames: CommandNames {
        typealias N = CommandNames.Named
        return CommandNames(
            accessories: (home.home?.accessories ?? []).map { N(id: $0.uniqueIdentifier.uuidString, name: $0.name, room: $0.room?.name) },
            rooms: home.rooms.map { N(id: $0.uniqueIdentifier.uuidString, name: $0.name) },
            scenes: home.scenes.map { N(id: $0.uniqueIdentifier.uuidString, name: $0.name) },
            routines: dashboard.routines.map { N(id: $0.id.uuidString, name: $0.name) },
            music: dashboard.tiles.filter { $0.kind == .musicAlbum || $0.kind == .playlist }.map { N(id: $0.id.uuidString, name: $0.title) })
    }

    /// Carries out what was typed and returns what to show back.
    func command(_ text: String) async -> String {
        home.start()
        let result = CommandParser.parse(text, names: commandNames)
        if !result.understood { Feedback.shared.play(.error) }
        for action in result.actions {
            switch action {
            case .accessory(let id, let on):
                guard let a = home.accessory(id) else { continue }
                if let on { await home.set(a, on: on) } else { await home.toggle(a) }
            case .brightness(let id, let percent):
                if let a = home.accessory(id) { await home.setBrightness(a, to: percent); Feedback.shared.play(.on) }
            case .room(let id, let on):
                if let r = home.room(id) { await home.set(r, on: on) }
            case .roomBrightness(let id, let percent):
                guard let r = home.room(id) else { continue }
                Feedback.shared.play(.on)
                for a in r.accessories where HomeStore.category(of: a) == .light { await home.setBrightness(a, to: percent) }
            case .scene(let id):
                if let s = home.scene(id) { await home.run(s) }
            case .routine(let id):
                if let uuid = UUID(uuidString: id) { await runRoutine(uuid) }
            case .allLightsOff:
                await home.allLightsOff()
            case .play(let id):
                if let t = dashboard.tiles.first(where: { $0.id.uuidString == id }), let ref = t.ref {
                    await music.play(ref, type: t.kind == .playlist ? t.options["type"] ?? "playlist" : nil)
                }
            case .pause: music.player.pause()
            case .resume: try? await music.player.play()
            case .next: try? await music.player.skipToNextEntry()
            case .timer(let label, let seconds): startTimer(label: label, seconds: seconds)
            case .lightShow(let show): lightShow.start(show, home: home)
            case .stopLightShow: lightShow.stop(home: home)
            case .briefing: briefing()
            case .showArtwork: artworkRequests += 1
            }
        }
        return result.reply
    }

    // MARK: Briefing

    var choresDue: [Chore] {
        dashboard.chores.filter { !$0.isDone(on: Date()) }
    }

    func briefingText(now: Date = Date()) -> String {
        let hour = Calendar.plate.component(.hour, from: now)
        let name = model.household.members.first?.name
        let w = weather.now
        let day = model.dayIndex(for: now)
        let meals = model.household.plan.entries.filter { $0.day == day }.compactMap { model.recipe($0.recipeId)?.name }
        let bins = dashboard.recurring.filter { r in
            let next = r.next(onOrAfter: now)
            return Calendar.plate.isDate(next, inSameDayAs: now) || Calendar.plate.isDate(next, inSameDayAs: now.addingTimeInterval(86_400))
        }.map { "\($0.name) is \(DayText.relative($0.next(onOrAfter: now), now: now).lowercased())" }
        return Briefing.text(
            greeting: DayText.greeting(hour: hour, name: name),
            weather: w.map { "It's \(Int($0.temperature.rounded())) degrees and \($0.condition.lowercased())." },
            rain: w.flatMap { WeatherText.rainNote($0.hours, now: now) },
            meals: meals,
            chores: choresDue.map { c in c.assignee(on: now).map { "\(c.name.lowercased()) for \($0)" } ?? c.name.lowercased() },
            bins: bins,
            timers: dashboard.timers.filter { !$0.isFinished(now: now) }.count)
    }

    func briefing() {
        Task {
            await weather.refresh()
            Feedback.shared.stopSpeaking()
            Feedback.shared.say(briefingText(), force: true)
        }
    }

    /// The one-line summary under the greeting.
    func summaryLine(now: Date = Date()) -> String {
        let w = weather.now
        return DayText.summary(lightsOn: home.lightsOnCount, inside: home.insideTemperature, outside: w?.temperature,
                               rain: w.flatMap { WeatherText.rainNote($0.hours, now: now) },
                               timers: dashboard.timers.filter { !$0.isFinished(now: now) }.count, choresDue: choresDue.count)
    }
}
