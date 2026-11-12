import AVFoundation
import PlateCore
import Speech
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

    /// The video's words, laid out for the recipe reader. `step` reports what it's doing ("Listening…").
    static func read(_ url: URL, caption: String? = nil, step: @MainActor @escaping (String) -> Void) async throws -> String {
        let asset = AVURLAsset(url: url)
        let duration: Double
        do { duration = try await asset.load(.duration).seconds } catch { throw Failure.unreadable(error.localizedDescription) }
        await step("Reading the text on screen…")
        let frames = await screenText(asset, duration: duration)
        await step("Listening to the video…")
        let speech = (try? await transcribe(asset)) ?? ""
        let text = VideoText.combine(caption: caption, screen: frames, speech: speech)
        guard !text.isEmpty else { throw Failure.nothingFound }
        return text
    }

    // MARK: Text on screen

    static func screenText(_ asset: AVAsset, duration: Double) async -> [[String]] {
        guard duration.isFinite, duration > 0 else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1080, height: 1080)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.3, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.3, preferredTimescale: 600)
        // About one frame a second, and no more than 150 for a long video.
        let count = min(150, max(1, Int(duration)))
        let times = (0..<count).map { CMTime(seconds: duration * (Double($0) + 0.5) / Double(count), preferredTimescale: 600) }
        var frames: [[String]] = []
        for await result in generator.images(for: times) {
            guard let image = try? result.image else { continue }
            frames.append(await Task.detached(priority: .userInitiated) { lines(in: image) }.value)
        }
        return frames
    }

    /// The lines of text in one frame, top to bottom.
    static func lines(in image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-GB", "en-US"]
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let found = (request.results ?? []).compactMap { obs -> (CGRect, String)? in
            guard let best = obs.topCandidates(1).first, best.confidence >= 0.5 else { return nil }
            return (obs.boundingBox, best.string)
        }
        return found.sorted { abs($0.0.midY - $1.0.midY) > 0.02 ? $0.0.midY > $1.0.midY : $0.0.minX < $1.0.minX }.map(\.1)
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
