import Foundation
import PlateCore

/// Gets the caption (where creators put the recipe) for an Instagram Reel or TikTok link.
enum CaptionFetcher {
    enum Failure: LocalizedError {
        case notALink
        case unsupported
        case noCaption(SocialImport.Platform)
        case network(String)

        var errorDescription: String? {
            switch self {
            case .notALink:
                return "That doesn't look like a link. Paste the Reel or TikTok link, or paste the caption itself."
            case .unsupported:
                return "Plate can read Instagram and TikTok links. For anything else, paste the recipe text."
            case .noCaption(let p):
                let app = p == .instagram ? "Instagram" : "TikTok"
                return "\(app) didn't share the caption for this post (it may be private). Open the post in \(app), tap the caption to expand it, copy it and paste it here."
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

    static func tiktok(_ url: URL) async throws -> SocialImport.Caption {
        guard let oembed = SocialImport.tiktokOEmbedURL(for: url) else { throw Failure.noCaption(.tiktok) }
        let data = try await get(oembed, userAgent: browserAgent)
        guard let caption = SocialImport.captionFromTikTokOEmbed(data) else { throw Failure.noCaption(.tiktok) }
        return caption
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
