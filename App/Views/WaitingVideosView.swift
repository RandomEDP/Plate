import PhotosUI
import PlateCore
import SwiftUI

/// Reels and TikToks shared to Plate whose recipe is only in the video. Pick the screen recording for each one and
/// Plate reads the post's caption and the video together, keeping the link with the recipe.
struct WaitingVideosView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var target: WaitingVideo?
    @State private var picking = false
    @State private var item: PhotosPickerItem?
    @State private var working: UUID?
    @State private var step = ""
    @State private var failures: [UUID: String] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.waitingVideos) { w in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title(w)).lineLimit(2)
                            Text(w.link).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if working == w.id {
                                HStack { ProgressView(); Text(step).font(.caption).foregroundStyle(.secondary) }
                            } else {
                                if let why = failures[w.id] { Text(why).font(.caption).foregroundStyle(.red) }
                                HStack {
                                    Button { target = w; picking = true } label: { Label("Pick the video", systemImage: "film") }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(working != nil)
                                    if let url = URL(string: w.link) {
                                        Link(destination: url) { Label("Open post", systemImage: "arrow.up.right.square") }
                                            .buttonStyle(.bordered)
                                    }
                                }
                                .font(.callout)
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions {
                            Button("Remove", role: .destructive) { remove(w) }
                        }
                    }
                    if model.waitingVideos.isEmpty {
                        Text("Nothing waiting.").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Screen-record each video (Control Centre → Screen Recording), then pick the recording here. Newest videos are at the top of the picker.")
                }
            }
            .navigationTitle("Waiting for a video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .photosPicker(isPresented: $picking, selection: $item, matching: .videos)
            .onChange(of: item) { _, picked in
                guard let picked, let w = target else { return }
                item = nil
                Task { await read(picked, for: w) }
            }
            .onAppear { model.waitingVideos = WaitingForVideo.all() }
        }
    }

    func title(_ w: WaitingVideo) -> String {
        let first = w.caption.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        if !first.isEmpty { return first }
        return w.author.map { "Post by \($0)" } ?? "Saved post"
    }

    func read(_ picked: PhotosPickerItem, for w: WaitingVideo) async {
        working = w.id
        failures[w.id] = nil
        step = "Opening the video…"
        defer { working = nil }
        do {
            guard let video = try await picked.loadTransferable(type: PickedVideo.self) else {
                throw VideoReader.Failure.unreadable("Photos didn't hand it over")
            }
            defer { try? FileManager.default.removeItem(at: video.url) }
            let recipe = try await model.recipeFromVideo(video.url, caption: w.caption.isEmpty ? nil : w.caption,
                                                         link: w.link, author: w.author) { step = $0 }
            model.save(recipe)
            remove(w)
            model.banner = "Saved \(recipe.name)"
        } catch {
            failures[w.id] = error.localizedDescription
        }
    }

    func remove(_ w: WaitingVideo) {
        WaitingForVideo.remove(w.id)
        model.waitingVideos = WaitingForVideo.all()
    }
}
