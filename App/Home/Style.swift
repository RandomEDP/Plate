import AudioToolbox
import AVFoundation
import MusicKit
import PlateCore
import SwiftUI

// The dashboard's look, as SwiftUI: colours from PlateCore's `RGB`, the background behind the tiles, the card every
// tile sits on, and the sounds and taps. The choices themselves live in `DashboardStyle` (PlateCore, tested).

extension RGB {
    var color: Color { Color(red: r, green: g, blue: b) }

    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Double(r), Double(g), Double(b))
    }
}

/// A SwiftUI colour picker bound to one of PlateCore's colours.
struct RGBPicker: View {
    let title: String
    @Binding var value: RGB
    var body: some View {
        ColorPicker(title, selection: Binding(get: { value.color }, set: { value = RGB($0) }), supportsOpacity: false)
    }
}

private struct DashStyleKey: EnvironmentKey { static let defaultValue = DashboardStyle() }
private struct TileTintKey: EnvironmentKey { static let defaultValue: RGB? = nil }
private struct TileIconKey: EnvironmentKey { static let defaultValue: String? = nil }

extension EnvironmentValues {
    var dashStyle: DashboardStyle {
        get { self[DashStyleKey.self] }
        set { self[DashStyleKey.self] = newValue }
    }
    /// The tile's own colour, when it has been given one.
    var tileTint: RGB? {
        get { self[TileTintKey.self] }
        set { self[TileTintKey.self] = newValue }
    }
    /// The tile's own icon, when it has been given one.
    var tileIcon: String? {
        get { self[TileIconKey.self] }
        set { self[TileIconKey.self] = newValue }
    }
}

extension FontLook {
    var design: Font.Design {
        switch self {
        case .standard: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .mono: return .monospaced
        }
    }
}

extension DashboardStyle {
    /// The light or dark mode to force on the whole dashboard, or nil to follow the device.
    var scheme: ColorScheme? {
        switch appearance {
        case .auto: return backgroundIsDark.map { $0 ? .dark : .light }
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// The card every tile sits on. It draws the tile's shape and colour from the dashboard's style (or the tile's own
/// colour, or the "on" colour when lit) and makes the text inside light or dark so it's always readable.
struct TileCard<Content: View>: View {
    var lit = false
    /// A colour for the lit state other than the style's "on" colour.
    var litColor: RGB?
    var alignment: Alignment = .topLeading
    @ViewBuilder var content: Content

    @Environment(\.dashStyle) private var style
    @Environment(\.tileTint) private var tint
    @Environment(\.colorScheme) private var deviceScheme

    private var fill: RGB? { lit ? (litColor ?? style.onColor) : tint }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        let dark = style.tileTextIsDark(fill: fill)
        ZStack(alignment: alignment) {
            background(shape)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .clipShape(shape)
        .environment(\.colorScheme, dark.map { $0 ? .light : .dark } ?? deviceScheme)
    }

    @ViewBuilder private func background(_ shape: RoundedRectangle) -> some View {
        if let fill {
            shape.fill(fill.color.gradient).opacity(lit ? 1 : style.tileOpacity)
        } else {
            switch style.tileLook {
            case .solid:
                shape.fill(style.tileColor?.color ?? Color(.secondarySystemGroupedBackground)).opacity(style.tileOpacity)
            case .glass:
                shape.fill(.ultraThinMaterial).opacity(style.tileOpacity)
                    .overlay(shape.fill((style.tileColor?.color ?? .clear).opacity(0.25)))
                    .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
            case .outline:
                shape.fill((style.tileColor?.color ?? .clear).opacity(0.08))
                    .overlay(shape.strokeBorder(style.accent.color.opacity(0.7), lineWidth: 1.5))
            }
        }
    }
}

/// What's behind the tiles.
struct DashboardBackground: View {
    let style: DashboardStyle
    @Environment(PhotoStore.self) private var photos
    @ObservedObject private var queue = SystemMusicPlayer.shared.queue
    @State private var photo: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch style.background {
                case .system:
                    Color(.systemGroupedBackground)
                case .solid:
                    style.backgroundA.color
                case .gradient:
                    gradient
                case .aurora:
                    AuroraView(a: style.backgroundA, b: style.backgroundB, accent: style.accent)
                case .photo:
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height).clipped()
                            .blur(radius: style.backgroundBlur * 40, opaque: true)
                    } else { gradient }
                case .nowPlaying:
                    if let art = queue.currentEntry?.artwork {
                        let side = max(geo.size.width, geo.size.height)
                        ArtworkImage(art, width: side, height: side)
                            .frame(width: geo.size.width, height: geo.size.height).clipped()
                            .blur(radius: 20 + style.backgroundBlur * 60, opaque: true)
                    } else { gradient }
                }
                if style.background != .system { Color.black.opacity(style.backgroundDim) }
            }
            .task(id: style.backgroundPhotoId) {
                guard style.background == .photo, let id = style.backgroundPhotoId else { photo = nil; return }
                let s = max(geo.size.width, geo.size.height) * 2
                photo = await photos.image(id, size: CGSize(width: s, height: s))
            }
        }
        .ignoresSafeArea()
    }

    private var gradient: some View {
        LinearGradient(colors: [style.backgroundA.color, style.backgroundB.color], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Slowly drifting colours, like the northern lights.
struct AuroraView: View {
    let a: RGB
    let b: RGB
    let accent: RGB

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate / 9
            let x1 = Float(0.5 + 0.28 * sin(t)), y1 = Float(0.5 + 0.28 * cos(t * 0.8))
            let x0 = Float(0.5 + 0.2 * sin(t * 0.6 + 2)), x2 = Float(0.5 + 0.2 * cos(t * 0.7 + 1))
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [x0, 0], [1, 0],
                [0, Float(0.5 + 0.2 * cos(t * 0.5))], [x1, y1], [1, Float(0.5 + 0.2 * sin(t * 0.9))],
                [0, 1], [x2, 1], [1, 1],
            ], colors: [
                a.color, a.mixed(with: b, 0.4).color, b.color,
                a.mixed(with: accent, 0.35).color, b.mixed(with: accent, 0.5).color, a.mixed(with: b, 0.7).color,
                b.color, a.mixed(with: b, 0.5).color, a.color,
            ])
        }
    }
}

