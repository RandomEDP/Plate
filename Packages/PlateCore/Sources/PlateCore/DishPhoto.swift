import Foundation

/// Which picture a recipe has. The picture itself is a JPEG kept beside the household file (in "DishPhotos"), so the
/// household file stays small and easy to sync.
public struct RecipePhoto: Codable, Hashable, Sendable {
    public enum Origin: String, Codable, Sendable {
        /// The cover picture of the Instagram, TikTok or Osta post.
        case post
        /// A still Plate took from the video, near the end where the finished dish usually is.
        case video
        /// Your own photo of the dish.
        case own

        /// Higher wins when Plate finds a picture by itself: it never swaps your own photo for one it found.
        var rank: Int { self == .own ? 2 : self == .video ? 1 : 0 }

        public init(from decoder: Decoder) throws {
            self = Origin(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .post
        }
    }

    /// The file's name in the photos folder.
    public var file: String
    public var origin: Origin
    public var updatedAt: Date

    public init(file: String, origin: Origin, updatedAt: Date = Date()) {
        self.file = file; self.origin = origin; self.updatedAt = updatedAt
    }

    /// Whether a picture Plate has just found (or you have just chosen) should take the place of the one there.
    /// Your own photo always goes in. A found one never replaces your own, and a post's cover never replaces a
    /// still from the video.
    public static func shouldReplace(_ existing: RecipePhoto?, with origin: Origin) -> Bool {
        guard let existing else { return true }
        return origin.rank >= existing.origin.rank
    }

    /// Picture files that no recipe uses any more (their recipes were deleted, or the picture was replaced).
    public static func orphans(files: [String], in household: Household) -> [String] {
        let used = household.photoFiles
        return files.filter { !used.contains($0) }
    }
}

extension Household {
    static let builtInRatingsKey = "builtInRatings"
    static let builtInPhotosKey = "builtInPhotos"

    /// "id:value,id:value" in `extras`, for things kept about built-in recipes (which themselves never change).
    func builtInMap(_ key: String) -> [UUID: String] {
        var out: [UUID: String] = [:]
        for pair in (extras[key] ?? "").split(separator: ",") {
            guard let colon = pair.firstIndex(of: ":"), let id = UUID(uuidString: String(pair[..<colon])) else { continue }
            out[id] = String(pair[pair.index(after: colon)...])
        }
        return out
    }

    mutating func setBuiltInMap(_ key: String, _ map: [UUID: String]) {
        extras[key] = map.map { "\($0.key.uuidString):\($0.value)" }.sorted().joined(separator: ",")
    }

    /// A built-in recipe with your rating and photo on it.
    public func dressed(_ builtIn: Recipe) -> Recipe {
        var r = builtIn
        if let stars = builtInMap(Household.builtInRatingsKey)[r.id].flatMap(Int.init) { r.rating = stars }
        if let value = builtInMap(Household.builtInPhotosKey)[r.id] {
            // "own|file.jpg"
            let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2 { r.photo = RecipePhoto(file: parts[1], origin: RecipePhoto.Origin(rawValue: parts[0]) ?? .own) }
        }
        return r
    }

    /// Rates a recipe from one to five stars; nil (or anything outside that) takes the rating off.
    /// False when there's no such recipe.
    @discardableResult
    public mutating func rate(_ id: UUID, stars: Int?) -> Bool {
        let stars = stars.flatMap { (1...5).contains($0) ? $0 : nil }
        if let i = recipes.firstIndex(where: { $0.id == id }) {
            recipes[i].rating = stars
            recipes[i].updatedAt = Date()
        } else if BuiltInRecipes.all.contains(where: { $0.id == id }) {
            var map = builtInMap(Household.builtInRatingsKey)
            map[id] = stars.map(String.init)
            setBuiltInMap(Household.builtInRatingsKey, map)
        } else {
            return false
        }
        updatedAt = Date()
        return true
    }

    /// The picture a recipe has now, yours or a built-in one's.
    public func photo(of id: UUID) -> RecipePhoto? {
        if let r = recipes.first(where: { $0.id == id }) { return r.photo }
        return BuiltInRecipes.all.first { $0.id == id }.flatMap { dressed($0).photo }
    }

    /// Gives a recipe a picture, or takes it away with nil. False when there's no such recipe. This doesn't weigh
    /// one picture against another: ask `RecipePhoto.shouldReplace` first for pictures Plate found by itself.
    @discardableResult
    public mutating func setPhoto(_ photo: RecipePhoto?, for id: UUID) -> Bool {
        if let i = recipes.firstIndex(where: { $0.id == id }) {
            recipes[i].photo = photo
            recipes[i].updatedAt = Date()
        } else if BuiltInRecipes.all.contains(where: { $0.id == id }) {
            var map = builtInMap(Household.builtInPhotosKey)
            map[id] = photo.map { "\($0.origin.rawValue)|\($0.file)" }
            setBuiltInMap(Household.builtInPhotosKey, map)
        } else {
            return false
        }
        updatedAt = Date()
        return true
    }

