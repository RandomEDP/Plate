import Foundation

/// Turns what Plate got from a recipe video (the words on screen, frame by frame, and what was said) into text the
/// recipe reader and the AI can work from. Many Reels and TikToks only give the recipe in the video itself.
public enum VideoText {
    /// Lines on screen that are the app's own furniture or the creator's handle, not recipe.
    static let furniture: Set<String> = [
        "tiktok", "instagram", "reels", "reel", "follow", "like", "share", "save", "comment", "comments", "subscribe",
        "link in bio", "original audio", "more", "see more", "send", "remix", "sound", "for you", "following",
    ]

    /// The same line as Plate compares it: lower case, letters and numbers only, single spaces.
    static func key(_ line: String) -> String {
        line.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ")
    }

    /// The text seen on screen, each line once, in the order it first appeared. A caption usually stays up for several
    /// frames, so the same line turns up again and again (sometimes with a stray full stop); this keeps one.
    public static func screenLines(_ frames: [[String]]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for frame in frames {
            for raw in frame {
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let k = key(line)
                guard k.count >= 2, !furniture.contains(k), !line.hasPrefix("@"), !k.allSatisfy(\.isNumber) || k.count <= 4,
                      !seen.contains(k) else { continue }
                // A line that's just a longer version of one already kept (text typed on screen word by word)
                // replaces it.
                if let i = out.firstIndex(where: { let o = key($0); return !o.isEmpty && k.hasPrefix(o + " ") }) {
                    seen.insert(k)
                    out[i] = line
                    continue
                }
                if out.contains(where: { key($0).hasPrefix(k + " ") }) { seen.insert(k); continue }
                seen.insert(k)
                out.append(line)
            }
        }
        return out
    }

    /// Everything Plate got from the video, laid out for the recipe reader: the caption (if there was one), the text
    /// on screen, then what was said.
    public static func combine(caption: String? = nil, screen frames: [[String]], speech: String) -> String {
        var parts: [String] = []
        if let caption = caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty { parts.append(caption) }
        let lines = screenLines(frames)
        if !lines.isEmpty { parts.append(lines.joined(separator: "\n")) }
        let said = speech.trimmingCharacters(in: .whitespacesAndNewlines)
        if !said.isEmpty { parts.append("What they say in the video:\n" + said) }
        return parts.joined(separator: "\n\n")
    }
}
