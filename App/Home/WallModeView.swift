import MusicKit
import PlateCore
import SwiftUI

/// Full-screen dashboard for an iPad on the wall. The screen stays on; after a few minutes without a touch it shows
/// the album that's playing, or otherwise your chosen photo album, with the time. A tap brings the dashboard back.
struct WallModeView: View {
    @Environment(AppModel.self) private var model
    @Environment(DashboardEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var lastTouch = Date()
    @State private var idle = false

    var body: some View {
        let settings = model.household.dashboard.idle
        ZStack {
            DashboardView(wall: true, onExit: { dismiss() })
            if idle {
                IdleArtworkView(settings: settings)
                    .transition(.opacity)
                    .onTapGesture { wake() }
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 1.2), value: idle)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in touched() })
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task(id: TimerKey(lastTouch: lastTouch, minutes: settings.minutes)) {
            guard let wait = IdleMode.secondsUntilIdle(lastTouch: lastTouch, now: Date(), settings: settings) else { return }
            try? await Task.sleep(for: .seconds(wait))
            if !Task.isCancelled { idle = true }
        }
        // A motion sensor or a finished timer brings the dashboard back; a routine or command can ask for the artwork.
        .onChange(of: engine.wakeRequests) { _, _ in if idle { wake() } else { lastTouch = Date() } }
        .onChange(of: engine.artworkRequests) { _, _ in idle = true }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private struct TimerKey: Equatable { let lastTouch: Date; let minutes: Int }

    private func wake() {
        if idle { Feedback.shared.play(.wake) }
        idle = false
        lastTouch = Date()
    }

    /// Any touch on the dashboard restarts the countdown. Only once a second, so dragging doesn't restart it constantly.
    private func touched() {
        if Date().timeIntervalSince(lastTouch) > 1 { lastTouch = Date() }
    }
}

/// What shows when nobody is using the wall iPad.
struct IdleArtworkView: View {
    let settings: IdleSettings
    @Environment(PhotoStore.self) private var photos
    @Environment(WeatherStore.self) private var weather
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var scale
    @ObservedObject private var playerState = SystemMusicPlayer.shared.state
    @ObservedObject private var queue = SystemMusicPlayer.shared.queue
    @State private var photoIds: [String] = []
    @State private var current: UIImage?
    @State private var currentId: String?

