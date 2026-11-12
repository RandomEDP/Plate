import PlateCore
import SwiftUI
import UniformTypeIdentifiers

/// The Home tab: the dashboard inside the app. It draws its own top row (greeting and buttons) rather than a
/// navigation bar, so the background and colours you choose run edge to edge.
struct HomeTabView: View {
    var body: some View {
        DashboardView(wall: false)
    }
}

/// The grid of tiles. Used in the Home tab and, full screen, in wall mode.
struct DashboardView: View {
    let wall: Bool
    var onExit: (() -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var home
    @Environment(MusicStore.self) private var music
    @Environment(DashboardEngine.self) private var engine
    @Environment(\.colorScheme) private var deviceScheme
    @State private var editing = false
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var showStyle = false
    @State private var editTile: DashboardTile?
    @State private var dragging: UUID?
    @State private var page: UUID? = HomeDashboard.firstPageId
    @State private var renaming: DashboardPage?
    @State private var newName = ""

    private var dashboard: HomeDashboard { model.household.dashboard }
    private var style: DashboardStyle { dashboard.style.clamped }

    private var currentPage: UUID {
        let pages = dashboard.pageList
        return pages.contains { $0.id == page } ? (page ?? HomeDashboard.firstPageId) : (pages.first?.id ?? HomeDashboard.firstPageId)
    }

    var body: some View {
        let style = self.style
        let spacing = CGFloat(style.spacing)
        let pages = dashboard.pageList
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: spacing) {
                    // The clock needs about 230 points in the middle, clear of the greeting and the buttons.
                    header(wide: geo.size.width >= 800)
                    if pages.count > 1 || editing { pageBar }
                    if let problem = home.problem ?? music.problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                            .onTapGesture { home.problem = nil; music.problem = nil }
                    }
                }
                .padding([.horizontal, .top], spacing)
                .padding(.bottom, spacing / 2)
                if dashboard.visibleTiles.isEmpty && pages.count == 1 {
                    ScrollView {
                        VStack(alignment: .leading, spacing: spacing) { homeStatus; emptyState }.padding(spacing)
                    }
                } else {
                    // Pages sit side by side; swipe to move between them, like the home screen. Each page measures
                    // its own width, so the grid always fits the space it really has (beside the sidebar, say).
                    TabView(selection: $page) {
                        ForEach(pages) { p in
                            GeometryReader { pg in
                                pageView(p, width: pg.size.width, spacing: spacing)
                            }
                            .tag(Optional(p.id))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .onAppear { if page != currentPage { page = currentPage } }
                    .overlay(alignment: .bottom) { if pages.count > 1 { pageDots(pages) } }
                }
            }
        }
        .background(DashboardBackground(style: style))
        .onChange(of: page) { old, new in if old != nil, new != nil, old != new { Feedback.shared.play(.tap) } }
        .fontDesign(style.font.design)
        .tint(style.accent.color)
        .environment(\.dashStyle, style)
        .environment(\.colorScheme, style.scheme ?? deviceScheme)
        .sheet(isPresented: $showAdd) { AddTileView(page: dashboard.pages.isEmpty ? nil : currentPage) }
        .sheet(isPresented: $showSettings) { DashboardSettingsView() }
        .sheet(isPresented: $showStyle) {
            StyleEditorView()
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(item: $editTile) { TileEditorView(tile: $0) }
        .alert("Name this page", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") {
                if let r = renaming, let i = model.household.dashboard.pages.firstIndex(where: { $0.id == r.id }) {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { model.household.dashboard.pages[i].name = name }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .onAppear { if needsHome { home.start() } }
    }

    /// One page of tiles, scrolling up and down on its own.
    private func pageView(_ p: DashboardPage, width pageWidth: CGFloat, spacing: CGFloat) -> some View {
        let tiles = dashboard.tiles(onPage: p.id)
        let width = max(100, pageWidth - spacing * 2)
        let cols = DashboardGrid.columns(forWidth: width, minTile: style.density.minTile, spacing: spacing)
        let cell = (width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        return ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                if p.id == dashboard.pageList.first?.id { homeStatus }
                if tiles.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: p.icon).font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("Nothing on “\(p.name)” yet.").font(.headline)
                        Button { page = p.id; editing = true; showAdd = true } label: { Label("Add tiles", systemImage: "plus") }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 60)
                } else {
                    let placed = DashboardGrid.place(tiles.map { (id: $0.id, size: $0.size, row: $0.row, column: $0.column) }, columns: cols)
                    let spots = Dictionary(placed.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    // While editing, two spare rows below the tiles to drag into.
                    let rows = DashboardGrid.rowCount(placed) + (editing ? 2 : 0)
                    ZStack(alignment: .topLeading) {
                        if editing {
                            EmptyCells(columns: cols, rows: rows, cell: cell, spacing: spacing, placed: placed) { r, c in
                                guard let id = dragging else { return false }
                                withAnimation(.spring(duration: 0.3)) {
                                    model.household.dashboard.moveTile(id, toRow: r, column: c, columns: cols)
                                }
                                Feedback.shared.play(.tap)
                                dragging = nil
                                return true
                            }
                        }
                        TileGrid(columns: cols, spacing: spacing, cell: cell, minRows: rows) {
                            ForEach(tiles) { tile in
                                tileCell(tile, spot: spots[tile.id], columns: cols)
                                    .layoutValue(key: TileSizeKey.self, value: tile.size)
                                    .layoutValue(key: TileSpotKey.self, value: spots[tile.id])
                            }
                        }
                    }
                    .animation(.spring(duration: 0.3), value: tiles)
                }
            }
            .padding(.horizontal, spacing)
            .padding(.top, spacing / 2)
            .padding(.bottom, spacing + 30)
        }
        .scrollIndicators(.hidden)
    }

    /// Dots at the bottom, one per page, as on the home screen. Tap one to go there.
    private func pageDots(_ pages: [DashboardPage]) -> some View {
        HStack(spacing: 10) {
            ForEach(pages) { p in
                Circle()
                    .fill(p.id == currentPage ? Color.primary : Color.primary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .onTapGesture { withAnimation(.snappy) { page = p.id } }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 8)
    }

    /// Adds a page and goes to it.
    private func addPage() {
        let id = model.household.dashboard.addPage(named: "")
        withAnimation(.snappy) { page = id }
        // Let the new page be laid out first, then show the add-tile sheet for it.
        Task { try? await Task.sleep(for: .milliseconds(350)); showAdd = true }
    }

    private var needsHome: Bool {
        let kinds: Set<TileKind> = [.accessory, .scene, .room, .group, .camera, .climate, .allOff, .battery, .lightShow, .command]
        return dashboard.tiles.contains { kinds.contains($0.kind) } || !dashboard.routines.isEmpty
    }

    // MARK: Top row

    /// The top row: greeting on the left, the time (and date) in the middle when there's room, buttons on the right.
    private func header(wide: Bool) -> some View {
        let clock = wide && style.headerClock != .off
        return HStack(alignment: .top, spacing: 12) {
            Group {
                if style.showGreeting {
                    TimelineView(.everyMinute) { ctx in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DayText.greeting(hour: Calendar.plate.component(.hour, from: ctx.date), name: model.household.members.first?.name))
                                .font(.system(size: wall ? 34 : 28, weight: .bold))
                                .lineLimit(1).minimumScaleFactor(0.6)
                            let summary = engine.summaryLine(now: ctx.date)
                            if !summary.isEmpty {
                                Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The clock takes its own room in the middle, so the row is as tall as it needs and nothing sits under it.
            if clock { headerClock.layoutPriority(1) }
            controls
                .frame(maxWidth: clock ? .infinity : nil, alignment: .trailing)
        }
    }

    private var headerClock: some View {
        TimelineView(.everyMinute) { ctx in
            VStack(spacing: 0) {
                Text(HeaderClock.timeText(ctx.date, calendar: .plate))
                    .font(.system(size: wall ? 64 : 52, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.snappy, value: HeaderClock.timeText(ctx.date, calendar: .plate))
                if style.headerClock == .timeAndDate {
                    Text(HeaderClock.dateText(ctx.date, calendar: .plate))
                        .font(.title3.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .fixedSize()
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    /// Small buttons that stay out of the way: faint in wall mode until you're editing.
    private var controls: some View {
        HStack(spacing: 16) {
            if editing {
                Button { Feedback.shared.play(.tap); showAdd = true } label: { Label("Add tile", systemImage: "plus") }
                Button { showStyle = true } label: { Label("Colours and sounds", systemImage: "paintbrush") }
                Button { showSettings = true } label: { Label("Dashboard settings", systemImage: "gearshape") }
                Button("Done") { withAnimation { editing = false } }.fontWeight(.semibold)
            } else {
                Button { withAnimation { editing = true } } label: { Label("Edit", systemImage: "pencil") }
                if wall, let onExit {
                    Button { onExit() } label: { Label("Leave wall mode", systemImage: "xmark") }
                } else if !wall {
                    Button { model.showWall = true } label: { Label("Wall mode", systemImage: "rectangle.inset.filled") }
                }
            }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .opacity(editing || !wall ? 1 : 0.55)
    }

    // MARK: Pages

    private var pageBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(dashboard.pageList) { p in
                    let on = p.id == currentPage
                    Button {
                        withAnimation(.snappy) { page = p.id }
                    } label: {
                        Label(p.name, systemImage: p.icon)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(on ? AnyShapeStyle(style.accent.color) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                            .foregroundStyle(on ? (style.accent.wantsDarkText ? Color.black : Color.white) : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !dashboard.pages.isEmpty {
                            Button("Rename", systemImage: "pencil") { newName = p.name; renaming = p }
                            Menu("Icon") {
                                ForEach(["house", "sofa", "bed.double", "fork.knife", "music.note", "lightbulb", "tv", "tram.fill", "leaf", "star", "square.grid.2x2"], id: \.self) { i in
                                    Button { setIcon(p.id, i) } label: { Label(i, systemImage: i) }
                                }
                            }
                            Button("Tidy this page", systemImage: "rectangle.3.group") {
                                    withAnimation(.snappy) { model.household.dashboard.tidyPage(p.id) }
                                }
                            if dashboard.pages.count > 1 {
                                Button("Delete page", systemImage: "trash", role: .destructive) {
                                    withAnimation { model.household.dashboard.removePage(p.id) }
                                }
                            }
                        }
                    }
                }
                if editing {
                    Button { addPage() } label: {
                        Label("New page", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func setIcon(_ id: UUID, _ icon: String) {
        if let i = model.household.dashboard.pages.firstIndex(where: { $0.id == id }) { model.household.dashboard.pages[i].icon = icon }
    }

    // MARK: Tiles

    @ViewBuilder private func tileCell(_ tile: DashboardTile, spot: TilePlacement?, columns: Int) -> some View {
        let base = TileView(tile: tile, editing: editing)
            .opacity(dragging == tile.id ? 0.4 : 1)
        if editing {
            base
                .overlay { Color.clear.contentShape(Rectangle()).onTapGesture { editTile = tile } }
                .overlay(alignment: .topLeading) { EditBadge(tile: tile, edit: { editTile = tile }) }
                .modifier(Jiggle(on: true))
                .onDrag {
                    dragging = tile.id
                    return NSItemProvider(object: tile.id.uuidString as NSString)
                }
                // Dropped on another tile: the two swap places.
                .onDrop(of: [.plainText], delegate: TileDrop(target: tile.id, dragging: $dragging) { from, _ in
                    guard let spot else { return }
                    withAnimation(.spring(duration: 0.3)) {
                        model.household.dashboard.moveTile(from, toRow: spot.row, column: spot.column, columns: columns)
                    }
                    Feedback.shared.play(.tap)
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
            Text("Put your lights, plugs and scenes next to Apple Music albums, timers, the weather, chores and today's meals. "
                 + "Choose the colours, background and sounds. Mount an iPad on the wall and turn on wall mode: after a few "
                 + "minutes it shows your photos, or the album that's playing, and a tap brings the dashboard back.")
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
        tiles.insert(DashboardTile(kind: .timer, title: "Timers"), at: 3)
        tiles.insert(DashboardTile(kind: .allOff, title: "All lights"), at: 4)
        tiles.append(DashboardTile(kind: .command, title: "Type a command"))
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

/// The remove button and the menu on a tile in edit mode.
private struct EditBadge: View {
    let tile: DashboardTile
    let edit: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Button {
                if tile.kind == .wifi { SecretStore.set(SecretStore.wifiAccount(tile.id), nil) }
                withAnimation { model.household.dashboard.remove(tile.id) }
            } label: {
                Image(systemName: "minus.circle.fill").font(.title).symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
            }
            .accessibilityLabel("Remove \(tile.name())")
            Spacer()
            Menu {
                Button("Name, icon, colour…", systemImage: "slider.horizontal.3", action: edit)
                Picker("Size", selection: Binding(get: { tile.size },
                                                  set: { s in withAnimation { model.household.dashboard.resize(tile.id, to: s) } })) {
                    ForEach(TileSize.allCases) { Text($0.title).tag($0) }
                }
                if model.household.dashboard.pages.count > 1 {
                    Menu("Move to page") {
                        ForEach(model.household.dashboard.pages) { p in
                            Button(p.name, systemImage: p.icon) { withAnimation { model.household.dashboard.moveTile(tile.id, toPage: p.id) } }
                        }
                    }
                }
                if tile.kind != .folder, !model.household.dashboard.folders.isEmpty {
                    Menu("Move into folder") {
                        ForEach(model.household.dashboard.folders) { f in
                            Button(f.name("Folder"), systemImage: f.icon ?? "folder") {
                                withAnimation { model.household.dashboard.moveTile(tile.id, toFolder: f.id) }
                            }
                        }
                    }
                }
                if tile.kind.canRepeat {
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        var copy = tile
                        copy.id = UUID()
                        model.household.dashboard.add(copy)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill").font(.title)
                    .symbolRenderingMode(.palette).foregroundStyle(.white, .blue)
            }
            .accessibilityLabel("Change \(tile.name())")
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

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        defer { dragging = nil }
        guard let dragging, dragging != target else { return false }
        move(dragging, target)
        return true
    }
}

/// The empty cells of the grid in edit mode, drawn faintly so you can see where a tile can go, and each one a place
/// to drop a tile.
private struct EmptyCells: View {
    let columns: Int
    let rows: Int
    let cell: CGFloat
    let spacing: CGFloat
    let placed: [TilePlacement]
    let drop: (Int, Int) -> Bool

    private struct Cell: Hashable, Identifiable {
        let r: Int
        let c: Int
        var id: String { "\(r),\(c)" }
    }

    var body: some View {
        let free = (0..<rows).flatMap { r in (0..<columns).map { c in Cell(r: r, c: c) } }.filter { cell in
            !placed.contains { $0.row <= cell.r && cell.r < $0.row + $0.rows && $0.column <= cell.c && cell.c < $0.column + $0.columns }
        }
        ZStack(alignment: .topLeading) {
            ForEach(free) { spot in
                DropCell(drop: { drop(spot.r, spot.c) })
                    .frame(width: cell, height: cell)
                    .offset(x: CGFloat(spot.c) * (cell + spacing), y: CGFloat(spot.r) * (cell + spacing))
            }
        }
        .frame(width: CGFloat(columns) * cell + CGFloat(max(0, columns - 1)) * spacing,
               height: CGFloat(rows) * cell + CGFloat(max(0, rows - 1)) * spacing, alignment: .topLeading)
    }
}

private struct DropCell: View {
    let drop: () -> Bool
    @Environment(\.dashStyle) private var style
    @State private var over = false

    var body: some View {
        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
            .foregroundStyle(over ? style.accent.color : Color.primary.opacity(0.15))
            .background(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .fill(over ? style.accent.color.opacity(0.18) : Color.clear))
            .contentShape(Rectangle())
            .onDrop(of: [.plainText], isTargeted: $over) { _ in drop() }
    }
}

// MARK: Grid layout

struct TileSizeKey: LayoutValueKey {
    static let defaultValue: TileSize = .small
}

/// Where the dashboard has placed a tile. Without it (inside a folder, say) tiles flow into the first gaps.
struct TileSpotKey: LayoutValueKey {
    static let defaultValue: TilePlacement? = nil
}

/// Lays tiles out on a grid of square cells using `DashboardGrid.place` (tested in PlateCore).
struct TileGrid: Layout {
    let columns: Int
    let spacing: CGFloat
    let cell: CGFloat
    var minRows = 0

    private func placements(_ subviews: Subviews) -> [TilePlacement] {
        let spots = subviews.map { $0[TileSpotKey.self] }
        if spots.allSatisfy({ $0 != nil }) { return spots.compactMap { $0 } }
        return DashboardGrid.place(subviews.map { (UUID(), $0[TileSizeKey.self]) }, columns: columns)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = CGFloat(max(minRows, DashboardGrid.rowCount(placements(subviews))))
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
