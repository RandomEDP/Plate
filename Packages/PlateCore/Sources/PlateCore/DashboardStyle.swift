import Foundation

// How the dashboard looks and sounds: colours, background, tile shape, font, sound pack. All plain values saved with
// the household, so a look made on the phone shows up on the wall iPad once sharing arrives.

extension KeyedDecodingContainer {
    /// Reads a value, or uses the default when it's missing or was written by a newer Plate in a form this one can't
    /// read. Keeps old and new files opening.
    func value<T: Decodable>(_ key: Key, default fallback: @autoclosure () -> T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback()
    }

    func optional<T: Decodable>(_ key: Key, as type: T.Type = T.self) -> T? {
        try? decodeIfPresent(T.self, forKey: key)
    }
}

/// A colour, saved as "#RRGGBB".
public struct RGB: Codable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = min(1, max(0, r)); self.g = min(1, max(0, g)); self.b = min(1, max(0, b))
    }

    /// "#1A2B3C", "1a2b3c" or the short "#abc".
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    public var hex: String {
        func c(_ v: Double) -> String {
            let s = String(Int((v * 255).rounded()), radix: 16, uppercase: true)
            return s.count == 1 ? "0" + s : s
        }
        return "#" + c(r) + c(g) + c(b)
    }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let c = RGB(hex: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a colour: \(s)"))
        }
        self = c
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }

    /// From hue (0 to 1 round the colour wheel), saturation and brightness.
    public init(hue: Double, saturation: Double, brightness: Double) {
        let h = (hue - hue.rounded(.down)) * 6
        let i = Int(h) % 6
        let f = h - Double(Int(h))
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * f)
        let t = brightness * (1 - saturation * (1 - f))
        switch i {
        case 0: self.init(brightness, t, p)
        case 1: self.init(q, brightness, p)
        case 2: self.init(p, brightness, t)
        case 3: self.init(p, q, brightness)
        case 4: self.init(t, p, brightness)
        default: self.init(brightness, p, q)
        }
    }

    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    /// How bright the colour looks, 0 (black) to 1 (white), by the usual accessibility formula.
    public var luminance: Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// Contrast ratio against another colour, 1 (same) to 21 (black on white).
    public func contrast(with other: RGB) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Whether black text reads better than white on this colour.
    public var wantsDarkText: Bool { contrast(with: .black) >= contrast(with: .white) }

    public func mixed(with other: RGB, _ amount: Double) -> RGB {
        let t = min(1, max(0, amount))
        return RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    public static let black = RGB(0, 0, 0)
    public static let white = RGB(1, 1, 1)
}

public enum BackgroundKind: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    /// The usual light or dark grey.
    case system
    case solid
    /// Two colours, top-left to bottom-right.
    case gradient
    /// Slowly moving colours.
    case aurora
    /// A photo from the library, blurred and dimmed to taste.
    case photo
    /// The cover of whatever's playing, blurred (falls back to the gradient when nothing is).
    case nowPlaying

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: return "Plain"
        case .solid: return "One colour"
        case .gradient: return "Gradient"
        case .aurora: return "Aurora (moving)"
        case .photo: return "A photo"
        case .nowPlaying: return "Album that's playing"
        }
    }
}

public enum TileLook: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case solid, glass, outline
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .solid: return "Solid"
        case .glass: return "Frosted glass"
        case .outline: return "Outline"
        }
    }
}

public enum FontLook: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case standard, rounded, serif, mono
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .standard: return "Standard"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .mono: return "Typewriter"
        }
    }
}

public enum AppearanceChoice: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case auto, light, dark
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum TileDensity: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case compact, regular, roomy
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    /// The narrowest a tile may be, in points. Smaller means more tiles across.
    public var minTile: Double {
        switch self {
        case .compact: return 118
        case .regular: return 150
        case .roomy: return 190
        }
    }
}

/// Sounds and taps when you touch a tile.
public struct SoundSettings: Codable, Hashable, Sendable {
    public var pack: SoundPack
    /// 0 to 1.
    public var volume: Double
    public var haptics: Bool
    /// Say things out loud, such as "Pasta timer finished".
    public var speech: Bool

