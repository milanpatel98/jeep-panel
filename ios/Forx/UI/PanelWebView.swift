import Foundation
import Observation
import SwiftUI
import UIKit
import WebKit

// MARK: - Files (pure, tested)

/// The bundle's `Web/` folder, served as `forx://app/…`.
nonisolated enum WebFiles {
    static let scheme = "forx"
    static let host = "app"
    static let startURL = URL(string: "forx://app/index.html")!

    static func mimeType(forPath path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html", "htm": "text/html"
        case "js", "mjs": "text/javascript"
        case "css": "text/css"
        case "glb": "model/gltf-binary"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "json": "application/json"
        case "webmanifest": "application/manifest+json"
        default: "application/octet-stream"
        }
    }

    /// The path inside `Web/` for a request, or nil for another scheme or host, or any
    /// `.`/`..` segment or backslash (also when percent-encoded).
    static func relativePath(for url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host(percentEncoded: false)?.lowercased() == host
        else { return nil }
        let raw = url.path(percentEncoded: false)
        if raw.contains("\\") || raw.contains("\0") { return nil }
        let parts = raw.split(separator: "/", omittingEmptySubsequences: true)
        if parts.contains(where: { $0 == ".." || $0 == "." }) { return nil }
        return parts.isEmpty ? "index.html" : parts.joined(separator: "/")
    }

    /// The regular file to serve, or nil (→ 404). Symlinks are resolved and must stay inside `root`.
    static func fileURL(for url: URL, root: URL) -> URL? {
        guard let rel = relativePath(for: url) else { return nil }
        let rootPath = trimmed(root.standardizedFileURL.resolvingSymlinksInPath())
        let file = root.appendingPathComponent(rel).standardizedFileURL.resolvingSymlinksInPath()
        guard trimmed(file).hasPrefix(rootPath + "/") else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: trimmed(file), isDirectory: &isDir), !isDir.boolValue
        else { return nil }
        return file
    }

    private static func trimmed(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}

// MARK: - Messages (pure, tested)

/// A message the page posts to the `jeep` handler (src/native.js contract).
nonisolated enum PanelMessage: Equatable, Sendable {
    case ready
    case command(JeepCommand)
    /// The settings gear (Task 12).
    case settings
}

/// Unknown types and actions are nil, so they're ignored.
nonisolated func panelMessage(_ body: Any) -> PanelMessage? {
    guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
    switch type {
    case "ready": return .ready
    case "settings": return .settings
    case "command":
        guard let action = dict["action"] as? String, let cmd = panelCommand(action) else { return nil }
        return .command(cmd)
    default: return nil
    }
}

/// The page's action names (ACTIONS in src/native.js) → commands.
nonisolated func panelCommand(_ action: String) -> JeepCommand? {
    switch action {
    case "lock": .lock
    case "unlock": .unlock
    case "climateOn": .climateOn
    case "climateOff": .climateOff
    case "lights": .lights
    case "horn": .horn
    case "gate": .gate
    default: nil
    }
}

// MARK: - Scheme handler

/// Serves `Web/` from the app bundle on `forx://app/`. Anything else is a 404.
final class WebSchemeHandler: NSObject, WKURLSchemeHandler {
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

// MARK: - Message handler proxy

/// `WKUserContentController` retains its handlers; this keeps only a weak reference to the
/// coordinator so the web view and coordinator aren't kept alive by each other.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

// MARK: - View

/// The Jeep Panel web app, full screen. JeepStore owns the data: the page posts commands,
/// and every store change is pushed back with `window.jeepNative.apply(patch)`.
struct PanelWebView: UIViewRepresentable {
    static let handlerName = "jeep"

