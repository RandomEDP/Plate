import Foundation
import PlateCore

/// Where Plate keeps its files. The app and the "Save to Plate" share extension both use the app group's folder, so a
/// recipe saved from Instagram or TikTok is waiting in the app the next time it opens.
enum SharedStorage {
    static let appGroup = "group.com.randomedp.plate.share"

    static var folder: URL {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return group
        }
        // Without the app group (e.g. an unsigned simulator build) fall back to the app's own documents.
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var householdURL: URL { folder.appendingPathComponent("household.json") }
    static var inboxURL: URL { folder.appendingPathComponent("inbox.json") }
}

/// A recipe saved from the share sheet, waiting for the app to pick it up.
struct PendingImport: Codable, Identifiable {
    var id = UUID()
    var savedAt = Date()
    var link: String?
    var caption: String
    var author: String?
    var recipe: Recipe?
}

enum Inbox {
    static func read() -> [PendingImport] {
        guard let data = try? Data(contentsOf: SharedStorage.inboxURL) else { return [] }
        return (try? JSONDecoder.plate.decode([PendingImport].self, from: data)) ?? []
    }

    static func append(_ item: PendingImport) throws {
        var items = read()
        items.append(item)
        try JSONEncoder.plate.encode(items).write(to: SharedStorage.inboxURL, options: .atomic)
    }

    /// Takes everything waiting and empties the inbox.
    static func takeAll() -> [PendingImport] {
        let items = read()
        if !items.isEmpty { try? FileManager.default.removeItem(at: SharedStorage.inboxURL) }
        return items
    }
}

extension JSONEncoder {
    static var plate: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var plate: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
