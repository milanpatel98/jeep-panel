import Foundation
import SwiftUI
import UIKit
import WebKit

// MARK: - State (pure, tested)

/// The state for `window.jeepEmbed.apply(state)` (src/embed.js, src/embedState.js).
nonisolated enum JeepEmbedState {
    /// Doors map like the phone patch: driver = FL, passenger = FR, rear left = BL, rear right = BR.
    /// Lights are always off here (the headlight flash is momentary). `locked` is true, false or
    /// null (unknown: no lock above the roof). Roof "doorsOff" is the top off with the doors off
    /// too. `dark` picks the page's night or day studio. `mode` is the view, `charge` the charge
    /// port's call-out, `tires` the four pressures with their age.
    static func make(
        snapshot s: JeepSnapshot?, roof: String, reducedMotion: Bool, dark: Bool = true,
        mode: JeepMode = .hero, charge: String? = nil, tires: [String: String] = [:], tiresAgo: String = ""
    ) -> [String: Any] {
        let open = Set(s?.doorsOpen ?? [])
        let doors: [String: Bool] = [
            "FL": open.contains("driver"),
            "FR": open.contains("passenger"),
            "BL": open.contains("leftRear"),
            "BR": open.contains("rightRear"),
        ]
        var tireMap: [String: Any] = tires
        tireMap["ago"] = tiresAgo
        var state: [String: Any] = [
            "lights": false,
            "roof": roof == "doorsOff" ? "off" : roof,
            "doorsOff": roof == "doorsOff",
            "theme": dark ? "dark" : "light",
            "doors": doors,
            "gate": s?.tailgateOpen == true,
            "reducedMotion": reducedMotion,
            "mode": mode.rawValue,
            "locked": s?.locked.map { $0 as Any } ?? NSNull(),
            "charge": charge.map { $0 as Any } ?? NSNull(),
            "tires": tireMap,
        ]
        return state
    }

    /// Stable JSON (sorted keys), so the same state is never pushed twice.
    static func json(_ state: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(state),
              let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// What the page says it's doing: its loading screen is painted (`loader`), the model's
    /// progress, or the Jeep is on screen (`ready`). Anything else is nil.
    static func page(_ body: Any) -> DashboardMotion.Page? {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "loader": return .loading(0)
        case "progress": return .loading(min(1, max(0, (dict["value"] as? Double) ?? 0)))
        case "ready": return .ready
        default: return nil
        }
    }
}

// MARK: - View

/// The 3D black Jeep on its mirror floor (`forx://app/embed.html`), transparent over the window,
/// full-screen. The view takes no touches: CarPlay's gestures reach the page through `gestures`.
/// The page's loading screen and its `ready` are reported to `motion`.
struct JeepEmbedView: UIViewRepresentable {
    static let url = URL(string: "forx://app/embed.html")!

    let state: [String: Any]
    var gestures: JeepGestures? = nil
    var motion: DashboardMotion? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let coordinator = context.coordinator

        let config = WKWebViewConfiguration()
        ForxSchemeHandler.install(in: config)
        config.userContentController.add(WeakScriptMessageHandler(coordinator), name: PanelWebView.handlerName)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.underPageBackgroundColor = .clear
        webView.isUserInteractionEnabled = false

        let scrollView = webView.scrollView
        scrollView.backgroundColor = .clear
        scrollView.isScrollEnabled = false
        scrollView.bounces = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false

        webView.navigationDelegate = coordinator
        coordinator.webView = webView
        coordinator.motion = motion
        coordinator.attach(gestures)
        coordinator.update(state)
        webView.load(URLRequest(url: Self.url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.motion = motion
        context.coordinator.attach(gestures)
        context.coordinator.update(state)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: PanelWebView.handlerName)
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        weak var motion: DashboardMotion?

        private var state: [String: Any] = [:]
        /// The page posted `ready`. Reset on every new load.
        private var ready = false
        private var stopped = false
        /// The JSON last applied, so an unchanged state isn't pushed again.
        private var pushed: String? = nil

        func update(_ state: [String: Any]) {
            self.state = state
            push()
        }

        func stop() {
            stopped = true
            ready = false
        }

        /// Gestures from CarPlay come in as page calls (`spin(4.2)`, `strip(-12, 1)`, …).
        func attach(_ gestures: JeepGestures?) {
            guard let gestures, gestures !== attached else { return }
            attached = gestures
            gestures.send = { [weak self] call in self?.call(call) }
        }

        private weak var attached: JeepGestures?

        private func call(_ js: String) {
            guard ready, !stopped, let webView else { return }
            webView.evaluateJavaScript("window.jeepEmbed && window.jeepEmbed.\(js)", completionHandler: nil)
        }

        private func push() {
            guard ready, !stopped, let webView, let json = JeepEmbedState.json(state), json != pushed
            else { return }
            pushed = json
            webView.evaluateJavaScript(
                "window.jeepEmbed && window.jeepEmbed.apply(\(json))", completionHandler: nil)
        }

        // MARK: Page → app

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !stopped, message.name == PanelWebView.handlerName, message.frameInfo.isMainFrame,
                  let page = JeepEmbedState.page(message.body) else { return }  // errors: ignored
            if let motion, motion.page != page {
                // `ready` sticks; progress never moves the dashboard backwards from ready
                if case .ready = motion.page { } else { motion.page = page }
            }
            guard case .ready = page else { return }
            ready = true
            pushed = nil
            push()
        }

        // MARK: Navigation

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            ready = false  // a (re)load: wait for the new page's `ready`
            pushed = nil
            motion?.page = .blank
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            ready = false
            pushed = nil
            motion?.page = .blank
            guard !stopped else { return }
            webView.load(URLRequest(url: JeepEmbedView.url))
        }

        /// The page stays on `forx://`; nothing else loads.
        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            let scheme = navigationAction.request.url?.scheme?.lowercased()
            return scheme == WebFiles.scheme || scheme == "about" ? .allow : .cancel
        }
    }
}
