import PlateCore
import SwiftUI

/// Paste a whole list of Reel and TikTok links (or several captions split by "---") and import them all in one go.
struct BulkImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var rows: [Row] = []
    @State private var alreadySaved = 0
    @State private var running = false
    @State private var stopRequested = false

    enum RowState: Equatable {
        case waiting, working, saved(String), failed(String), expanded(Int)
    }

    struct Row: Identifiable {
        let id = UUID()
        let item: BulkImport.Item
        var state: RowState = .waiting

        var title: String {
            switch item {
            case .link(let url, _) where OstaImport.kind(of: url) != nil:
                if case .folder? = OstaImport.kind(of: url) { return "Osta folder" }
                return "Osta · \(url.lastPathComponent)"
            case .link(let url, let platform):
                let name = platform == .instagram ? "Instagram" : platform == .tiktok ? "TikTok" : (url.host ?? "Link")
                return "\(name) · \(url.path)"
            case .caption(let text, _):
                return text.split(separator: "\n").first.map(String.init) ?? "Recipe text"
            }
        }
    }

    var savedCount: Int { rows.filter { if case .saved = $0.state { return true } else { return false } }.count }
    var failedCount: Int { rows.filter { if case .failed = $0.state { return true } else { return false } }.count }
    var waitingCount: Int { rows.filter { $0.state == .waiting }.count }

    var body: some View {
        NavigationStack {
            Form {
                if rows.isEmpty {
                    Section {
                        TextField("Paste links or recipes here", text: $input, axis: .vertical)
                            .lineLimit(6...14)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        PasteButton(payloadType: String.self) { strings in
                            input = strings.joined(separator: "\n")
                            find()
                        }
                        Button { find() } label: { Label("Find the recipes", systemImage: "list.bullet.rectangle") }
                            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } footer: {
                        Text("Paste as many Instagram, TikTok or Osta links as you like, one per line (words around them are fine). An Osta folder link brings in every recipe in the folder. To paste several recipes as text, put a line of --- between each one. Recipes you've already saved are skipped.")
                    }
                } else {
                    Section {
                        if running {
                            HStack { ProgressView(); Text("Importing \(rows.count - waitingCount) of \(rows.count)…") }
                            Button("Stop after this one", role: .destructive) { stopRequested = true }
                        } else if waitingCount > 0 {
                            Button { Task { await run() } } label: {
                                Label("Import \(waitingCount) recipe\(waitingCount == 1 ? "" : "s")", systemImage: "square.and.arrow.down.on.square")
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Start again") { rows = []; alreadySaved = 0 }
                        } else {
                            Text("Saved \(savedCount)\(failedCount > 0 ? ", \(failedCount) couldn't be read" : "").")
                            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                        }
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            if alreadySaved > 0 { Text("\(alreadySaved) already in your recipes, so left out.") }
                            Text("Plate reads one post at a time, so a long list takes a few minutes. You can close this and it carries on.")
                        }
                    }
                    Section("Recipes") {
                        ForEach(rows) { row in
                            HStack(alignment: .top) {
                                icon(row.state).frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    switch row.state {
                                    case .saved(let name):
                                        Text(name)
                                    case .expanded(let n):
                                        Text(row.title)
                                        Text("Found \(n) new recipe\(n == 1 ? "" : "s") in it").font(.caption).foregroundStyle(.secondary)
                                    case .failed(let why):
                                        Text(row.title).lineLimit(1)
                                        Text(why).font(.caption).foregroundStyle(.red)
                                    default:
                                        Text(row.title).lineLimit(1).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import many")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    @ViewBuilder func icon(_ state: RowState) -> some View {
        switch state {
        case .waiting: Image(systemName: "circle").foregroundStyle(.secondary)
        case .working: ProgressView()
        case .saved: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .expanded: Image(systemName: "folder.fill").foregroundStyle(.secondary)
        }
    }

    func find() {
        let items = BulkImport.items(in: input)
        let fresh = BulkImport.notYetImported(items, existingLinks: model.recipes.compactMap { $0.source.url })
        alreadySaved = items.count - fresh.count
        rows = fresh.map { Row(item: $0) }
        if items.isEmpty {
            model.banner = "Couldn't find any links or recipes in that. Paste Instagram or TikTok links, one per line."
        }
    }

    func run() async {
        running = true
        stopRequested = false
        defer { running = false }
        var i = 0
        while i < rows.count {
            defer { i += 1 }
            guard rows[i].state == .waiting else { continue }
            if stopRequested { break }
            rows[i].state = .working
            if let url = rows[i].item.link, case .folder? = OstaImport.kind(of: url) {
                // A shared Osta folder: list its recipes, and import each one after it.
                do {
                    let links = try await OstaReader.folder(url)
                    let items = links.map { BulkImport.Item.link($0, .web) }
                    let have = model.recipes.compactMap { $0.source.url } + rows.compactMap { $0.item.link?.absoluteString }
                    let fresh = BulkImport.notYetImported(items, existingLinks: have)
                    alreadySaved += items.count - fresh.count
                    rows.insert(contentsOf: fresh.map { Row(item: $0) }, at: i + 1)
                    rows[i].state = .expanded(fresh.count)
                } catch {
                    rows[i].state = .failed(error.localizedDescription)
                }
                continue
            }
            rows[i].state = await importOne(rows[i].item)
            // A short pause between posts, so Instagram, TikTok and Osta don't start refusing.
            if rows[i].item.isLink { try? await Task.sleep(for: .milliseconds(1200)) }
        }
        if savedCount > 0 { model.banner = "Imported \(savedCount) recipe\(savedCount == 1 ? "" : "s")" }
    }

    func importOne(_ item: BulkImport.Item) async -> RowState {
        let link = item.link
        let platform = link.map(SocialImport.platform(of:))
        var caption: String
        var author: String?
        switch item {
        case .link(let url, _) where OstaImport.kind(of: url) != nil:
            do {
                let page = try await OstaReader.recipe(url)
                caption = page.caption
                author = page.author
            } catch {
                return .failed(error.localizedDescription)
            }
        case .link(let url, _):
            do {
                let (c, _, _) = try await CaptionFetcher.fetch(url.absoluteString)
                caption = c.text
                author = c.author
            } catch {
                return .failed(error.localizedDescription)
            }
        case .caption(let text, _):
            caption = text
        }
        guard let (recipe, _) = await model.readRecipe(caption: caption, link: link?.absoluteString, author: author, platform: platform) else {
            return .failed("No recipe in the caption. It may only be in the video; type it in with Recipes → ✎.")
        }
        model.save(recipe)
        return .saved(recipe.name)
    }
}

extension BulkImport.Item {
    var isLink: Bool { if case .link = self { return true } else { return false } }
}
