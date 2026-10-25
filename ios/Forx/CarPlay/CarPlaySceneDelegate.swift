import CarPlay
import CoreLocation
import os
import SwiftUI
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    /// Rebuild this often, so the Climate map button turns off when its 15 minutes run out
    /// (`dashboard` also updates the template buttons; nothing else re-reads the clock).
    static let tickInterval: Duration = .seconds(30)

    private static let log = Logger(subsystem: "com.milanpatel.Forx", category: "carplay")

    private var interfaceController: CPInterfaceController?
    private var window: CPWindow?
    private var host: UIHostingController<DashboardView>?
    private var templates: CarPlayTemplates?
    /// Drags on the map → the 3D Jeep. One per connect.
    private var spin: DashboardSpin?
    private var connected = false
    private var ticker: Task<Void, Never>? = nil
    private var motionObserver: (any NSObjectProtocol)? = nil

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController
        self.window = window
        let mode = CarPlayDebug.mode ?? "normal"
        Self.log.notice("CarPlay connect mode=\(mode, privacy: .public) bounds=\(NSCoder.string(for: window.bounds), privacy: .public)")

        // Built once per connect: sets the map template as root; updates go in place.
        let scene = templateApplicationScene
        let spin = DashboardSpin()
        self.spin = spin
        templates = CarPlayTemplates(
            interface: interfaceController,
            open: { [weak scene] url in scene?.open(url, options: nil, completionHandler: nil) },
            perform: { cmd in Task { await AppModel.store.perform(cmd, fromCarPlay: true) } },
            spin: spin)

        let dark = Self.isDark(window)
        let host = UIHostingController(rootView: Self.dashboard(dark: dark, spin: spin))
        host.view.backgroundColor = dark ? .black : UIColor(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255, alpha: 1)
        window.rootViewController = host
        self.host = host
        connected = true
        // Day and night follow CarPlay's appearance (the car's light sensor and headlights).
        window.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: CPWindow, _: UITraitCollection) in
            self?.render()
        }
        observe()
        startTicker()
        motionObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            let delegate = self
            Task { @MainActor in delegate?.render() }
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        connected = false
        ticker?.cancel()
        ticker = nil
        if let motionObserver { NotificationCenter.default.removeObserver(motionObserver) }
        motionObserver = nil
        window.rootViewController = nil  // frees the 3D Jeep's WebGL context now
        host = nil
        templates = nil
        spin = nil
        self.interfaceController = nil
        self.window = nil
    }

    // MARK: Store → window

    /// Builds the dashboard under observation (store and roof). The first change re-runs this on
    /// the next main-actor turn, so a burst of changes becomes one rebuild.
    private func observe() {
        guard connected else { return }
        let dark = Self.isDark(window)
        let spin = self.spin
        let templates = self.templates
        let view = withObservationTracking {
            Self.dashboard(templates: templates, dark: dark, spin: spin)
        } onChange: { [weak self] in
            let delegate = self
            Task { @MainActor in delegate?.observe() }
        }
        paint(dark)
        host?.rootView = view
    }

    /// A rebuild outside observation (ticker, Reduce Motion, appearance); the observation stays armed.
    private func render() {
        guard connected else { return }
        let dark = Self.isDark(window)
        paint(dark)
        host?.rootView = Self.dashboard(templates: templates, dark: dark, spin: spin)
    }

    private func paint(_ dark: Bool) {
        host?.view.backgroundColor = dark ? .black : UIColor(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255, alpha: 1)
    }

    /// CarPlay's appearance: night unless the window says light.
    private static func isDark(_ window: UIWindow?) -> Bool {
        window?.traitCollection.userInterfaceStyle != .light
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: CarPlaySceneDelegate.tickInterval)
                guard !Task.isCancelled, let self else { return }
                self.render()
            }
        }
    }

    /// The dashboard for the store's state now; also updates the CarPlay buttons in place.
    private static func dashboard(
        templates: CarPlayTemplates? = nil, dark: Bool = true, spin: DashboardSpin? = nil, now: Date = Date()
    ) -> DashboardView {
        let store = AppModel.store
        let roof = AppModel.roof
        // Debug demo first (FORX_CP=demo); then the live snapshot; signed in but the first fetch
        // hasn't landed yet: the one on disk, before falling back to "—".
        let demo = CarPlayDebug.demoSnapshot(now: now)
        let signedIn = demo != nil || !store.needsSignIn
        let snapshot = demo ?? store.snapshot ?? (signedIn ? store.lastKnownSnapshot : nil)
        let climateOn = store.climateOnUntil.map { now < $0 } ?? false
        let model = CarPlayModel.make(
            snapshot: snapshot, pending: store.pending, climateOn: climateOn, message: store.message,
            signedIn: signedIn, roof: roof, now: now)
        templates?.update(model, dark: dark)
        let state = JeepEmbedState.make(
            snapshot: snapshot, roof: roof, reducedMotion: UIAccessibility.isReduceMotionEnabled, dark: dark)
        var location: CLLocationCoordinate2D? = nil
        if let lat = snapshot?.latitude, let lng = snapshot?.longitude {
            location = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return DashboardView(
            model: model, jeepState: state, location: location, battery: snapshot?.evPercent,
            charging: snapshot?.charging == true, dark: dark, spin: spin, tray: templates?.tray)
    }
}