/// Sounds, taps and speech for the dashboard. Sounds are made from notes (see `SoundPack` in PlateCore), written out
/// as little sound files and played as system sounds, which leaves any music that's playing alone.
@MainActor
final class Feedback {
    static let shared = Feedback()
    var settings = SoundSettings()

    private var sounds: [String: SystemSoundID] = [:]
    private let speaker = AVSpeechSynthesizer()

    func play(_ event: SoundEvent) {
        haptic(event)
        let s = settings
        guard s.pack != .off, s.volume > 0.01 else { return }
        let key = "\(s.pack.rawValue)-\(event.rawValue)-\(Int((s.volume * 20).rounded()))"
        if let id = sounds[key] { AudioServicesPlaySystemSound(id); return }
        guard let recipe = s.pack.recipe(for: event) else { return }
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("plate-\(key).wav")
        do {
            try ToneSynth.wav(ToneSynth.render(recipe, volume: s.volume)).write(to: url, options: .atomic)
            var id: SystemSoundID = 0
            guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError else { return }
            sounds[key] = id
            AudioServicesPlaySystemSound(id)
        } catch {
            print("Plate couldn't make a sound: \(error)")
        }
    }

    private func haptic(_ event: SoundEvent) {
        guard settings.haptics else { return }
        switch event {
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .timer: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .scene: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .wake: break
        default: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    /// Says something out loud in a British voice, if speech is on.
    func say(_ text: String, force: Bool = false) {
        guard settings.speech || force, !text.isEmpty else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-GB")
        u.volume = Float(max(0.3, settings.volume))
        speaker.speak(u)
    }

    func stopSpeaking() { speaker.stopSpeaking(at: .immediate) }
}

/// A grid of icons to choose from, for tiles, routines and chores.
struct IconPicker: View {
    @Binding var selection: String?
    var allowNone = true

    static let icons = [
        "lightbulb.fill", "lamp.desk.fill", "lamp.floor.fill", "lamp.table.fill", "light.strip.2", "chandelier.fill", "poweroutlet.type.g.fill",
        "fan.fill", "thermometer.medium", "flame.fill", "snowflake", "humidity.fill", "lock.fill", "door.left.hand.closed",
        "blinds.horizontal.closed", "curtains.closed", "tv.fill", "hifispeaker.fill", "homepod.fill", "gamecontroller.fill",
        "sofa.fill", "bed.double.fill", "bathtub.fill", "shower.fill", "toilet.fill", "washer.fill", "dishwasher.fill",
        "refrigerator.fill", "oven.fill", "cooktop.fill", "microwave.fill", "cup.and.saucer.fill", "fork.knife", "wineglass.fill",
        "house.fill", "sun.max.fill", "moon.fill", "moon.stars.fill", "sunrise.fill", "sunset.fill", "sparkles", "star.fill",
        "heart.fill", "bolt.fill", "leaf.fill", "drop.fill", "party.popper.fill", "music.note", "play.fill", "film.fill",
        "book.fill", "desktopcomputer", "laptopcomputer", "wifi", "trash.fill", "arrow.3.trianglepath", "cart.fill",
        "figure.walk", "car.fill", "bicycle", "airplane", "pawprint.fill", "gift.fill", "bell.fill", "timer", "alarm.fill",
        "calendar", "camera.fill", "video.fill", "wand.and.stars", "power", "poweroff", "square.grid.2x2.fill", "person.2.fill",
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 10) {
            if allowNone {
                cell(nil, symbol: "circle.slash")
            }
            ForEach(Self.icons, id: \.self) { cell($0, symbol: $0) }
        }
        .padding(.vertical, 4)
    }

    private func cell(_ value: String?, symbol: String) -> some View {
        Button { selection = value } label: {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(selection == value ? Color.accentColor.opacity(0.25) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value ?? "Default icon")
    }
}
