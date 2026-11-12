import PlateCore
import SwiftUI

@main
struct PlateApp: App {
    @State private var model: AppModel
    @State private var home: HomeStore
    @State private var music: MusicStore
    @State private var photos = PhotoStore()
    @State private var weather: WeatherStore
    /// Counts timers down and runs routines and schedules for as long as the app is open.
    @State private var engine: DashboardEngine
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let model = AppModel(), home = HomeStore(), music = MusicStore(), weather = WeatherStore()
        _model = State(initialValue: model)
        _home = State(initialValue: home)
        _music = State(initialValue: music)
        _weather = State(initialValue: weather)
        _engine = State(initialValue: DashboardEngine(model: model, home: home, music: music, weather: weather))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .environment(model)
                .environment(home)
                .environment(music)
                .environment(photos)
                .environment(weather)
                .onAppear {
                    model.rollPlanForward()
                    model.collectInbox()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        model.rollPlanForward()
                        model.collectInbox()
                    case .background:
                        model.saveNow()
                    default: break
                    }
                }
                .onOpenURL { url in
                    // plate://import opens the import screen (used by the share extension's "Open Plate").
                    if url.host == "import" { model.selectedTab = .recipes }
                    // plate://wall opens wall mode; plate://command?text=kitchen%20off carries out a typed command.
                    // Both can be used from Apple's Shortcuts app, so Siri and automations can drive the dashboard.
                    if url.host == "wall" { model.showWall = true }
                    if url.host == "command",
                       let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "text" })?.value {
                        Task { model.banner = await engine.command(text) }
                    }
                    model.collectInbox()
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var home
    @Environment(MusicStore.self) private var music
    @Environment(PhotoStore.self) private var photos
    @Environment(WeatherStore.self) private var weather
    @Environment(DashboardEngine.self) private var engine

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppModel.Tab.today)
            KitchenView()
                .tabItem { Label("Kitchen", systemImage: "refrigerator") }
                .tag(AppModel.Tab.kitchen)
            RecipesView()
                .tabItem { Label("Recipes", systemImage: "book") }
                .tag(AppModel.Tab.recipes)
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(AppModel.Tab.plan)
            ShopView()
                .tabItem { Label("Shop", systemImage: "cart") }
                .tag(AppModel.Tab.shop)
            HomeTabView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppModel.Tab.home)
        }
        .fullScreenCover(isPresented: $model.showWall) {
            WallModeView()
                .environment(model)
                .environment(home)
                .environment(music)
                .environment(photos)
                .environment(weather)
                .environment(engine)
        }
        .overlay(alignment: .top) {
            if let text = model.banner {
                BannerView(text: text)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation { model.banner = nil }
                    }
            }
        }
        .animation(.spring, value: model.banner)
    }
}

struct BannerView: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
            .shadow(radius: 4, y: 2)
    }
}