    public init(pack: SoundPack = .soft, volume: Double = 0.6, haptics: Bool = true, speech: Bool = true) {
        self.pack = pack; self.volume = volume; self.haptics = haptics; self.speech = speech
    }

    enum CodingKeys: String, CodingKey { case pack, volume, haptics, speech }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SoundSettings()
        pack = c.value(.pack, default: d.pack)
        volume = c.value(.volume, default: d.volume)
        haptics = c.value(.haptics, default: d.haptics)
        speech = c.value(.speech, default: d.speech)
    }
}

/// The whole look of the dashboard.
public struct DashboardStyle: Codable, Hashable, Sendable {
    /// Buttons, highlights and the edit controls.
    public var accent: RGB
    public var background: BackgroundKind
    public var backgroundA: RGB
    public var backgroundB: RGB
    /// The Photos identifier of the background picture.
    public var backgroundPhotoId: String?
    /// 0 (sharp) to 1 (very blurred).
    public var backgroundBlur: Double
    /// 0 (as is) to 0.9 (nearly black), so tiles stand out from a busy photo.
    public var backgroundDim: Double
    public var tileLook: TileLook
    /// nil uses the usual light or dark tile colour.
    public var tileColor: RGB?
    /// 0.2 to 1.
    public var tileOpacity: Double
    /// The colour of a tile for something that's switched on.
    public var onColor: RGB
    /// 0 (square) to 40 (very round).
    public var cornerRadius: Double
    /// Gap between tiles, 6 to 28.
    public var spacing: Double
    public var density: TileDensity
    public var font: FontLook
    public var appearance: AppearanceChoice
    /// "Good evening" with a one-line summary above the tiles.
    public var showGreeting: Bool
    public var sounds: SoundSettings

    public init(accent: RGB = RGB(hex: "#2E9E5B")!, background: BackgroundKind = .system,
                backgroundA: RGB = RGB(hex: "#1B2845")!, backgroundB: RGB = RGB(hex: "#5899E2")!,
                backgroundPhotoId: String? = nil, backgroundBlur: Double = 0.3, backgroundDim: Double = 0.25,
                tileLook: TileLook = .solid, tileColor: RGB? = nil, tileOpacity: Double = 1,
                onColor: RGB = RGB(hex: "#FFD60A")!, cornerRadius: Double = 22, spacing: Double = 16,
                density: TileDensity = .regular, font: FontLook = .standard, appearance: AppearanceChoice = .auto,
                showGreeting: Bool = true, sounds: SoundSettings = SoundSettings()) {
        self.accent = accent; self.background = background; self.backgroundA = backgroundA; self.backgroundB = backgroundB
        self.backgroundPhotoId = backgroundPhotoId; self.backgroundBlur = backgroundBlur; self.backgroundDim = backgroundDim
        self.tileLook = tileLook; self.tileColor = tileColor; self.tileOpacity = tileOpacity; self.onColor = onColor
        self.cornerRadius = cornerRadius; self.spacing = spacing; self.density = density; self.font = font
        self.appearance = appearance; self.showGreeting = showGreeting; self.sounds = sounds
    }

    enum CodingKeys: String, CodingKey {
        case accent, background, backgroundA, backgroundB, backgroundPhotoId, backgroundBlur, backgroundDim, tileLook,
             tileColor, tileOpacity, onColor, cornerRadius, spacing, density, font, appearance, showGreeting, sounds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DashboardStyle()
        accent = c.value(.accent, default: d.accent)
        background = c.value(.background, default: d.background)
        backgroundA = c.value(.backgroundA, default: d.backgroundA)
        backgroundB = c.value(.backgroundB, default: d.backgroundB)
        backgroundPhotoId = c.optional(.backgroundPhotoId)
        backgroundBlur = c.value(.backgroundBlur, default: d.backgroundBlur)
        backgroundDim = c.value(.backgroundDim, default: d.backgroundDim)
        tileLook = c.value(.tileLook, default: d.tileLook)
        tileColor = c.optional(.tileColor)
        tileOpacity = c.value(.tileOpacity, default: d.tileOpacity)
        onColor = c.value(.onColor, default: d.onColor)
        cornerRadius = c.value(.cornerRadius, default: d.cornerRadius)
        spacing = c.value(.spacing, default: d.spacing)
        density = c.value(.density, default: d.density)
        font = c.value(.font, default: d.font)
        appearance = c.value(.appearance, default: d.appearance)
        showGreeting = c.value(.showGreeting, default: d.showGreeting)
        sounds = c.value(.sounds, default: d.sounds)
    }

