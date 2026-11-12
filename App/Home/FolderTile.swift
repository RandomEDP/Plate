import PlateCore
import SwiftUI

/// A folder of tiles, like a folder on the home screen: little pictures of what's inside, and a tap opens it.
struct FolderTile: View {
    let tile: DashboardTile
    let editing: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.dashStyle) private var style
    @State private var open = false

    var body: some View {
        let inside = model.household.dashboard.tiles(inFolder: tile.id)
        Button { Feedback.shared.play(.tap); open = true } label: {
            TileCard {
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geo in
                        // As many little squares as fit: 2 × 2 on a small tile, more on bigger ones.
                        let side = max(22, min(54, (min(geo.size.width, geo.size.height) - 8) / 2))
                        let across = max(2, Int((geo.size.width + 8) / (side + 8)))
                        let down = max(1, Int((geo.size.height + 8) / (side + 8)))
                        let shown = Array(inside.prefix(across * down))
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: 8), count: across), alignment: .leading, spacing: 8) {
                            ForEach(shown) { t in
                                RoundedRectangle(cornerRadius: side * 0.26, style: .continuous)
                                    .fill((t.tint ?? style.accent).color.opacity(t.tint == nil ? 0.22 : 0.9))
                                    .frame(width: side, height: side)
                                    .overlay(Image(systemName: t.icon ?? t.kind.symbol).font(.system(size: side * 0.42, weight: .medium))
                                        .foregroundStyle(t.tint.map { $0.wantsDarkText ? Color.black : Color.white } ?? Color.primary))
                            }
                        }
                        if inside.isEmpty {
                            Image(systemName: tile.icon ?? "folder").font(.system(size: 30, weight: .medium)).foregroundStyle(.secondary)
                        }
                    }
                    Text(tile.name("Folder")).font(.headline).lineLimit(1)
                    Text(inside.isEmpty ? "Empty: open to add" : "\(inside.count) inside").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
        .disabled(editing)
        .sheet(isPresented: $open) { FolderView(folderId: tile.id) }
    }
}

/// An open folder: the real tiles, working as they do on the dashboard.
struct FolderView: View {
    let folderId: UUID
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var home
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var deviceScheme
    @State private var editing = false
    @State private var showAdd = false
    @State private var editTile: DashboardTile?

    var body: some View {
        let dashboard = model.household.dashboard
        let style = dashboard.style.clamped
        let spacing = CGFloat(style.spacing)
        let folder = dashboard.tiles.first { $0.id == folderId }
        let tiles = dashboard.tiles(inFolder: folderId)
        NavigationStack {
            GeometryReader { geo in
                let width = max(100, geo.size.width - spacing * 2)
                let cols = DashboardGrid.columns(forWidth: width, minTile: style.density.minTile, spacing: spacing)
                let cell = (width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
                ScrollView {
                    VStack(alignment: .leading, spacing: spacing) {
                        if tiles.isEmpty {
                            Text("Nothing in here yet. Tap + to add tiles, or in the dashboard's edit mode use a tile's menu and choose “Move into folder”.")
                                .foregroundStyle(.secondary).padding(.top, 30)
                        }
                        TileGrid(columns: cols, spacing: spacing, cell: cell) {
                            ForEach(tiles) { t in
                                TileView(tile: t, editing: editing)
                                    .overlay { if editing { Color.clear.contentShape(Rectangle()).onTapGesture { editTile = t } } }
                                    .overlay(alignment: .topLeading) { if editing { badge(t) } }
                                    .layoutValue(key: TileSizeKey.self, value: t.size)
                            }
                        }
                        .animation(.spring(duration: 0.3), value: tiles)
                    }
                    .padding(spacing)
                }
                .scrollIndicators(.hidden)
            }
            .background(DashboardBackground(style: style))
            .navigationTitle(folder?.name("Folder") ?? "Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(editing ? "Finished" : "Edit") { withAnimation { editing.toggle() } } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Label("Add tile", systemImage: "plus") }
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showAdd) { AddTileView(page: folder?.pageId, folder: folderId) }
            .sheet(item: $editTile) { TileEditorView(tile: $0) }
        }
        .fontDesign(style.font.design)
        .tint(style.accent.color)
        .environment(\.dashStyle, style)
        .environment(\.colorScheme, style.scheme ?? deviceScheme)
        .presentationDetents([.medium, .large])
        .onAppear { home.start() }
    }

    private func badge(_ t: DashboardTile) -> some View {
        Menu {
            Button("Move out of the folder", systemImage: "arrow.up.forward.square") {
                withAnimation { model.household.dashboard.moveTile(t.id, toFolder: nil) }
            }
            Button("Name, icon, colour…", systemImage: "slider.horizontal.3") { editTile = t }
            Picker("Size", selection: Binding(get: { t.size }, set: { s in withAnimation { model.household.dashboard.resize(t.id, to: s) } })) {
                ForEach(TileSize.allCases) { Text($0.title).tag($0) }
            }
            Button("Move earlier", systemImage: "arrow.left") { withAnimation { shift(t, -1) } }
            Button("Move later", systemImage: "arrow.right") { withAnimation { shift(t, 1) } }
            Button("Remove", systemImage: "trash", role: .destructive) { withAnimation { model.household.dashboard.remove(t.id) } }
        } label: {
            Image(systemName: "ellipsis.circle.fill").font(.title).symbolRenderingMode(.palette).foregroundStyle(.white, .blue)
        }
        .padding(-8)
    }

    /// Swaps a tile with its neighbour inside the folder.
    private func shift(_ t: DashboardTile, _ by: Int) {
        let inside = model.household.dashboard.tiles(inFolder: folderId)
        guard let i = inside.firstIndex(where: { $0.id == t.id }), inside.indices.contains(i + by),
              let a = model.household.dashboard.tiles.firstIndex(where: { $0.id == t.id }),
              let b = model.household.dashboard.tiles.firstIndex(where: { $0.id == inside[i + by].id }) else { return }
        model.household.dashboard.tiles.swapAt(a, b)
    }
}
