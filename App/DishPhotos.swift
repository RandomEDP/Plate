import PlateCore
import SwiftUI
import UIKit

/// The pictures of dishes: JPEGs in the app group's "DishPhotos" folder, beside the household file. A recipe's
/// `photo` says which file is its own.
enum DishPhotos {
    static var folder: URL { SharedStorage.folder.appendingPathComponent("DishPhotos", isDirectory: true) }

    static func url(_ photo: RecipePhoto) -> URL { folder.appendingPathComponent(photo.file) }

    /// Saves a picture, scaled down so the longest side is 1,600 points at most, and gives its file name.
    static func store(_ data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, 1600 / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        // Drawing it again also turns a sideways camera photo the right way up.
        let jpeg = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.82) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        let name = UUID().uuidString + ".jpg"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try jpeg.write(to: folder.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            print("Plate couldn't save a dish photo: \(error)")
            return nil
        }
    }

    static func remove(_ file: String) {
        cache.removeAllObjects()
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
    }

    /// Deletes pictures no recipe uses any more. Ones made in the last hour are left, in case their recipe is
    /// still being saved.
    static func tidy(_ household: Household) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let old = files.filter {
            let made = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return made < Date().addingTimeInterval(-3600)
        }
        for name in RecipePhoto.orphans(files: old.map(\.lastPathComponent), in: household) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private static let cache = NSCache<NSString, UIImage>()

    /// The picture, shrunk to about the size it's shown at (`side` points) and remembered.
    static func image(_ photo: RecipePhoto, side: CGFloat) -> UIImage? {
        let pixels = Int(side * 3)
        let key = "\(photo.file)@\(pixels)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let full = UIImage(contentsOfFile: url(photo).path) else { return nil }
        let longest = max(full.size.width, full.size.height)
        let scale = min(1, CGFloat(pixels) / max(1, longest))
        let small = scale < 1
            ? (full.preparingThumbnail(of: CGSize(width: full.size.width * scale, height: full.size.height * scale)) ?? full)
            : full
        cache.setObject(small, forKey: key)
        return small
    }

    /// Fetches a post's cover picture. The request carries nothing but the picture's address.
    static func download(_ url: URL) async -> Data? {
        guard url.scheme == "https", let data = try? await CaptionFetcher.get(url, userAgent: CaptionFetcher.browserAgent),
              data.count < 15_000_000, UIImage(data: data) != nil else { return nil }
        return data
    }

    /// A small copy of a frame, measured for choosing the dish still.
    static func stats(of image: CGImage) -> FrameStats {
        let side = 48
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? FrameStats.measure(rgba: bytes, width: side, height: side) : FrameStats(brightness: 0, colour: 0, sharpness: 0)
    }
}

/// A picture found for a recipe that hasn't been saved yet.
struct FoundPhoto {
    var data: Data
    var origin: RecipePhoto.Origin
}

extension AppModel {
    /// Keeps a picture for a recipe until the recipe is saved (`save` picks it up), or puts it straight on a recipe
    /// that's already there. A found picture never takes the place of your own.
    func offer(_ photo: FoundPhoto?, for id: UUID) {
        guard let photo else { return }
        if recipe(id) != nil { setPhoto(photo.data, origin: photo.origin, for: id) }
        else { foundPhotos[id] = photo }
    }

    /// Hands over the picture kept for a recipe that was never saved under that id (a re-import, say).
    func takeFoundPhoto(for id: UUID) -> FoundPhoto? {
        foundPhotos.removeValue(forKey: id)
    }

    /// Fetches a post's cover picture and keeps it for the recipe.
    func offerCover(_ url: URL?, for id: UUID) async {
        guard let url, let data = await DishPhotos.download(url) else { return }
        offer(FoundPhoto(data: data, origin: .post), for: id)
    }

    /// Puts a picture on a saved recipe. False when it wasn't used: the recipe has gone, the picture couldn't be
    /// read, or it would have replaced a better one (your own, or a video still by a post's cover).
    @discardableResult
    func setPhoto(_ data: Data, origin: RecipePhoto.Origin, for id: UUID) -> Bool {
        let old = household.photo(of: id)
        guard recipe(id) != nil, RecipePhoto.shouldReplace(old, with: origin), let file = DishPhotos.store(data) else { return false }
        household.setPhoto(RecipePhoto(file: file, origin: origin), for: id)
        if let old { DishPhotos.remove(old.file) }
        return true
    }

    func removePhoto(for id: UUID) {
        guard let old = household.photo(of: id) else { return }
        household.setPhoto(nil, for: id)
        DishPhotos.remove(old.file)
    }

    func rate(_ recipe: Recipe, stars: Int?) {
        household.rate(recipe.id, stars: stars)
    }

    // MARK: Recipes sent as a link

    /// Opens a recipe someone sent as a Plate link. False when the link isn't one.
    @discardableResult
    func open(sharedLink url: URL) -> Bool {
        guard RecipeShare.code(in: url) != nil else { return false }
        guard let recipe = RecipeShare.recipe(from: url) else {
            banner = "That Plate link is damaged or cut short. Ask for it to be sent again."
            return true
        }
        selectedTab = .recipes
        if let mine = household.copy(of: recipe) {
            banner = "You already have \(mine.name)"
            arrived = mine
        } else {
            arrived = recipe
        }
        return true
    }
}

/// A recipe's picture, filling whatever frame it's given.
struct DishPhotoView: View {
    let photo: RecipePhoto
    var side: CGFloat = 400

    var body: some View {
        if let image = DishPhotos.image(photo, side: side) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Color.secondary.opacity(0.15)
        }
    }
}

/// One to five stars. Tap a star to rate; tap the same one again to take the rating off.
struct StarRating: View {
    let rating: Int?
    let set: (Int?) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { n in
                Button { set(rating == n ? nil : n) } label: {
                    Image(systemName: n <= (rating ?? 0) ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(n <= (rating ?? 0) ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(n) star\(n == 1 ? "" : "s")")
                .accessibilityAddTraits(rating == n ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your rating")
        .accessibilityValue(rating.map { "\($0) out of 5" } ?? "Not rated")
    }
}

/// The camera, for a photo of the dish you've just made.
struct CameraPicker: UIViewControllerRepresentable {
    let onPhoto: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    static var available: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) { parent.onPhoto(data) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