    /// Values kept inside sensible limits, whatever a slider or an imported file says.
    public var clamped: DashboardStyle {
        var s = self
        s.backgroundBlur = min(1, max(0, backgroundBlur))
        s.backgroundDim = min(0.9, max(0, backgroundDim))
        s.tileOpacity = min(1, max(0.2, tileOpacity))
        s.cornerRadius = min(40, max(0, cornerRadius))
        s.spacing = min(28, max(6, spacing))
        s.sounds.volume = min(1, max(0, sounds.volume))
        return s
    }

    /// Whether what's behind the tiles is dark (so frosted and outlined tiles should use light text).
    /// nil means "follow the device", for the plain background.
    public var backgroundIsDark: Bool? {
        switch background {
        case .system: return appearance == .auto ? nil : appearance == .dark
        case .solid: return !backgroundA.mixed(with: .black, backgroundDim).wantsDarkText
        case .gradient, .aurora: return !backgroundA.mixed(with: backgroundB, 0.5).mixed(with: .black, backgroundDim).wantsDarkText
        // Photos and album covers vary, so they're always dimmed enough for light text.
        case .photo, .nowPlaying: return true
        }
    }

    /// Whether text on a tile should be dark (true), light (false) or follow the device (nil).
    /// `fill` is the tile's own colour when it has one (a custom colour, or the "on" colour when lit).
    public func tileTextIsDark(fill: RGB?) -> Bool? {
        if let fill { return fill.wantsDarkText }
        if tileLook == .solid, let tileColor { return tileColor.wantsDarkText }
        if tileLook == .solid { return appearance == .auto ? nil : appearance == .light }
        return backgroundIsDark.map { !$0 }
    }
}

