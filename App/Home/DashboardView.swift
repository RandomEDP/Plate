import PlateCore
import SwiftUI
import UniformTypeIdentifiers

/// The Home tab: the dashboard inside the app, with buttons to edit it and to go into wall mode.
struct HomeTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var home

    var body: some View {
        NavigationStack {
            DashboardView(wall: false)
                .navigationTitle(home.home?.name ?? "Home")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { model.showWall = true } label: { Label("Wall mode", systemImage: "rectangle.inset.filled") }
                    }
                }
        }
    }
}

/// The grid of tiles. Used in the Home tab and, full screen, in wall mode.
struct DashboardView: View {
    let wall: Bool
    var onExit: (() -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var home
    @Environment(MusicStore.self) private var music
    @State private var editing = false
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var dragging: UUID?

    private let spacing: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - spacing * 2
            let cols = DashboardGrid.columns(forWidth: width, minTile: wall ? 170 : 150, spacing: spacing)
            let cell = (width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    if let problem = home.problem ?? music.problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                            .onTapGesture { home.problem = nil; music.problem = nil }
                    }
                    homeStatus
                    if model.household.dashboard.visibleTiles.isEmpty {
                        emptyState
                    } else {
                        TileGrid(columns: cols, spacing: spacing, cell: cell) {
                            ForEach(model.household.dashboard.visibleTiles) { tile in
                                tileCell(tile)
                                    .layoutValue(key: TileSizeKey.self, value: tile.size)
                            }
                        }
                        .animation(.spring(duration: 0.3), value: model.household.dashboard.tiles)
                    }
                }
                .padding(spacing)
                .padding(.top, wall ? 44 : 0)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .topTrailing) { if wall { wallControls } }
        .toolbar {
            if !wall {
                ToolbarItemGroup(placement: .topBarLeading) { editButtons }
            }
        }
        .sheet(isPresented: $showAdd) { AddTileView() }
        .sheet(isPresented: $showSettings) { DashboardSettingsView() }
        .onAppear { if !model.household.dashboard.tiles.isEmpty && needsHome { home.start() } }
    }

    private var needsHome: Bool {
        model.household.dashboard.tiles.contains { [.accessory, .scene, .room].contains($0.kind) }
    }

    @ViewBuilder private var editButtons: some View {
        Button(editing ? "Done" : "Edit") { withAnimation { editing.toggle() } }
            .fontWeight(editing ? .semibold : .regular)
        if editing {
            Button { showAdd = true } label: { Label("Add tile", systemImage: "plus") }
            Button { showSettings = true } label: { Label("Dashboard settings", systemImage: "gearshape") }
        }
    }

    /// Small, faint buttons in wall mode so they don't spoil the look.
    private var wallControls: some View {
        HStack(spacing: 14) {
            editButtons
            if !editing, let onExit {
                Button { onExit() } label: { Label("Leave wall mode", systemImage: "xmark") }
            }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .opacity(editing ? 1 : 0.6)
        .padding(.trailing, spacing).padding(.top, 8)
    }

    @ViewBuilder private func tileCell(_ tile: DashboardTile) -> some View {
        let base = TileView(tile: tile, editing: editing)
            .opacity(dragging == tile.id ? 0.4 : 1)
            .overlay(alignment: .topLeading) { if editing { EditBadge(tile: tile) } }
            .modifier(Jiggle(on: editing))
        if editing {
            base
                .onDrag {
                    dragging = tile.id
                    return NSItemProvider(object: tile.id.uuidString as NSString)
                }
                .onDrop(of: [.plainText], delegate: TileDrop(target: tile.id, dragging: $dragging) { from, to in
                    model.household.dashboard.move(from, before: to)
                })
        } else {
            base
        }
    }

    @ViewBuilder private var homeStatus: some View {
        switch home.status {
        case .denied:
            notice("Plate can't see your home", "Turn on Plate in Settings → Privacy & Security → HomeKit, then come back.",
                   button: "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        case .noHome:
            notice("No home set up yet", "Add your lights and plugs in Apple's Home app first. They'll appear here.", button: nil) {}
        default:
            EmptyView()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your dashboard").font(.title2.bold())
            Text("Put your lights, plugs and scenes next to Apple Music albums, today's meals and the shopping list. "
                 + "Mount an iPad on the wall and turn on wall mode: after a few minutes it shows your photos, or the "
                 + "album that's playing, and a tap brings the dashboard back.")
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    Task { await makeStarter() }
                } label: { Label("Set it up from my home", systemImage: "house") }
                    .buttonStyle(.borderedProminent)
                Button { editing = true; showAdd = true } label: { Label("Add tiles myself", systemImage: "plus") }
                    .buttonStyle(.bordered)
            }
        }
        .card()
    }

    private func makeStarter() async {
        home.start()
        // HomeKit takes a moment the first time (and while the permission prompt is up).
        for _ in 0..<60 where home.status == .loading || home.status == .notStarted {
            try? await Task.sleep(for: .milliseconds(500))
        }
        var tiles = DashboardStarter.layout(accessories: home.summaries, scenes: home.sceneSummaries)
        tiles.insert(DashboardTile(kind: .weather, title: "Weather"), at: 1)
        tiles.insert(DashboardTile(kind: .nowPlaying, title: "Now playing"), at: 2)
        for t in tiles { model.household.dashboard.add(t) }
    }

    private func notice(_ title: String, _ text: String, button: String?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
            if let button { Button(button, action: action).buttonStyle(.bordered) }
        }
        .card()
    }
}

