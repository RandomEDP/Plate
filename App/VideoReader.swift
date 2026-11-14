import AVFoundation
import PlateCore
import Speech
import UIKit
import Vision

/// Reads a recipe video on the phone: what's said (Apple's speech recognition, on the device where it can) and the
/// text on screen (Vision, about one frame a second). Nothing leaves the phone, except that speech recognition may
/// use Apple's servers on a phone that can't do it on its own.
enum VideoReader {
    enum Failure: LocalizedError {
        case nothingFound
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .nothingFound:
                return "Couldn't hear or see a recipe in that video. Check it has sound, or type the recipe in with Recipes → ✎."
            case .unreadable(let why):
                return "Couldn't open that video (\(why)). Try saving it again, or pick another."
            }
        }
    }

    /// What a video gave: its words, laid out for the recipe reader, and a still of the finished dish.
    struct Reading {
        var text: String
        var dish: FoundPhoto?
    }

    /// Reads the video. `step` reports what it's doing ("Listening…").
    static func read(_ url: URL, caption: String? = nil, step: @MainActor @escaping (String) -> Void) async throws -> Reading {
        let asset = AVURLAsset(url: url)
        let duration: Double
        do { duration = try await asset.load(.duration).seconds } catch { throw Failure.unreadable(error.localizedDescription) }
        await step("Reading the text on screen…")
        let (frames, looks) = await screenText(asset, duration: duration)
        await step("Listening to the video…")
        let speech = (try? await transcribe(asset)) ?? ""
        let text = VideoText.combine(caption: caption, screen: frames, speech: speech)
        guard !text.isEmpty else { throw Failure.nothingFound }
        await step("Finding a picture of the dish…")
        return Reading(text: text, dish: await dishStill(asset, from: looks, duration: duration))
    }

    // MARK: The dish's picture

    /// A still of the finished dish: the best-looking frame near the end (see `DishFrame` in PlateCore), taken again
    /// at a good size.
    static func dishStill(_ asset: AVAsset, from looks: [DishFrame.Candidate], duration: Double) async -> FoundPhoto? {
        guard let best = DishFrame.pick(looks, duration: duration) else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let image = try? await generator.image(at: CMTime(seconds: best.time, preferredTimescale: 600)).image,
              let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else { return nil }
        return FoundPhoto(data: data, origin: .video)
    }

    // MARK: Text on screen

    /// The lines of text in each frame, and how each frame looks (for choosing the dish's picture).
    static func screenText(_ asset: AVAsset, duration: Double) async -> ([[String]], [DishFrame.Candidate]) {
        guard duration.isFinite, duration > 0 else { return ([], []) }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1080, height: 1080)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.3, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.3, preferredTimescale: 600)
        // About one frame a second, and no more than 150 for a long video.
        let count = min(150, max(1, Int(duration)))
        let times = (0..<count).map { CMTime(seconds: duration * (Double($0) + 0.5) / Double(count), preferredTimescale: 600) }
        var frames: [[String]] = []
        var looks: [DishFrame.Candidate] = []
        for await result in generator.images(for: times) {
            guard let image = try? result.image else { continue }
            let time = result.requestedTime.seconds
            let (lines, look) = await Task.detached(priority: .userInitiated) { () -> ([String], DishFrame.Candidate) in
                let (lines, textArea) = text(in: image)
                return (lines, DishFrame.Candidate(time: time, textArea: textArea, stats: DishPhotos.stats(of: image)))
            }.value
            frames.append(lines)
            looks.append(look)
        }
        return (frames, looks)
    }

    /// The lines of text in one frame, top to bottom.
    static func lines(in image: CGImage) -> [String] { text(in: image).0 }

    /// The lines of text in one frame, top to bottom, and how much of the frame the writing covers (0 to 1).
    static func text(in image: CGImage) -> ([String], Double) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-GB", "en-US"]
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let found = (request.results ?? []).compactMap { obs -> (CGRect, String)? in
            guard let best = obs.topCandidates(1).first, best.confidence >= 0.5 else { return nil }
            return (obs.boundingBox, best.string)
        }
        let area = found.reduce(0.0) { $0 + Double($1.0.width * $1.0.height) }
        return (found.sorted { abs($0.0.midY - $1.0.midY) > 0.02 ? $0.0.midY > $1.0.midY : $0.0.minX < $1.0.minX }.map(\.1), min(1, area))
    }

    // MARK: Speech

    static func transcribe(_ asset: AVAsset) async throws -> String {
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else { return "" }
        guard await authorised(), let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB")) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else { return "" }
        // Speech recognition reads audio files, so take the sound out of the video first.
        let audio = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: audio) }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return "" }
        try await export.export(to: audio, as: .m4a)

        let request = SFSpeechURLRecognitionRequest(url: audio)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        return try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    once.run { continuation.resume(returning: result.bestTranscription.formattedString) }
                } else if let error {
                    once.run { continuation.resume(throwing: error) }
                }
            }
        }
    }

    static func authorised() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { c in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }

    /// Makes sure a continuation is resumed only once, whatever the recogniser calls back with.
    final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func run(_ body: () -> Void) {
            lock.lock(); defer { lock.unlock() }
            guard !done else { return }
            done = true
            body()
        }
    }
}
