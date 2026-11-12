import Foundation
import MusicKit
import Observation
import Photos
import UIKit

/// Apple Music for the dashboard: finding albums to pin, playing them on the iPad (AirPlay to a speaker from the
/// Now Playing tile), and the cover of whatever is playing for idle mode. Playing needs an Apple Music subscription.
@MainActor
@Observable
final class MusicStore {
    var status: MusicAuthorization.Status = MusicAuthorization.currentStatus
    var problem: String?
    private var cache: [String: Album] = [:]

    var player: ApplicationMusicPlayer { ApplicationMusicPlayer.shared }

    func authorise() async {
        status = await MusicAuthorization.request()
    }

    /// Albums from the Apple Music catalogue matching a search.
    func search(_ term: String) async -> [Album] {
        guard !term.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        do {
            var request = MusicCatalogSearchRequest(term: term, types: [Album.self])
            request.limit = 25
            let albums = Array(try await request.response().albums)
            for a in albums { cache[a.id.rawValue] = a }
            return albums
        } catch {
            problem = "Couldn't search Apple Music: \(error.localizedDescription)"
            return []
        }
    }

    /// Albums in your own library, newest first as Music lists them.
    func libraryAlbums() async -> [Album] {
        do {
            var request = MusicLibraryRequest<Album>()
            request.limit = 60
            let albums = Array(try await request.response().items)
            for a in albums { cache[a.id.rawValue] = a }
            return albums
        } catch {
            return []
        }
    }

    /// The album a pinned tile points at, from the catalogue or your library.
    func album(_ ref: String) async -> Album? {
        if let a = cache[ref] { return a }
        let id = MusicItemID(ref)
        if let a = try? await MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: id).response().items.first {
            cache[ref] = a
            return a
        }
        var lib = MusicLibraryRequest<Album>()
        lib.filter(matching: \.id, equalTo: id)
        if let a = try? await lib.response().items.first {
            cache[ref] = a
            return a
        }
        return nil
    }

    func play(_ ref: String) async {
        guard let album = await album(ref) else {
            problem = "Couldn't find that album in Apple Music any more. Remove the tile and pin it again."
            return
        }
        do {
            player.queue = [album]
            try await player.play()
        } catch {
            problem = "Couldn't play \(album.title): \(error.localizedDescription). Playing needs an Apple Music subscription."
        }
    }

    func togglePlayPause() async {
        if player.state.playbackStatus == .playing { player.pause() } else { try? await player.play() }
    }
}

/// The iPad's photo library: the albums to choose from, and the pictures in one, for idle mode.
@MainActor
@Observable
final class PhotoStore {
    struct AlbumInfo: Identifiable, Hashable {
        var id: String
        var title: String
        var count: Int
    }

    var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    var canRead: Bool { status == .authorized || status == .limited }

    func authorise() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Your own albums, then Favourites.
    func albums() -> [AlbumInfo] {
        guard canRead else { return [] }
        var out: [AlbumInfo] = []
        let images = PHFetchOptions()
        images.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        func add(_ result: PHFetchResult<PHAssetCollection>) {
            result.enumerateObjects { c, _, _ in
                let n = PHAsset.fetchAssets(in: c, options: images).count
                if n > 0 { out.append(AlbumInfo(id: c.localIdentifier, title: c.localizedTitle ?? "Album", count: n)) }
            }
        }
        add(PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil))
        add(PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumFavorites, options: nil))
        return out
    }

    /// The pictures (not videos) in an album.
    func photoIds(in albumId: String?) -> [String] {
        guard canRead, let albumId,
              let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumId], options: nil).firstObject
        else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        var ids: [String] = []
        PHAsset.fetchAssets(in: album, options: options).enumerateObjects { a, _, _ in ids.append(a.localIdentifier) }
        return ids
    }

    /// A picture at roughly screen size. Pictures kept in iCloud are downloaded first.
    func image(_ id: String, size: CGSize) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        return await withCheckedContinuation { cont in
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                cont.resume(returning: image)
            }
        }
    }
}