/// A ready-made look to start from.
public struct ThemePreset: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var style: DashboardStyle

    public static let all: [ThemePreset] = {
        func c(_ h: String) -> RGB { RGB(hex: h)! }
        return [
            ThemePreset(id: "classic", name: "Classic", style: DashboardStyle()),
            ThemePreset(id: "midnight", name: "Midnight", style: DashboardStyle(
                accent: c("#7AA2F7"), background: .gradient, backgroundA: c("#0B1026"), backgroundB: c("#1F2A5C"),
                backgroundDim: 0, tileLook: .glass, tileOpacity: 0.7, onColor: c("#F7C76A"), appearance: .dark)),
            ThemePreset(id: "sunset", name: "Sunset", style: DashboardStyle(
                accent: c("#FF7A59"), background: .gradient, backgroundA: c("#FF9A5A"), backgroundB: c("#8A2D6B"),
                backgroundDim: 0.1, tileLook: .glass, tileOpacity: 0.75, onColor: c("#FFE08A"), cornerRadius: 28,
                font: .rounded, appearance: .dark)),
            ThemePreset(id: "forest", name: "Forest", style: DashboardStyle(
                accent: c("#8BC34A"), background: .solid, backgroundA: c("#14261B"), backgroundDim: 0,
                tileColor: c("#21402C"), onColor: c("#C8E66B"), cornerRadius: 18, appearance: .dark)),
            ThemePreset(id: "ocean", name: "Ocean", style: DashboardStyle(
                accent: c("#00B4D8"), background: .aurora, backgroundA: c("#03045E"), backgroundB: c("#00B4D8"),
                backgroundDim: 0.15, tileLook: .glass, tileOpacity: 0.65, onColor: c("#90E0EF"), cornerRadius: 30,
                font: .rounded, appearance: .dark)),
            ThemePreset(id: "candy", name: "Candy", style: DashboardStyle(
                accent: c("#FF4F9A"), background: .gradient, backgroundA: c("#FFD1E8"), backgroundB: c("#C9E4FF"),
                backgroundDim: 0, tileColor: c("#FFFFFF"), tileOpacity: 0.9, onColor: c("#FF8AC4"), cornerRadius: 34,
                font: .rounded, appearance: .light)),
            ThemePreset(id: "paper", name: "Paper", style: DashboardStyle(
                accent: c("#B2553A"), background: .solid, backgroundA: c("#F3EDE2"), backgroundDim: 0,
                tileColor: c("#FBF8F2"), onColor: c("#F2C56B"), cornerRadius: 10, font: .serif, appearance: .light)),
            ThemePreset(id: "mono", name: "Mono", style: DashboardStyle(
                accent: c("#FFFFFF"), background: .solid, backgroundA: c("#000000"), backgroundDim: 0,
                tileLook: .outline, onColor: c("#FFFFFF"), cornerRadius: 6, spacing: 12, appearance: .dark)),
            ThemePreset(id: "terminal", name: "Terminal", style: DashboardStyle(
                accent: c("#39FF14"), background: .solid, backgroundA: c("#050A05"), backgroundDim: 0,
                tileLook: .outline, onColor: c("#39FF14"), cornerRadius: 0, spacing: 10, density: .compact,
                font: .mono, appearance: .dark, sounds: SoundSettings(pack: .retro))),
            ThemePreset(id: "neon", name: "Neon", style: DashboardStyle(
                accent: c("#FF2BD6"), background: .aurora, backgroundA: c("#12002B"), backgroundB: c("#FF2BD6"),
                backgroundDim: 0.3, tileLook: .glass, tileOpacity: 0.6, onColor: c("#00F5FF"), cornerRadius: 24,
                appearance: .dark, sounds: SoundSettings(pack: .glass))),
            ThemePreset(id: "album", name: "Album art", style: DashboardStyle(
                accent: c("#FF375F"), background: .nowPlaying, backgroundA: c("#2B1B3D"), backgroundB: c("#B23A6F"),
                backgroundBlur: 0.7, backgroundDim: 0.35, tileLook: .glass, tileOpacity: 0.65, appearance: .dark)),
        ]
    }()

    /// Applies a preset but keeps the person's own photo, greeting choice and sound volume.
    public func applied(to current: DashboardStyle) -> DashboardStyle {
        var s = style
        s.backgroundPhotoId = current.backgroundPhotoId
        s.showGreeting = current.showGreeting
        s.sounds.volume = current.sounds.volume
        s.sounds.haptics = current.sounds.haptics
        s.sounds.speech = current.sounds.speech
        return s
    }
}

// MARK: - Sounds

public enum SoundPack: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case off, soft, click, marimba, glass, retro
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .off: return "Silent"
        case .soft: return "Soft"
        case .click: return "Click"
        case .marimba: return "Marimba"
        case .glass: return "Glass"
        case .retro: return "Retro arcade"
        }
    }
}

public enum SoundEvent: String, Hashable, Sendable, CaseIterable {
    /// Something switched on / off.
    case on, off
    /// A scene or routine ran.
    case scene
    /// Something didn't work.
    case error
    /// A timer finished.
    case timer
    /// The dashboard came back from idle.
    case wake
    /// A plain tap (opening something, adding a tile).
    case tap
}

public enum Waveform: Sendable { case sine, triangle, square }

/// One note: when it starts, how long it rings, and how loud.
public struct Tone: Hashable, Sendable {
    public var frequency: Double
    public var start: Double
    public var duration: Double
    public var gain: Double
    public init(_ frequency: Double, at start: Double = 0, for duration: Double, gain: Double = 1) {
        self.frequency = frequency; self.start = start; self.duration = duration; self.gain = gain
    }
}

public struct SoundRecipe: Sendable {
    public var waveform: Waveform
    public var tones: [Tone]
    /// How quickly each note dies away: higher is more of a pluck, lower more of a hum.
    public var decay: Double
    public var length: Double { tones.map { $0.start + $0.duration }.max() ?? 0 }
}