/// The remove button and size menu on a tile in edit mode.
private struct EditBadge: View {
    let tile: DashboardTile
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Button {
                withAnimation { model.household.dashboard.remove(tile.id) }
            } label: {
                Image(systemName: "minus.circle.fill").font(.title).symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
            }
            .accessibilityLabel("Remove \(tile.title)")
            Spacer()
            Menu {
                Picker("Size", selection: Binding(get: { tile.size },
                                                  set: { s in withAnimation { model.household.dashboard.resize(tile.id, to: s) } })) {
                    ForEach(TileSize.allCases) { Text($0.title).tag($0) }
                }
                Button("Move earlier", systemImage: "arrow.left") { withAnimation { model.household.dashboard.shift(tile.id, by: -1) } }
                Button("Move later", systemImage: "arrow.right") { withAnimation { model.household.dashboard.shift(tile.id, by: 1) } }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill").font(.title)
                    .symbolRenderingMode(.palette).foregroundStyle(.white, .blue)
            }
            .accessibilityLabel("Resize or move \(tile.title)")
        }
        .padding(-8)
    }
}

private struct Jiggle: ViewModifier {
    let on: Bool
    @State private var phase = false
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(on ? (phase ? 0.8 : -0.8) : 0))
            .animation(on ? .easeInOut(duration: 0.14).repeatForever(autoreverses: true) : .default, value: phase)
            .onChange(of: on, initial: true) { _, now in phase = now }
    }
}

private struct TileDrop: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let move: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation { move(dragging, target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

// MARK: Grid layout

struct TileSizeKey: LayoutValueKey {
    static let defaultValue: TileSize = .small
}

/// Lays tiles out on a grid of square cells using `DashboardGrid.place` (tested in PlateCore).
struct TileGrid: Layout {
    let columns: Int
    let spacing: CGFloat
    let cell: CGFloat

    private func placements(_ subviews: Subviews) -> [TilePlacement] {
        DashboardGrid.place(subviews.map { (UUID(), $0[TileSizeKey.self]) }, columns: columns)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = CGFloat(DashboardGrid.rowCount(placements(subviews)))
        let width = CGFloat(columns) * cell + CGFloat(columns - 1) * spacing
        return CGSize(width: width, height: max(0, rows * cell + (rows - 1) * spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, p) in zip(subviews, placements(subviews)) {
            let x = bounds.minX + CGFloat(p.column) * (cell + spacing)
            let y = bounds.minY + CGFloat(p.row) * (cell + spacing)
            let w = CGFloat(p.columns) * cell + CGFloat(p.columns - 1) * spacing
            let h = CGFloat(p.rows) * cell + CGFloat(p.rows - 1) * spacing
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: h))
        }
    }
}