    /// Every picture file a recipe points at.
    public var photoFiles: Set<String> {
        var files = Set(recipes.compactMap { $0.photo?.file })
        for value in builtInMap(Household.builtInPhotosKey).values {
            if let bar = value.firstIndex(of: "|") { files.insert(String(value[value.index(after: bar)...])) }
        }
        return files
    }
}

/// Choosing the still of the finished dish from a recipe video.
public enum DishFrame {
    /// One frame Plate looked at. Everything but the time runs from 0 to 1.
    public struct Candidate: Equatable, Sendable {
        /// Seconds from the start.
        public var time: Double
        /// How much of the frame is covered by writing (captions, "follow for more" cards).
        public var textArea: Double
        public var brightness: Double
        public var colour: Double
        public var sharpness: Double

        public init(time: Double, textArea: Double, brightness: Double, colour: Double, sharpness: Double) {
            self.time = time; self.textArea = textArea; self.brightness = brightness; self.colour = colour; self.sharpness = sharpness
        }

        public init(time: Double, textArea: Double, stats: FrameStats) {
            self.init(time: time, textArea: textArea, brightness: stats.brightness, colour: stats.colour, sharpness: stats.sharpness)
        }
    }

    /// How good a frame looks as the recipe's picture. The finished dish is usually at the end, so later frames
    /// score more (nothing for the first half, full marks from four fifths of the way through). Colourful, crisp
    /// frames do better; frames covered in writing, and black or white ones (fades and end cards), do worse.
    public static func score(_ c: Candidate, duration: Double) -> Double {
        let position = duration > 0 ? min(1, max(0, c.time / duration)) : 1
        var s = min(1, max(0, (position - 0.5) / 0.3)) * 2
        s += min(0.6, max(0, c.colour)) * 1.5
        s += min(1, max(0, c.sharpness))
        s -= min(0.5, max(0, c.textArea)) * 6
        if c.brightness < 0.12 || c.brightness > 0.92 { s -= 3 }
        return s
    }

    /// The best frame for the picture, or nil when there were none. Equal scores go to the later frame.
    public static func pick(_ candidates: [Candidate], duration: Double) -> Candidate? {
        var best: (Candidate, Double)?
        for c in candidates.sorted(by: { $0.time < $1.time }) {
            let s = score(c, duration: duration)
            if best == nil || s >= best!.1 { best = (c, s) }
        }
        return best?.0
    }
}

/// A rough measure of how a picture looks, from a small copy of it.
public struct FrameStats: Equatable, Sendable {
    /// 0 is black, 1 is white.
    public var brightness: Double
    /// 0 is grey, 1 is as vivid as it gets.
    public var colour: Double
    /// How much fine detail there is: 0 is flat or blurred.
    public var sharpness: Double

    public init(brightness: Double, colour: Double, sharpness: Double) {
        self.brightness = brightness; self.colour = colour; self.sharpness = sharpness
    }

    /// Measures a picture given as red, green, blue and alpha bytes, row by row. A 48 by 48 copy is plenty.
    public static func measure(rgba: [UInt8], width: Int, height: Int) -> FrameStats {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else {
            return FrameStats(brightness: 0, colour: 0, sharpness: 0)
        }
        var luma = [Double](repeating: 0, count: width * height)
        var bright = 0.0, colour = 0.0
        for i in 0..<(width * height) {
            let r = Double(rgba[i * 4]) / 255, g = Double(rgba[i * 4 + 1]) / 255, b = Double(rgba[i * 4 + 2]) / 255
            let l = 0.299 * r + 0.587 * g + 0.114 * b
            luma[i] = l
            bright += l
            colour += max(r, g, b) - min(r, g, b)
        }
        // Detail: how much each pixel differs from the one to its right and the one below.
        var edges = 0.0, pairs = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let here = luma[y * width + x]
                if x + 1 < width { edges += abs(here - luma[y * width + x + 1]); pairs += 1 }
                if y + 1 < height { edges += abs(here - luma[(y + 1) * width + x]); pairs += 1 }
            }
        }
        let n = Double(width * height)
        return FrameStats(brightness: bright / n, colour: colour / n,
                          sharpness: pairs > 0 ? min(1, edges / pairs * 8) : 0)
    }
}