extension SoundPack {
    /// The notes for an event in this pack. "On" always rises and "off" always falls, so they can be told apart
    /// without looking.
    public func recipe(for event: SoundEvent) -> SoundRecipe? {
        // Notes of a C major pentatonic scale, so any two sounds played together still sound pleasant.
        let c5 = 523.25, d5 = 587.33, e5 = 659.25, g5 = 783.99, a5 = 880.0, c6 = 1046.5, e6 = 1318.5, g4 = 392.0
        let wave: Waveform
        let decay: Double
        let stretch: Double
        switch self {
        case .off: return nil
        case .soft: wave = .sine; decay = 9; stretch = 1
        case .click: wave = .triangle; decay = 60; stretch = 0.35
        case .marimba: wave = .triangle; decay = 14; stretch = 1.2
        case .glass: wave = .sine; decay = 5; stretch = 1.8
        case .retro: wave = .square; decay = 3; stretch = 0.7
        }
        let n = 0.09 * stretch
        let shift = self == .glass ? 2.0 : 1.0
        func t(_ f: Double, _ i: Double, _ len: Double = 2, gain: Double = 1) -> Tone {
            Tone(f * shift, at: i * n, for: len * n + 0.04, gain: gain)
        }
        let tones: [Tone]
        switch event {
        case .on: tones = [t(e5, 0), t(a5, 1, 3)]
        case .off: tones = [t(a5, 0), t(e5, 1, 3)]
        case .scene: tones = [t(c5, 0), t(e5, 1), t(g5, 2), t(c6, 3, 4)]
        case .error: tones = [t(g4, 0, 2), t(g4 * 0.94, 2, 4)]
        case .timer: tones = [t(c6, 0), t(e6, 1), t(c6, 2), t(e6, 3), t(c6, 5), t(e6, 6), t(c6, 7), t(e6, 8, 5)]
        case .wake: tones = [t(g5, 0, 2, gain: 0.6), t(d5 * 2, 1, 4, gain: 0.6)]
        case .tap: tones = [t(c6, 0, 1, gain: 0.7)]
        }
        return SoundRecipe(waveform: wave, tones: tones, decay: decay)
    }
}

public enum ToneSynth {
    /// Turns a recipe into sound samples between -1 and 1. Each note fades in over a few milliseconds (so there's no
    /// click) and dies away; the result is scaled so stacked notes never clip.
    public static func render(_ recipe: SoundRecipe, sampleRate: Double = 44_100, volume: Double = 1) -> [Float] {
        let count = Int((recipe.length * sampleRate).rounded(.up))
        guard count > 0 else { return [] }
        var out = [Double](repeating: 0, count: count)
        for tone in recipe.tones {
            let first = Int(tone.start * sampleRate)
            let n = Int(tone.duration * sampleRate)
            guard n > 0 else { continue }
            for i in 0..<n where first + i < count {
                let time = Double(i) / sampleRate
                let phase = (time * tone.frequency).truncatingRemainder(dividingBy: 1)
                let raw: Double
                switch recipe.waveform {
                case .sine: raw = sin(2 * .pi * phase)
                case .triangle: raw = 4 * abs(phase - 0.5) - 1
                case .square: raw = phase < 0.5 ? 0.6 : -0.6
                }
                let attack = min(1, time / 0.004)
                let release = min(1, Double(n - i) / (0.012 * sampleRate))
                out[first + i] += raw * attack * release * exp(-recipe.decay * time) * tone.gain
            }
        }
        let peak = out.map { abs($0) }.max() ?? 0
        let scale = (peak > 0 ? min(1, 0.9 / peak) : 1) * min(1, max(0, volume))
        return out.map { Float($0 * scale) }
    }

    /// The samples as a 16-bit mono WAV file.
    public static func wav(_ samples: [Float], sampleRate: Int = 44_100) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        for s in samples {
            let v = Int16((max(-1, min(1, Double(s))) * 32767).rounded())
            withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
        }
        return d
    }
}
