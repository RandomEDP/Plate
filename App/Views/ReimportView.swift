import PlateCore
import SwiftUI

/// Reads chosen recipes again from the links they came from (Osta, Instagram, TikTok) and puts each new reading in
/// place of the old one, keeping it on the meal plan, shopping lists and favourites. One that can't be read is left
/// as it was and marked, so it can be deleted.
struct ReimportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let ids: [UUID]
    @State private var rows: [Row] = []
    @State private var running = false
    @State private var stopRequested = false
    @State private var started = false

    enum RowState: Equatable { case waiting, working, done(String), failed(String), noLink }

    struct Row: Identifiable {
        let id: UUID
        let oldName: String
        let link: URL?
        var state: RowState
    }

    var failedIDs: Set<UUID> { Set(rows.filter { if case .failed = $0.state { return true } else { return false } }.map(\.id)) }
    var doneCount: Int { rows.filter { if case .done = $0.state { return true } else { return false } }.count }
    var waitingCount: Int { rows.filter { $0.state == .waiting }.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if running {
                        HStack { ProgressView(); Text("Reading \(rows.count - waitingCount) of \(rows.count)…") }
                        Button("Stop after this one", role: .destructive) { stopRequested = true }
                    } else if waitingCount > 0 {
                        Button { Task { await run() } } label: {
                            Label("Re-import \(waitingCount) recipe\(waitingCount == 1 ? "" : "s")", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("Updated \(doneCount)\(failedIDs.isEmpty ? "" : ", \(failedIDs.count) couldn't be read").")
                        if !failedIDs.isEmpty {
                            Button("Delete the \(failedIDs.count) that couldn't be read", role: .destructive) {
                                let n = failedIDs.count
                                model.delete(failedIDs)
                                rows.removeAll { failedIDs.contains($0.id) }
                                model.banner = "Deleted \(n) recipe\(n == 1 ? "" : "s")"
                            }
                        }
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                } footer: {
                    Text("Plate reads each recipe again from where it came from and puts it right where the old one was, so it stays on your plan, lists and favourites. Any changes you made to these recipes by hand will be replaced.")
                }
                Section("Recipes") {
                    ForEach(rows) { row in
                        HStack(alignment: .top) {
                            icon(row.state).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                switch row.state {
                                case .done(let name):
                                    Text(name)
                                    if name != row.oldName { Text("was \(row.oldName)").font(.caption).foregroundStyle(.secondary) }
                                case .failed(let why):
                                    Text(row.oldName).lineLimit(1)
                                    Text(why).font(.caption).foregroundStyle(.red)
                                case .noLink:
                                    Text(row.oldName).lineLimit(1).foregroundStyle(.secondary)
                                    Text("No link saved with it, so it can't be read again.").font(.caption).foregroundStyle(.secondary)
                                default:
                                    Text(row.oldName).lineLimit(1).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Re-import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear {
                guard !started else { return }
                started = true
                rows = ids.compactMap { id in
                    guard let r = model.household.recipes.first(where: { $0.id == id }) else { return nil }
                    let link = r.source.url.flatMap(URL.init(string:))
                    return Row(id: id, oldName: r.name, link: link, state: link == nil ? .noLink : .waiting)
                }
            }
        }
    }

    @ViewBuilder func icon(_ state: RowState) -> some View {
        switch state {
        case .waiting: Image(systemName: "circle").foregroundStyle(.secondary)
        case .working: ProgressView()
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .noLink: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }

    func run() async {
        running = true
        stopRequested = false
        defer { running = false }
        for i in rows.indices {
            guard rows[i].state == .waiting, let link = rows[i].link else { continue }
            if stopRequested { break }
            rows[i].state = .working
            do {
                let fresh = try await model.fetchRecipe(link: link)
                if model.household.replaceRecipe(rows[i].id, with: fresh) {
                    rows[i].state = .done(fresh.name)
                } else {
                    rows[i].state = .failed("Deleted while this was running.")
                }
            } catch {
                rows[i].state = .failed(error.localizedDescription)
            }
            // A short pause between pages, so Osta, Instagram and TikTok don't start refusing.
            try? await Task.sleep(for: .milliseconds(1200))
        }
        if doneCount > 0 { model.banner = "Re-imported \(doneCount) recipe\(doneCount == 1 ? "" : "s")" }
    }
}
