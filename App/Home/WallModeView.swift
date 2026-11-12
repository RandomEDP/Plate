import MusicKit
import PlateCore
import SwiftUI

/// Full-screen dashboard for an iPad on the wall. The screen stays on; after a few minutes without a touch it shows
/// the album that's playing, or otherwise your chosen photo album, with the time. A tap brings the dashboard back.
struct WallModeView: View {
    @Environment(AppModel.self) private var model
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
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private struct TimerKey: Equatable { let lastTouch: Date; let minutes: Int }

    private func wake() {
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
    @Environment(\.displayScale) private var scale
    @ObservedObject private var playerState = ApplicationMusicPlayer.shared.state
    @ObservedObject private var queue = ApplicationMusicPlayer.shared.queue
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
                        Image(uiImage: current)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .id(currentId)
                            .transition(.opacity)
                    }
                case .clockOnly:
                    LinearGradient(colors: [.indigo, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                if settings.showClock || show == .clockOnly {
                    IdleClock(big: show == .clockOnly)
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
    let entry: ApplicationMusicPlayer.Queue.Entry
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

private struct IdleClock: View {
    let big: Bool
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            VStack(alignment: big ? .center : .leading, spacing: 2) {
                Text(ctx.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                    .font(.system(size: big ? 140 : 72, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(big ? .title : .title3)
            }
            .environment(\.locale, Locale(identifier: "en_GB"))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 12)
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: big ? .center : .bottomLeading)
        }
    }
}

/// Idle mode and wall mode settings.
struct DashboardSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(PhotoStore.self) private var photos
    @Environment(\.dismiss) private var dismiss
    @AppStorage("wallModeOnLaunch") private var wallOnLaunch = false
    @State private var albums: [PhotoStore.AlbumInfo] = []

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Picker("Show artwork after", selection: $model.household.dashboard.idle.minutes) {
                        Text("Never").tag(0)
                        ForEach([1, 2, 3, 5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    Toggle("Show the time", isOn: $model.household.dashboard.idle.showClock)
                } header: { Text("When nobody's using it") } footer: {
                    Text("While music is playing it shows the album cover. Otherwise it shows the photo album below. A tap goes back to the dashboard.")
                }
                Section("Photos") {
                    if photos.canRead {
                        Picker("Album", selection: Binding(get: { model.household.dashboard.idle.photoAlbumId },
                                                           set: { id in
                                                               model.household.dashboard.idle.photoAlbumId = id
                                                               model.household.dashboard.idle.photoAlbumTitle = albums.first { $0.id == id }?.title
                                                           })) {
                            Text("None").tag(String?.none)
                            ForEach(albums) { a in Text("\(a.title) (\(a.count))").tag(Optional(a.id)) }
                        }
                        Picker("Each photo for", selection: $model.household.dashboard.idle.secondsPerSlide) {
                            ForEach([10, 20, 30, 60, 120, 300], id: \.self) { s in
                                Text(s < 60 ? "\(s) seconds" : "\(s / 60) min").tag(s)
                            }
                        }
                    } else if photos.status == .denied || photos.status == .restricted {
                        Text("Plate isn't allowed to see your photos. Turn it on in Settings → Privacy & Security → Photos.")
                            .font(.subheadline)
                    } else {
                        Button("Choose a photo album") { Task { await photos.authorise(); albums = photos.albums() } }
                    }
                }
                Section {
                    Toggle("Dim at night", isOn: $model.household.dashboard.idle.nightDim)
                    if model.household.dashboard.idle.nightDim {
                        timePicker("From", $model.household.dashboard.idle.nightStart)
                        timePicker("Until", $model.household.dashboard.idle.nightEnd)
                        VStack(alignment: .leading) {
                            Text("How dark")
                            Slider(value: $model.household.dashboard.idle.nightDarkness, in: 0.2...0.95)
                        }
                    }
                } header: { Text("Night") }
                Section {
                    Toggle("Open in wall mode", isOn: $wallOnLaunch)
                } header: { Text("This device") } footer: {
                    Text("Turn this on for the iPad on the wall. To stop anyone leaving Plate, use Guided Access: Settings → Accessibility → Guided Access, then triple-click the top button in Plate.")
                }
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { albums = photos.albums() }
        }
    }

    private func timePicker(_ title: String, _ minutes: Binding<Int>) -> some View {
        Picker(title, selection: minutes) {
            ForEach(Array(stride(from: 0, to: 1440, by: 30)), id: \.self) { Text(IdleMode.timeText($0)).tag($0) }
        }
    }
}
