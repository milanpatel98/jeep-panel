import Foundation
import WebKit

/// Serves `Web/` from the app bundle on `forx://app/`. Anything else is a 404.
/// Shared by the phone panel (`PanelWebView`) and the CarPlay 3D Jeep (`JeepEmbedView`).
final class ForxSchemeHandler: NSObject, WKURLSchemeHandler {
    /// The bundle's `Web/` folder.
    static var bundleRoot: URL? {
        Bundle.main.url(forResource: "Web", withExtension: nil)
    }

    /// Registers a handler for `forx://` on `config`, serving the bundle's `Web/` folder.
    static func install(in config: WKWebViewConfiguration) {
        config.setURLSchemeHandler(ForxSchemeHandler(root: bundleRoot), forURLScheme: WebFiles.scheme)
    }

    private let root: URL?

    init(root: URL?) {
        self.root = root
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        // Local files, memory-mapped: answered in one go, so `stop` never interrupts a response.
        if let root, let file = WebFiles.fileURL(for: url, root: root),
           let data = try? Data(contentsOf: file, options: .mappedIfSafe) {
            respond(urlSchemeTask, url: url, status: 200, data: data,
                    mime: WebFiles.mimeType(forPath: file.lastPathComponent))
        } else {
            respond(urlSchemeTask, url: url, status: 404, data: Data(), mime: "text/plain")
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    private func respond(_ task: any WKURLSchemeTask, url: URL, status: Int, data: Data, mime: String) {
        let headers = [
            "Content-Type": mime,
            "Content-Length": String(data.count),
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-cache",
        ]
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
        else {
            task.didFailWithError(URLError(.cannotParseResponse))
            return
        }
        task.didReceive(response)
        if !data.isEmpty { task.didReceive(data) }
        task.didFinish()
    }
}
