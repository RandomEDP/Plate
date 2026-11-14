import PlateCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Save to Plate" in the share sheet. Reads the Reel or TikTok caption, shows what it found and drops the recipe in
/// the app's inbox. The app picks it up the next time it opens.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(context: extensionContext)
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.load() }
    }
}

@MainActor
final class ShareModel: ObservableObject {
    enum Phase {
        case reading, found(Recipe), failed(String), saved, videoSaved, needsVideo(String), waiting
        /// Already in Plate. The fresh reading comes too when there was a recipe in it, so it can update the saved one.
        case duplicate(Recipe?, RecipeDuplicates.Match)
        case updated(String)
    }

    weak var context: NSExtensionContext?
    @Published var phase: Phase = .reading
    var link: String?
    var caption = ""
    var author: String?
    var thumbnail: URL?

    init(context: NSExtensionContext?) { self.context = context }

    func load() async {
        // A video: hand it to the app, which listens to it and reads the text on screen.
        if let video = await sharedVideo() {
            do {
                try VideoInbox.add(video)
                phase = .videoSaved
            } catch {
                phase = .failed("Couldn't save the video: \(error.localizedDescription)")
            }
            return
        }
        let shared = await sharedText()
        guard !shared.isEmpty else {
            phase = .failed("Nothing to read here. Share a Reel or TikTok, or the recipe text.")
            return
        }
        // A recipe someone sent as a Plate link: it's all in the link.
        if let recipe = RecipeShare.recipe(in: shared) {
            phase = .found(recipe)
            return
        }
        var platform: SocialImport.Platform?
        if let (url, p) = SocialImport.link(in: shared), shared.count < url.absoluteString.count + 40 {
            link = url.absoluteString
            do {
                let (c, _, _) = try await CaptionFetcher.fetch(shared)
                caption = c.text; author = c.author; platform = p; thumbnail = c.thumbnail
            } catch {
                // Already saved from this post: say so, rather than asking for the video.
                let bare = Recipe(name: "", mealTypes: [], servings: 1, ingredients: [], steps: [],
                                  source: RecipeSource(kind: p == .tiktok ? .tiktok : p == .instagram ? .instagram : .web, url: link))
                if let match = RecipeDuplicates.match(for: bare, in: SavedRecipes.all()) {
                    phase = .duplicate(nil, match)
                    return
                }
                // The caption couldn't be read (a private post, say), but the recipe may still be in the video.
                if p == .instagram || p == .tiktok {
                    phase = .needsVideo("Couldn't read the post's caption (\(error.localizedDescription)).")
                } else {
                    phase = .failed(error.localizedDescription)
                }
                return
            }
        } else {
            caption = shared
            if let (url, p) = SocialImport.link(in: shared) { link = url.absoluteString; platform = p }
        }
        let kind: RecipeSourceKind = platform == .tiktok ? .tiktok : platform == .instagram ? .instagram : (link == nil ? .manual : .web)
        let recipe = RecipeTextParser.parse(caption).recipe(source: RecipeSource(kind: kind, url: link, author: author))
        if let match = RecipeDuplicates.match(for: recipe, in: SavedRecipes.all()) {
            phase = .duplicate(recipe.ingredients.count >= 2 ? recipe : nil, match)
        } else if recipe.ingredients.count < 2, link != nil {
            phase = .needsVideo("There's no recipe in the caption, so it must be in the video.")
        } else if recipe.ingredients.count < 2 {
            phase = .failed("Couldn't find a recipe in that caption. If the recipe is only in the video, save the video, then share it to Plate (or use Recipes → Import → From a video).")
        } else {
            phase = .found(recipe)
        }
    }

