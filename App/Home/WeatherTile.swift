import CoreLocation
import Observation
import PlateCore
import SwiftUI
import WeatherKit

/// The weather where the device is, from Apple Weather (WeatherKit). The location is asked for once and kept, rounded
/// to about a kilometre, so a wall iPad keeps showing the weather without asking again.
@MainActor
@Observable
final class WeatherStore {
    struct Now {
        var temperature: Double
        var symbol: String
        var condition: String
        var hours: [HourForecast]
        var days: [DayForecast] = []
        var sunrise: Date?
        var sunset: Date?
        var tomorrowSunrise: Date?
        var fetched: Date
    }

    var now: Now?
    var problem: String?
    var attribution: WeatherAttribution?
    private var loading = false
    private let manager = CLLocationManager()

    private var savedLocation: CLLocation? {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: "weatherLat") != nil else { return nil }
            return CLLocation(latitude: d.double(forKey: "weatherLat"), longitude: d.double(forKey: "weatherLon"))
        }
        set {
            let d = UserDefaults.standard
            if let newValue {
                // Two decimal places is about a kilometre: plenty for weather, and no more precise than it needs to be.
                d.set((newValue.coordinate.latitude * 100).rounded() / 100, forKey: "weatherLat")
                d.set((newValue.coordinate.longitude * 100).rounded() / 100, forKey: "weatherLon")
            } else {
                d.removeObject(forKey: "weatherLat"); d.removeObject(forKey: "weatherLon")
            }
        }
    }

    /// Fetches the weather if it's more than 20 minutes old.
    func refresh(force: Bool = false) async {
        if !force, let now, Date().timeIntervalSince(now.fetched) < 20 * 60 { return }
        guard !loading else { return }
        loading = true
        defer { loading = false }
        guard let location = await location() else { return }
        do {
            let (current, hourly, daily) = try await WeatherService.shared.weather(for: location, including: .current, .hourly, .daily)
            let days = Array(daily.forecast.prefix(7))
            now = Now(
                temperature: current.temperature.converted(to: .celsius).value,
                symbol: current.symbolName,
                condition: current.condition.description,
                hours: hourly.forecast.prefix(36).map {
                    HourForecast(date: $0.date, temperature: $0.temperature.converted(to: .celsius).value,
                                 precipitationChance: $0.precipitationChance)
                },
                days: days.map {
                    DayForecast(date: $0.date, high: $0.highTemperature.converted(to: .celsius).value,
                                low: $0.lowTemperature.converted(to: .celsius).value, symbol: $0.symbolName,
                                precipitationChance: $0.precipitationChance)
                },
                sunrise: days.first?.sun.sunrise, sunset: days.first?.sun.sunset,
                tomorrowSunrise: days.dropFirst().first?.sun.sunrise,
                fetched: Date())
            problem = nil
            if attribution == nil { attribution = try? await WeatherService.shared.attribution }
        } catch {
            problem = "Couldn't get the weather: \(error.localizedDescription)"
        }
    }

    private func location() async -> CLLocation? {
        if let saved = savedLocation { return saved }
        switch manager.authorizationStatus {
        case .denied, .restricted:
            problem = "Plate needs your location for the weather. Turn it on in Settings → Privacy & Security → Location Services → Plate."
            return nil
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if update.authorizationDenied {
                    problem = "Plate needs your location for the weather. Turn it on in Settings → Privacy & Security → Location Services → Plate."
                    return nil
                }
                if let loc = update.location {
                    savedLocation = loc
                    return savedLocation
                }
            }
        } catch {
            problem = "Couldn't find where you are for the weather. Try again in a moment."
        }
        return nil
    }

    /// Forgets the saved location, for when the iPad moves.
    func forgetLocation() {
        savedLocation = nil
        now = nil
    }
}

struct WeatherTile: View {
    let large: Bool
    @Environment(WeatherStore.self) private var weather
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TileCard {
            VStack(alignment: .leading, spacing: 8) {
                if let now = weather.now {
                    HStack(alignment: .top) {
                        Image(systemName: now.symbol)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 40))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(WeatherText.temperature(now.temperature))
                                .font(.system(size: 40, weight: .semibold))
                            Text(now.condition).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if let r = WeatherText.range(now.hours, now: Date()) {
                            VStack(alignment: .trailing) {
                                Text("↑\(WeatherText.temperature(r.high))")
                                Text("↓\(WeatherText.temperature(r.low))").foregroundStyle(.secondary)
                            }
                            .font(.subheadline.monospacedDigit())
                        }
                    }
                    if let rain = WeatherText.rainNote(now.hours, now: Date()) {
                        Label(rain, systemImage: "umbrella.fill").font(.subheadline.weight(.medium)).foregroundStyle(.blue)
                    }
                    if large { hourly(now.hours) }
                } else if let problem = weather.problem {
                    Label("Weather", systemImage: "cloud.sun").font(.headline)
                    Text(problem).font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Weather", systemImage: "cloud.sun").font(.headline)
                    ProgressView()
                }
                Spacer(minLength: 0)
                attributionMark
            }
            .padding(16)
        }
        .task {
            // Refresh now and then every half hour while the tile is on screen.
            while !Task.isCancelled {
                await weather.refresh()
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }

    private func hourly(_ hours: [HourForecast]) -> some View {
        let start = Calendar.plate.dateInterval(of: .hour, for: Date())?.start ?? Date()
        let next = hours.filter { $0.date > start }.prefix(6)
        return HStack {
            ForEach(Array(next), id: \.date) { h in
                VStack(spacing: 4) {
                    Text(h.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(WeatherText.temperature(h.temperature)).font(.subheadline.monospacedDigit())
                    Text(h.precipitationChance >= 0.2 ? "\(Int((h.precipitationChance * 100).rounded()))%" : " ")
                        .font(.caption2).foregroundStyle(.blue)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .environment(\.locale, Locale(identifier: "en_GB"))
    }

    /// Apple requires its Weather mark and a link to its data sources wherever WeatherKit data is shown.
    @ViewBuilder private var attributionMark: some View {
        if let a = weather.attribution {
            Link(destination: a.legalPageURL) {
                AsyncImage(url: scheme == .dark ? a.combinedMarkDarkURL : a.combinedMarkLightURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(a.serviceName).font(.caption2)
                }
                .frame(height: 12)
            }
            .foregroundStyle(.secondary)
        }
    }
}
