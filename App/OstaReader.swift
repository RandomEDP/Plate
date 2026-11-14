import PlateCore
import UIKit
import WebKit

/// Opens an Osta page out of sight, lets its JavaScript draw the recipe, and reads the page's text. Osta has no export
/// and its pages are empty until the script runs, so this is the only way in. Nothing is sent but the page request.
@MainActor
final class OstaReader {
    enum Failure: LocalizedError {
        case noRecipe(OstaImport.Miss)
        case noRecipesInFolder
        case loading(String)

        var errorDescription: String? {
            switch self {
            case .noRecipe(.notARecipe):
                return "Osta showed its home page, not this recipe, so it's private or has been removed. Tap Open to check in Safari."
            case .noRecipe(.unreadable):
                return "Osta showed the recipe, but Plate couldn't pick out its ingredients. Tap Open, and send a screenshot of the page so the reader can be fixed."
            case .noRecipe(.notFound):
                return "Osta's website says \"Recipe not found\": Osta only shows this one in its app. Copy the recipe's text from the Osta app and paste it into Recipes → From a Reel or TikTok instead."
            case .noRecipe(.empty):
                return "Osta's page didn't load in 20 seconds. Check your connection and try again."
            case .noRecipesInFolder:
                return "Osta's folder page didn't list any recipes (it may only open in the Osta app). In Osta, open each recipe, tap Share → Copy, and paste the links here instead."
            case .loading(let m):
                return "Couldn't open Osta's page (\(m)). Check your connection and try again."
            }
        }
    }

    private static let script = """
    (() => {
      const h1 = document.querySelector('h1');
      const links = Array.from(document.querySelectorAll('a[href]')).map(a => a.href);
      const html = document.documentElement ? document.documentElement.innerHTML : '';
      const ids = html.match(/recipes?\\/[A-Za-z0-9_-]{8,40}/g) || [];
      const og = document.querySelector('meta[property="og:image"], meta[name="twitter:image"]');
      return JSON.stringify({
        image: og ? og.content : '',
        title: h1 ? h1.innerText : (document.title || ''),
        text: document.body ? document.body.innerText : '',
        links: links.concat(ids)
      });
    })()
    """

    /// Reads one recipe page.
    static func recipe(_ url: URL) async throws -> OstaImport.Extract {
        let reader = OstaReader()
        defer { reader.close() }
        try reader.open(url)
        var lastText = ""
        // Up to 20 seconds: done once there's a recipe and the text has stopped changing.
        for tick in 0..<40 {
            try? await Task.sleep(for: .milliseconds(500))
            guard let page = await reader.page() else { continue }
            if let found = OstaImport.extract(page), page.text == lastText, tick >= 3 { return found }
            lastText = page.text
        }
        guard let page = await reader.page() else { throw Failure.noRecipe(.empty) }
        if let found = OstaImport.extract(page) { return found }
        throw Failure.noRecipe(OstaImport.miss(page))
    }

    /// Reads a shared folder page and gives the links of the recipes in it, scrolling so it loads them all.
    static func folder(_ url: URL) async throws -> [URL] {
        let reader = OstaReader()
        defer { reader.close() }
        try reader.open(url)
        var best: [URL] = []
        var steady = 0
        for _ in 0..<60 {
            try? await Task.sleep(for: .milliseconds(500))
            _ = try? await reader.web.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight); true")
            guard let page = await reader.page() else { continue }
            let links = OstaImport.recipeLinks(in: page.links)
            if links.count > best.count { best = links; steady = 0 } else { steady += 1 }
            if !best.isEmpty, steady >= 6 { break }
        }
        if best.isEmpty { throw Failure.noRecipesInFolder }
        return best
    }

    let web: WKWebView

    private init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        web.customUserAgent = CaptionFetcher.browserAgent
        // Pages only run their scripts properly when they're in a window, so it sits there almost invisibly.
        web.alpha = 0.01
        web.isUserInteractionEnabled = false
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        window?.insertSubview(web, at: 0)
    }

    private func open(_ url: URL) throws {
        guard web.load(URLRequest(url: url, timeoutInterval: 20)) != nil else { throw Failure.loading("the link didn't open") }
    }

    private func page() async -> OstaImport.Page? {
        guard let json = try? await web.evaluateJavaScript(Self.script) as? String,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return OstaImport.Page(title: obj["title"] as? String ?? "",
                               text: obj["text"] as? String ?? "",
                               links: obj["links"] as? [String] ?? [],
                               image: (obj["image"] as? String).flatMap { $0.isEmpty ? nil : $0 })
    }

    private func close() {
        web.stopLoading()
        web.removeFromSuperview()
    }
}
