import Foundation

/// Recognises Instagram and TikTok links and pulls the caption out of what those sites send back.
/// The network calls live in the app; this part is plain text handling so it can be tested.
public enum SocialImport {
    public enum Platform: String, Sendable { case instagram, tiktok, youtube, web }

    /// The first link in some shared text, with which platform it's from.
    public static func link(in text: String) -> (URL, Platform)? {
        var urls: [URL] = []
        if let re = try? NSRegularExpression(pattern: #"https?://[^\s<>"']+"#, options: [.caseInsensitive]) {
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let raw = ns.substring(with: m.range).trimmingCharacters(in: CharacterSet(charactersIn: ".,)!?"))
                if let u = URL(string: raw) { urls.append(u) }
            }
        }
        if urls.isEmpty {
            // "instagram.com/reel/..." pasted without the https.
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.contains(" "), t.contains("."), let u = URL(string: "https://" + t), u.host?.contains(".") == true { urls = [u] }
        }
        for url in urls {
            return (url, platform(of: url))
        }
        return nil
    }

    public static func platform(of url: URL) -> Platform {
        let host = (url.host ?? "").lowercased()
        if host.hasSuffix("instagram.com") || host == "instagr.am" { return .instagram }
        if host.hasSuffix("tiktok.com") { return .tiktok }
        if host.hasSuffix("youtube.com") || host == "youtu.be" { return .youtube }
        return .web
    }

    /// The post's short code from an Instagram link (/reel/ABC123/, /p/ABC123/, /reels/ABC123/).
    public static func instagramCode(_ url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        for (i, p) in parts.enumerated() where ["reel", "reels", "p", "tv"].contains(p) && i + 1 < parts.count {
            return parts[i + 1]
        }
        return nil
    }

    /// TikTok's oEmbed address for a video link. Its "title" is the video's caption.
    public static func tiktokOEmbedURL(for url: URL) -> URL? {
        var c = URLComponents(string: "https://www.tiktok.com/oembed")
        c?.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        return c?.url
    }

    /// Instagram's public embed page, which carries the caption for public posts.
    public static func instagramEmbedURL(for url: URL) -> URL? {
        guard let code = instagramCode(url) else { return nil }
        return URL(string: "https://www.instagram.com/p/\(code)/embed/captioned/")
    }

    public struct Caption: Equatable, Sendable {
        public var text: String
        public var author: String?
        /// The post's cover picture, when the page gave one.
        public var thumbnail: URL? = nil
    }

    /// The cover picture's address from TikTok's oEmbed answer.
    public static func thumbnailFromTikTokOEmbed(_ data: Data) -> URL? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let s = obj["thumbnail_url"] as? String else { return nil }
        return webImage(s)
    }

    /// The cover picture's address from an Instagram page: the embed page's picture, or the link-preview picture.
    public static func thumbnailFromInstagramHTML(_ html: String) -> URL? {
        if let re = try? NSRegularExpression(pattern: #"<img[^>]+class=["'][^"']*EmbeddedMediaImage[^"']*["'][^>]*>"#, options: [.caseInsensitive]),
           let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), let r = Range(m.range, in: html) {
            let tag = String(html[r])
            if let src = try? NSRegularExpression(pattern: #"\ssrc=["']([^"']+)["']"#, options: [.caseInsensitive]),
               let sm = src.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)), let sr = Range(sm.range(at: 1), in: tag),
               let url = webImage(decodeEntities(String(tag[sr]))) {
                return url
            }
        }
        for key in ["og:image", "twitter:image"] {
            if let content = metaContent(html, key: key), let url = webImage(decodeEntities(content)) { return url }
        }
        return nil
    }

    /// Only proper https addresses are fetched.
    static func webImage(_ s: String) -> URL? {
        guard let url = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    public static func captionFromTikTokOEmbed(_ data: Data) -> Caption? {
        if case .caption(let c) = readTikTokOEmbed(data) { return c }
        return nil
    }

    /// What TikTok told us about a post.
    public enum TikTokRead: Equatable, Sendable {
        case caption(Caption)
        /// The post is there but has no caption: the recipe can only be in the video.
        case noCaption(author: String?)
        /// TikTok says the post is private, removed or doesn't exist.
        case unavailable
        /// Nothing usable (a blocked request, a changed page): worth trying another way.
        case unreadable
    }

    /// Reads TikTok's oEmbed answer. Its "title" is the caption; an error answer has a code or message instead.
    public static func readTikTokOEmbed(_ data: Data) -> TikTokRead {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .unreadable }
        let author = (obj["author_name"] as? String) ?? (obj["author_unique_id"] as? String)
        if let title = obj["title"] as? String {
            let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? .noCaption(author: author)
                : .caption(Caption(text: text, author: author, thumbnail: thumbnailFromTikTokOEmbed(data)))
        }
        // {"code":400,"message":"Something went wrong","status_msg":"..."}: oEmbed can't say why, so try the page.
        return .unreadable
    }

    /// True for TikTok's share links (vm.tiktok.com/ZN..., vt.tiktok.com/..., tiktok.com/t/...), which only redirect
    /// to the real post. TikTok's oEmbed often can't read these, so Plate follows the redirect first.
    public static func isTikTokShortLink(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        if host == "vm.tiktok.com" || host == "vt.tiktok.com" { return true }
        return platform(of: url) == .tiktok && url.path.lowercased().hasPrefix("/t/")
    }

    /// The post's number from a TikTok link (/@user/video/123, /@user/photo/123, m.tiktok.com/v/123.html).
    public static func tiktokVideoID(_ url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        for (i, p) in parts.enumerated() where ["video", "photo", "v"].contains(p) && i + 1 < parts.count {
            let id = parts[i + 1].replacingOccurrences(of: ".html", with: "")
            if !id.isEmpty, id.allSatisfy(\.isNumber) { return id }
        }
        if let item = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "item_id" || $0.name == "share_item_id" })?.value,
           !item.isEmpty, item.allSatisfy(\.isNumber) { return item }
        return nil
    }

    /// The plain post address (https://www.tiktok.com/@user/video/123), without the tracking bits a share link
    /// redirects to. Nil when the link doesn't name a post.
    public static func tiktokPostURL(_ url: URL) -> URL? {
        guard platform(of: url) == .tiktok, let id = tiktokVideoID(url) else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        let user = parts.first(where: { $0.hasPrefix("@") && $0.count > 1 })
        let kind = parts.contains("photo") ? "photo" : "video"
        return URL(string: "https://www.tiktok.com/\(user ?? "@")/\(kind)/\(id)")
    }

    /// Reads a TikTok post page: the data it carries for its own scripts (the caption is "desc"), else the page's
    /// description tags ("… TikTok video from Sam (@sam): "caption". original sound").
    public static func readTikTokPage(_ html: String) -> TikTokRead {
        for id in ["__UNIVERSAL_DATA_FOR_REHYDRATION__", "SIGI_STATE", "__NEXT_DATA__"] {
            guard let json = scriptJSON(html, id: id) else { continue }
            if let detail = find("webapp.video-detail", in: json) as? [String: Any] {
                let code = (detail["statusCode"] as? Int) ?? (detail["statusCode"] as? NSNumber)?.intValue ?? 0
                if code != 0, find("itemStruct", in: detail) == nil { return .unavailable }
            }
            if let item = (find("itemStruct", in: json) as? [String: Any]) ?? firstItem(in: json),
               let desc = item["desc"] as? String {
                let author = (item["author"] as? [String: Any]).flatMap { ($0["nickname"] as? String) ?? ($0["uniqueId"] as? String) }
                    ?? item["author"] as? String
                let text = desc.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? .noCaption(author: author)
                    : .caption(Caption(text: text, author: author, thumbnail: pageImage(html)))
            }
        }
        for key in ["og:description", "description", "twitter:description"] {
            guard let content = metaContent(html, key: key) else { continue }
            var text = decodeEntities(content)
            var author: String?
            if let from = text.range(of: "video from "), let colon = text.range(of: ": ", range: from.upperBound..<text.endIndex) {
                author = String(text[from.upperBound..<colon.lowerBound]).components(separatedBy: " (@").first
                text = String(text[colon.upperBound...])
                if text.hasPrefix("\"") { text.removeFirst() }
                if let lastQuote = text.range(of: "\"", options: .backwards) { text = String(text[..<lastQuote.lowerBound]) }
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // TikTok's own blurb on pages it won't show ("Make Your Day", "TikTok - trends start here").
            if text.count > 10, !text.lowercased().contains("trends start here"), !text.lowercased().hasPrefix("tiktok -") {
                return .caption(Caption(text: text, author: author, thumbnail: pageImage(html)))
            }
        }
        return .unreadable
    }

    /// The link-preview picture of a page (a TikTok post's cover).
    static func pageImage(_ html: String) -> URL? {
        for key in ["og:image", "twitter:image"] {
            if let content = metaContent(html, key: key), let url = webImage(decodeEntities(content)) { return url }
        }
        return nil
    }

    static func scriptJSON(_ html: String, id: String) -> Any? {
        guard let idRange = html.range(of: "id=\"\(id)\""),
              let open = html.range(of: ">", range: idRange.upperBound..<html.endIndex),
              let close = html.range(of: "</script>", range: open.upperBound..<html.endIndex) else { return nil }
        let body = html[open.upperBound..<close.lowerBound]
        return try? JSONSerialization.jsonObject(with: Data(body.utf8))
    }

    /// The first value under `key`, anywhere in some decoded JSON.
    static func find(_ key: String, in json: Any, depth: Int = 0) -> Any? {
        guard depth < 12 else { return nil }
        if let d = json as? [String: Any] {
            if let v = d[key] { return v }
            for v in d.values { if let f = find(key, in: v, depth: depth + 1) { return f } }
        } else if let a = json as? [Any] {
            for v in a { if let f = find(key, in: v, depth: depth + 1) { return f } }
        }
        return nil
    }

    /// The older page layout: "ItemModule": { "123": { "desc": ..., "author": "sam" } }.
    static func firstItem(in json: Any) -> [String: Any]? {
        guard let module = find("ItemModule", in: json) as? [String: Any] else { return nil }
        return module.values.compactMap { $0 as? [String: Any] }.first { $0["desc"] != nil }
    }

    /// Reads the caption from an Instagram embed page, or failing that from the page's description tags.
    public static func captionFromInstagramHTML(_ html: String) -> Caption? {
        // Embed page: <div class="Caption"> <a class="CaptionUsername" ...>user</a> caption text ... <div class="CaptionComments">
        if let r = html.range(of: "class=\"Caption\"") {
            var body = String(html[r.upperBound...])
            if let end = body.range(of: "class=\"CaptionComments\"") ?? body.range(of: "</div>") { body = String(body[..<end.lowerBound]) }
            // Drop a tag left half-open by the cut ("<div ").
            if let lt = body.lastIndex(of: "<"), !body[lt...].contains(">") { body = String(body[..<lt]) }
            var author: String?
            if let u = body.range(of: "class=\"CaptionUsername\""), let close = body[u.upperBound...].range(of: "</a>") {
                let inner = String(body[u.upperBound..<close.lowerBound])
                author = inner.split(separator: ">").last.map { decodeEntities(String($0)) }
                body.removeSubrange(body.startIndex..<close.upperBound)
            }
            let text = htmlToText(body)
            if text.count > 10 { return Caption(text: text, author: author, thumbnail: thumbnailFromInstagramHTML(html)) }
        }
        // Full page: <meta property="og:description" content="123 likes, 4 comments - user on May 1, 2026: &quot;caption&quot;. ">
        for key in ["og:description", "description", "twitter:description"] {
            if let content = metaContent(html, key: key) {
                var text = decodeEntities(content)
                var author: String?
                if let colon = text.range(of: ": \""), text.contains(" on ") {
                    let head = text[..<colon.lowerBound]
                    if let dash = head.range(of: " - ") { author = head[dash.upperBound...].components(separatedBy: " on ").first }
                    text = String(text[colon.upperBound...])
                    if let lastQuote = text.range(of: "\"", options: .backwards) { text = String(text[..<lastQuote.lowerBound]) }
                }
                if text.count > 10 { return Caption(text: text, author: author, thumbnail: thumbnailFromInstagramHTML(html)) }
            }
        }
        return nil
    }

    public static func metaContent(_ html: String, key: String) -> String? {
        let patterns = [
            #"<meta[^>]+(?:property|name)=["']\#(key)["'][^>]+content=["']([^"']*)["']"#,
            #"<meta[^>]+content=["']([^"']*)["'][^>]+(?:property|name)=["']\#(key)["']"#,
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
            let ns = html as NSString
            if let m = re.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) {
                return ns.substring(with: m.range(at: 1))
            }
        }
        return nil
    }

    static func htmlToText(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<br />", with: "\n").replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
        // Drop the remainder of a tag we started inside, then all tags.
        if let gt = s.firstIndex(of: ">"), !s[..<gt].contains("<") { s = String(s[s.index(after: gt)...]) }
        if let re = try? NSRegularExpression(pattern: "<[^>]+>") {
            s = re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
        }
        return decodeEntities(s).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func decodeEntities(_ s: String) -> String {
        var out = s
        let named = ["&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&#064;": "@", "&#x2F;": "/"]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        // Numeric entities (&#128523; &#x1F60B;)
        if let re = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let ns = out as NSString
            var result = ""
            var last = 0
            for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let hex = ns.substring(with: m.range(at: 1)) == "x"
                let num = ns.substring(with: m.range(at: 2))
                if let v = UInt32(num, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(v) { result.unicodeScalars.append(scalar) }
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            out = result
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }
}