    let store: JeepStore
    /// Called when the page posts `{type:"settings"}` (the gear; Task 12).
    var onSettings: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store, onSettings: onSettings)
    }

    func makeUIView(context: Context) -> WKWebView {
        let coordinator = context.coordinator

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(
            WebSchemeHandler(root: Bundle.main.url(forResource: "Web", withExtension: nil)),
            forURLScheme: WebFiles.scheme)
        let content = config.userContentController
        content.add(WeakScriptMessageHandler(coordinator), name: Self.handlerName)
        // The page turns off rubber-banding (overscroll-behavior: none), which would also stop
        // pull-to-refresh; let the root scroll vertically again. The bottom is clamped natively.
        content.addUserScript(WKUserScript(
            source: """
            (function () {
              var s = document.createElement('style');
              s.textContent = 'html { overscroll-behavior-y: auto !important; }';
              (document.head || document.documentElement).appendChild(s);
            })();
            """,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false  // no white flash: transparent over black until the first load
        webView.backgroundColor = .black
        webView.underPageBackgroundColor = .black
        #if DEBUG
        webView.isInspectable = true
        #endif

        let scrollView = webView.scrollView
        scrollView.backgroundColor = .black
        scrollView.contentInsetAdjustmentBehavior = .never  // the page handles safe areas (viewport-fit=cover)
        scrollView.bouncesHorizontally = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = true  // pull-to-refresh only; see scrollViewDidScroll
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = coordinator

        let refresh = UIRefreshControl()
        refresh.tintColor = .white
        refresh.addTarget(coordinator, action: #selector(Coordinator.pulledToRefresh(_:)), for: .valueChanged)
        scrollView.refreshControl = refresh

        webView.navigationDelegate = coordinator
        coordinator.webView = webView
        coordinator.observe()
        webView.load(URLRequest(url: WebFiles.startURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSettings = onSettings
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: handlerName)
        webView.navigationDelegate = nil
        webView.scrollView.delegate = nil
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, UIScrollViewDelegate {
        let store: JeepStore
        var onSettings: (() -> Void)?
        weak var webView: WKWebView?

        /// Re-push this often while the page is ready, so "Updated N min ago" stays true between changes.
        static let tickInterval: Duration = .seconds(30)

        /// The page posted `ready` (its `window.jeepNative` exists). Reset on every new load.
        private var ready = false
        private var stopped = false
        private var ticker: Task<Void, Never>? = nil

        init(store: JeepStore, onSettings: (() -> Void)?) {
            self.store = store
            self.onSettings = onSettings
        }

        func stop() {
            stopped = true
            notReady()
        }

        private func notReady() {
            ready = false
            ticker?.cancel()
            ticker = nil
        }

        /// Pushes the current patch every 30 s until the page reloads or the view goes away.
        private func startTicker() {
            ticker?.cancel()
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Coordinator.tickInterval)
                    guard !Task.isCancelled, let self else { return }
                    self.push(self.store.patch)
                }
            }
        }

        // MARK: Store → page

        /// Reads `store.patch` under observation and pushes it. The first change re-runs this
        /// on the next main-actor turn, so a burst of changes becomes one push with the latest patch.
        func observe() {
            guard !stopped else { return }
            let patch = withObservationTracking {
                store.patch
            } onChange: { [weak self] in
                let coordinator = self
                Task { @MainActor in coordinator?.observe() }
            }
            push(patch)
        }

        private func push(_ patch: [String: Any]) {
            guard ready, !stopped, let webView,
                  JSONSerialization.isValidJSONObject(patch),
                  let data = try? JSONSerialization.data(withJSONObject: patch),
                  let json = String(data: data, encoding: .utf8)
            else { return }
            webView.evaluateJavaScript(
                "window.jeepNative && window.jeepNative.apply(\(json))", completionHandler: nil)
        }

        // MARK: Page → store

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !stopped, message.name == PanelWebView.handlerName, message.frameInfo.isMainFrame,
                  let msg = panelMessage(message.body) else { return }  // unknown messages are ignored
            switch msg {
            case .ready:
                ready = true
                push(store.patch)
                startTicker()
            case .command(let cmd):
                let store = self.store
                Task { await store.perform(cmd) }
            case .settings:
                onSettings?()
            }
        }

        @objc func pulledToRefresh(_ control: UIRefreshControl) {
            let store = self.store
            Task {
                await store.refresh()
                control.endRefreshing()
            }
        }

        // MARK: Navigation

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            notReady()  // a (re)load: wait for the new page's `ready`
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.isOpaque = true
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            notReady()
            webView.isOpaque = false
            webView.load(URLRequest(url: WebFiles.startURL))
        }

        /// The panel stays on `forx://`; links (e.g. the map's OpenStreetMap credit) open in Safari.
        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            let scheme = url.scheme?.lowercased()
            if scheme == WebFiles.scheme || scheme == "about" { return .allow }
            guard navigationAction.targetFrame?.isMainFrame ?? true else { return .allow }  // subframes
            if scheme == "https" || scheme == "http" {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            return .cancel
        }

        // MARK: Scrolling

        /// No bounce at the bottom: only the pull at the top (for refresh) moves the page.
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height
                + scrollView.adjustedContentInset.bottom)
            if scrollView.contentOffset.y > maxY {
                scrollView.contentOffset.y = maxY
            }
        }
    }
}