    /// Drops the recipe in the inbox. `replaces` updates a recipe already saved; `keepCopy` saves a second copy on purpose.
    func save(_ recipe: Recipe, replaces existing: Recipe? = nil, keepCopy: Bool = false) {
        do {
            try Inbox.append(PendingImport(link: link, caption: caption, author: author, recipe: recipe,
                                           thumbnail: thumbnail?.absoluteString,
                                           replaces: existing?.id, keepCopy: keepCopy ? true : nil))
            phase = existing.map { .updated($0.name) } ?? .saved
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                self.close()
            }
        } catch {
            phase = .failed("Couldn't save it: \(error.localizedDescription)")
        }
    }

    /// Keeps the link and caption until a recording of the video is added in the app.
    func saveForVideo() {
        guard let link else { return }
        do {
            try WaitingForVideo.add(WaitingVideo(link: link, caption: caption, author: author))
            phase = .waiting
        } catch {
            phase = .failed("Couldn't save it: \(error.localizedDescription)")
        }
    }

    func close() { context?.completeRequest(returningItems: nil) }

    /// A shared video file, copied somewhere this extension can read it.
    private func sharedVideo() async -> URL? {
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        guard let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.movie.identifier) }) else { return nil }
        return await withCheckedContinuation { c in
            _ = p.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                // The file goes away when this returns, so copy it first.
                guard let url else { c.resume(returning: nil); return }
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + (url.pathExtension.isEmpty ? "mov" : url.pathExtension))
                c.resume(returning: (try? FileManager.default.copyItem(at: url, to: copy)) != nil ? copy : nil)
            }
        }
    }

    /// The shared link or text, whichever the app offered.
    private func sharedText() async -> String {
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var texts: [String] = []
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let item = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier),
               let url = item as? URL {
                texts.append(url.absoluteString)
            } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let item = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) {
                if let s = item as? String { texts.append(s) }
                else if let d = item as? Data, let s = String(data: d, encoding: .utf8) { texts.append(s) }
            }
        }
        // Prefer the longest text (a full caption beats a bare link), but keep a link if that's all there is.
        let joined = texts.sorted { $0.count > $1.count }.first ?? ""
        return joined.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .reading:
                    VStack(spacing: 12) { ProgressView(); Text("Reading the recipe…").foregroundStyle(.secondary) }
                case .failed(let message):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                        Text(message).multilineTextAlignment(.center)
                    }
                    .padding()
                case .needsVideo(let why):
                    VStack(spacing: 14) {
                        Image(systemName: "film").font(.largeTitle).foregroundStyle(.orange)
                        Text(why).multilineTextAlignment(.center)
                        Text("Save the link now, then screen-record the video. In Plate, Recipes → Waiting for a video → pick the recording, and Plate reads the caption and the video together.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button { model.saveForVideo() } label: { Label("Save link, add the video later", systemImage: "clock") }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                case .waiting:
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                        Text("Saved. Now screen-record the video (Control Centre → Screen Recording), then open Plate: it's under Recipes → Waiting for a video.")
                            .multilineTextAlignment(.center)
                        Button("Done") { model.close() }.buttonStyle(.borderedProminent)
                    }
                    .padding()
                case .videoSaved:
                    VStack(spacing: 12) {
                        Image(systemName: "film").font(.largeTitle).foregroundStyle(.green)
                        Text("Saved. Open Plate and it'll watch the video for the recipe.").multilineTextAlignment(.center)
                        Button("Done") { model.close() }.buttonStyle(.borderedProminent)
                    }
                    .padding()
                case .duplicate(let fresh, let match):
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(.green)
                        Text(match.message).font(.headline).multilineTextAlignment(.center)
                        Text("It's in Plate under Recipes, so there's no need to save it again.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Done") { model.close() }.buttonStyle(.borderedProminent)
                        if let fresh {
                            Button { model.save(fresh, replaces: match.recipe) } label: {
                                Label("Update it with this version", systemImage: "arrow.triangle.2.circlepath")
                            }
                            Button { model.save(fresh, keepCopy: true) } label: {
                                Label("Save a copy anyway", systemImage: "plus.square.on.square")
                            }
                        }
                    }
                    .padding()
                case .updated(let name):
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                        Text("\(name) will be updated next time you open Plate.").multilineTextAlignment(.center)
                    }
                    .padding()
                case .saved:
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                        Text("Saved. It'll be in Plate next time you open it.").multilineTextAlignment(.center)
                    }
                    .padding()
                case .found(let r):
                    List {
                        Section {
                            Text(r.name).font(.headline)
                            Text("\(r.ingredients.count) ingredients · \(r.steps.count) steps · serves \(r.servings)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Section("Ingredients") {
                            ForEach(r.ingredients) { ing in
                                Text((ing.quantity.map { Format.quantity($0) + " " } ?? "") + ing.name)
                            }
                        }
                        Section {
                            Button { model.save(r) } label: { Label("Save to Plate", systemImage: "checkmark") }
                                .buttonStyle(.borderedProminent)
                        } footer: {
                            Text("You can tidy it up with AI or edit it in the app.")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Save to Plate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.close() } } }
        }
    }
}
