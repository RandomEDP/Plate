import PlateCore
import SwiftUI

@main
struct PlateApp: App {
    @State private var model = AppModel()
    @State private var home = HomeStore()
    @State private var music = MusicStore()
    @State private var photos = PhotoStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(home)
                .environment(music)
                .environment(photos)
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
