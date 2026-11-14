import Foundation
import PlateCore

/// Gets the caption (where creators put the recipe) for an Instagram Reel or TikTok link.
enum CaptionFetcher {
    enum Failure: LocalizedError {
        case notALink
        case unsupported
        case noCaption(SocialImport.Platform)
        /// The post has no caption at all, so the recipe is only in the video.
        case emptyCaption(SocialImport.Platform)
        /// The site said the post is private or gone.
        case unavailable(SocialImport.Platform)
        case network(String)

        var errorDescription: String? {
            switch self {
            case .notALink:
                return "That doesn't look like a link. Paste the Reel or TikTok link, or paste the caption itself."
            case .unsupported:
                return "Plate can read Instagram and TikTok links. For anything else, paste the recipe text."
            case .noCaption(let p):
                let app = p == .instagram ? "Instagram" : "TikTok"
                return "Plate couldn't read this post's caption from \(app) just now. Try again in a minute. If it still won't come through, open the post in \(app), tap the caption to expand it, copy it and paste it here."
            case .emptyCaption(let p):
                let app = p == .instagram ? "Instagram" : "TikTok"
                return "This \(app) post has no caption, so the recipe must be in the video. Save a screen recording of it, then use Import → From a video."
            case .unavailable(let p):
                let app = p == .instagram ? "Instagram" : "TikTok"
                return "\(app) says this post is private or has been taken down, so Plate can't read it. If you can see it in \(app), copy the caption and paste it here."
            case .network(let m):
                return "Couldn't reach the internet to read the post (\(m)). Check your connection, or paste the caption instead."
            }
        }
    }

    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.httpAdditionalHeaders = ["Accept-Language": "en-GB,en;q=0.9"]
        return URLSession(configuration: c)
    }()

    static func fetch(_ text: String) async throws -> (SocialImport.Caption, URL, SocialImport.Platform) {
        guard let (url, platform) = SocialImport.link(in: text) else { throw Failure.notALink }
        switch platform {
        case .tiktok:
            return (try await tiktok(url), url, platform)
        case .instagram:
            return (try await instagram(url), url, platform)
        case .youtube, .web:
            throw Failure.unsupported
        }
    }

    static func get(_ url: URL, userAgent: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw Failure.network("the site answered \(http.statusCode)")
            }
            return data
        } catch let f as Failure {
            throw f
        } catch {
            throw Failure.network(error.localizedDescription)
        }
    }

    static let browserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    static let previewAgent = "facebookexternalhit/1.1"

    /// TikTok: share links (vm.tiktok.com/…) are followed to the post first, because oEmbed often can't read them.
    /// Then oEmbed, then the post's own page. Only a clear answer from TikTok is reported as private or captionless.
    static func tiktok(_ url: URL) async throws -> SocialImport.Caption {
        var post = SocialImport.tiktokPostURL(url)
        var networkError: Failure?
        if post == nil {
            do {
                post = try await resolveTikTok(url)
            } catch let f as Failure {
                networkError = f
            }
        }
        var heard: [SocialImport.TikTokRead] = []
        // oEmbed with the plain post address, then the link as shared in case TikTok prefers that.
        var candidates: [URL] = []
        for u in [post, url].compactMap({ $0 }) where !candidates.contains(u) { candidates.append(u) }
        for candidate in candidates {
            guard let oembed = SocialImport.tiktokOEmbedURL(for: candidate) else { continue }
            do {
                let read = SocialImport.readTikTokOEmbed(try await getAnyStatus(oembed, userAgent: browserAgent))
                if case .caption(let c) = read { return c }
                heard.append(read)
            } catch let f as Failure {
                networkError = f
            }
        }
        // The post page itself, as a phone browser and then as a link preview sees it.
        if let page = post ?? (networkError == nil ? url : nil) {
            for agent in [browserAgent, previewAgent] {
                do {
                    let data = try await get(page, userAgent: agent)
                    let read = SocialImport.readTikTokPage(String(decoding: data, as: UTF8.self))
                    if case .caption(let c) = read { return c }
                    heard.append(read)
                } catch let f as Failure {
                    networkError = f
                }
            }
        }
        if heard.contains(where: { if case .noCaption = $0 { return true } else { return false } }) {
            throw Failure.emptyCaption(.tiktok)
        }
        if heard.contains(.unavailable) { throw Failure.unavailable(.tiktok) }
        if heard.isEmpty, let networkError { throw networkError }
        throw Failure.noCaption(.tiktok)
    }

    /// Follows a TikTok share link to the post it points at.
    static func resolveTikTok(_ url: URL) async throws -> URL? {
        var req = URLRequest(url: url)
        req.setValue(browserAgent, forHTTPHeaderField: "User-Agent")
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: req)
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        let (data, response) = result
        if let final = response.url, let post = SocialImport.tiktokPostURL(final) { return post }
        // Some redirects land on a page that names the post only in its canonical link.
        let html = String(decoding: data, as: UTF8.self)
        for key in ["og:url"] {
            if let u = SocialImport.metaContent(html, key: key).flatMap(URL.init(string:)),
               let post = SocialImport.tiktokPostURL(u) { return post }
        }
        return nil
    }

    /// Like `get`, but an error status still returns the body (oEmbed explains itself in JSON).
    static func getAnyStatus(_ url: URL, userAgent: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            return try await session.data(for: req).0
        } catch {
            throw Failure.network(error.localizedDescription)
        }
    }

    static func instagram(_ url: URL) async throws -> SocialImport.Caption {
        // Share links (instagram.com/share/...) redirect to the post first.
        var postURL = url
        if SocialImport.instagramCode(url) == nil {
            var req = URLRequest(url: url)
            req.setValue(browserAgent, forHTTPHeaderField: "User-Agent")
            if let (_, response) = try? await session.data(for: req), let final = response.url { postURL = final }
        }
        if let embed = SocialImport.instagramEmbedURL(for: postURL),
           let data = try? await get(embed, userAgent: browserAgent),
           let html = String(data: data, encoding: .utf8),
           let caption = SocialImport.captionFromInstagramHTML(html) {
            return caption
        }
        // The page's own description, as link previews see it.
        let data = try await get(postURL, userAgent: previewAgent)
        if let html = String(data: data, encoding: .utf8), let caption = SocialImport.captionFromInstagramHTML(html) {
            return caption
        }
        throw Failure.noCaption(.instagram)
    }
}