    var body: some View {
        let entry = queue.currentEntry
        let show = IdleArtwork.choose(musicPlaying: playerState.playbackStatus == .playing,
                                      hasNowPlayingArtwork: entry?.artwork != nil, photoCount: photoIds.count)
        GeometryReader { geo in
            ZStack {
                Color.black
                switch show {
                case .nowPlaying:
                    if let entry, let art = entry.artwork { NowPlayingArt(entry: entry, artwork: art, size: geo.size) }
                case .photos:
                    if let current {
                        DriftingPhoto(image: current, size: geo.size, drift: settings.drift, seconds: Double(max(5, settings.secondsPerSlide)))
                            .id(currentId)
                            .transition(.opacity)
                    }
                case .clockOnly:
                    if settings.aurora {
                        let style = model.household.dashboard.style
                        AuroraView(a: style.background == .system ? RGB(hex: "#1B1464")! : style.backgroundA.mixed(with: .black, 0.3),
                                   b: style.background == .system ? RGB(hex: "#0B0B1A")! : style.backgroundB.mixed(with: .black, 0.5),
                                   accent: style.accent)
                    } else {
                        LinearGradient(colors: [.indigo, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                if settings.showClock || show == .clockOnly {
                    IdleClock(big: show == .clockOnly, face: settings.clockFace, drift: settings.drift,
                              weather: settings.showWeather ? weather.now : nil)
                }
                TimelineView(.everyMinute) { ctx in
                    Color.black.opacity(IdleMode.dimming(ctx.date, settings: settings))
                }
                .allowsHitTesting(false)
            }
            .animation(.easeInOut(duration: 1.5), value: currentId)
            .animation(.easeInOut(duration: 1.5), value: show)
            // Restarts when the screen changes size too (rotating, or unfolding a foldable iPhone), so photos stay sharp.
            .task(id: SlideshowKey(album: settings.photoAlbumId, size: geo.size)) { await runSlideshow(size: geo.size) }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
    }

    private struct SlideshowKey: Equatable { let album: String?; let size: CGSize }

    private func runSlideshow(size: CGSize) async {
        if !photos.canRead { return }
        photoIds = photos.photoIds(in: settings.photoAlbumId)
        var show = Slideshow(items: photoIds)
        let px = CGSize(width: size.width * scale, height: size.height * scale)
        while !Task.isCancelled {
            if let id = show.next(), let image = await photos.image(id, size: px) {
                currentId = id
                current = image
            }
            try? await Task.sleep(for: .seconds(max(5, settings.secondsPerSlide)))
        }
    }
}

/// The cover of what's playing, big, on a blurred copy of itself, with the song and artist.
private struct NowPlayingArt: View {
    let entry: MusicPlayer.Queue.Entry
    let artwork: Artwork
    let size: CGSize

    var body: some View {
        let side = min(size.width, size.height) * 0.62
        ZStack {
            ArtworkImage(artwork, width: max(size.width, size.height), height: max(size.width, size.height))
                .frame(width: size.width, height: size.height)
                .blur(radius: 60)
                .overlay(Color.black.opacity(0.35))
                .clipped()
            let layout = size.width > size.height
                ? AnyLayout(HStackLayout(spacing: 48)) : AnyLayout(VStackLayout(spacing: 32))
            layout {
                ArtworkImage(artwork, width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
                VStack(alignment: size.width > size.height ? .leading : .center, spacing: 8) {
                    Text(entry.title).font(.system(size: 40, weight: .bold)).lineLimit(2)
                    if let s = entry.subtitle { Text(s).font(.title2).opacity(0.8).lineLimit(1) }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: size.width > size.height ? size.width * 0.3 : size.width * 0.8)
            }
        }
        .id(entry.id)
        .transition(.opacity)
    }
}

/// A photo that slowly zooms and slides while it's up, so the wall never looks frozen.
private struct DriftingPhoto: View {
    let image: UIImage
    let size: CGSize
    let drift: Bool
    let seconds: Double
    @State private var moved = false

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .scaleEffect(drift ? (moved ? 1.12 : 1.02) : 1)
            .offset(x: drift ? (moved ? -size.width * 0.02 : size.width * 0.02) : 0)
            .clipped()
            .onAppear { withAnimation(.linear(duration: seconds + 3)) { moved = true } }
    }
}

private struct IdleClock: View {
    let big: Bool
    let face: ClockFace
    let drift: Bool
    let weather: WeatherStore.Now?

    var body: some View {
        TimelineView(.periodic(from: .now, by: face == .analogue ? 1 : 10)) { ctx in
            let c = Calendar.plate.dateComponents([.hour, .minute], from: ctx.date)
            let nudge = drift ? IdleMode.burnInOffset(ctx.date) : (x: 0, y: 0)
            VStack(alignment: big ? .center : .leading, spacing: 4) {
                switch face {
                case .analogue:
                    AnalogueClock(date: ctx.date)
                        .frame(width: big ? 300 : 170, height: big ? 300 : 170)
                case .words:
                    Text(DayText.clockWords(hour: c.hour ?? 0, minute: c.minute ?? 0).capitalizedFirst)
                        .font(.system(size: big ? 84 : 50, weight: .semibold, design: .serif))
                        .multilineTextAlignment(big ? .center : .leading)
                        .minimumScaleFactor(0.5)
                case .flip:
                    HStack(spacing: big ? 16 : 10) {
                        FlipCard(text: String(format: "%02d", c.hour ?? 0), big: big)
                        FlipCard(text: String(format: "%02d", c.minute ?? 0), big: big)
                    }
                case .digital:
                    Text(ctx.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                        .font(.system(size: big ? 140 : 72, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                HStack(spacing: 14) {
                    Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    if let weather {
                        Label(WeatherText.temperature(weather.temperature), systemImage: weather.symbol)
                            .symbolRenderingMode(.multicolor)
                    }
                }
                .font(big ? .title : .title3)
                if let weather, let rain = WeatherText.rainNote(weather.hours, now: ctx.date) {
                    Label(rain, systemImage: "umbrella.fill").font(.headline)
                }
            }
            .environment(\.locale, Locale(identifier: "en_GB"))
            .environment(\.colorScheme, .dark)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 12)
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: big ? .center : .bottomLeading)
            .offset(x: nudge.x, y: nudge.y)
            .animation(.easeInOut(duration: 4), value: nudge.x)
        }
    }
}

/// One card of a flip clock: two digits on a dark tile with a line across the middle.
private struct FlipCard: View {
    let text: String
    let big: Bool
    var body: some View {
        Text(text)
            .font(.system(size: big ? 150 : 76, weight: .bold, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, big ? 22 : 12)
            .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: big ? 22 : 12))
            .overlay(Rectangle().fill(Color.black.opacity(0.7)).frame(height: 3))
            .id(text)
            .transition(.push(from: .top))
            .animation(.easeInOut(duration: 0.5), value: text)
    }
}
