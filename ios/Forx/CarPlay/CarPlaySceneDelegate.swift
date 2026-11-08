import CarPlay
import CoreLocation
import os
import SwiftUI
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    /// Rebuild this often, so "38 minutes ago" and the Climate row stay true between changes
    /// (`dashboard` also updates the template buttons; nothing else re-reads the clock).
    static let tickInterval: Duration = .seconds(30)

    private static let log = Logger(subsystem: "com.milanpatel.Forx", category: "carplay")

    private var interfaceController: CPInterfaceController?
    private var window: CPWindow?
    private var host: UIHostingController<DashboardView>?
    private var templates: CarPlayTemplates?
    /// Fingers on the map → the 3D Jeep and the dashboard. One per connect.
    private var gestures: JeepGestures?
    private var motion: DashboardMotion?
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
        let motion = DashboardMotion()
        let gestures = JeepGestures(motion: motion)
        self.motion = motion
        self.gestures = gestures
        templates = CarPlayTemplates(
            interface: interfaceController,
            open: { [weak scene] url in scene?.open(url, options: nil, completionHandler: nil) },
            perform: { cmd in Task { await AppModel.store.perform(cmd, fromCarPlay: true) } },
            gestures: gestures)

        let dark = Self.isDark(window)
        let host = UIHostingController(rootView: Self.dashboard(dark: dark, gestures: gestures, motion: motion))
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
        #if DEBUG
        // demo states for screenshots (FORX_CP=demo-…): applied as the buttons would
        if CarPlayDebug.demo {
            if let roof = CarPlayDebug.demoRoof { AppModel.roof = roof }
            if let mode = CarPlayDebug.demoMode { motion.mode = mode }
            if CarPlayDebug.demoMap { templates?.setMap(open: true) }
            CarPlayDebug.runDemoDrag(gestures, motion: motion)
        }
        #endif
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
        gestures = nil
        motion = nil
        self.interfaceController = nil
        self.window = nil
    }

    // MARK: Store → window

    /// Builds the dashboard under observation (store, roof and the dashboard's own
    /// motion). The first change re-runs this on the next main-actor turn, so a burst of changes
    /// becomes one rebuild.
    private func observe() {
        guard connected else { return }
        let dark = Self.isDark(window)
        let gestures = self.gestures
        let motion = self.motion
        let templates = self.templates
        let view = withObservationTracking {
            Self.dashboard(templates: templates, dark: dark, gestures: gestures, motion: motion)
        } onChange: { [weak self] in
            let delegate = self
            Task { @MainActor in delegate?.observe() }
        }
        paint(dark)
        host?.rootView = view
        flush()
    }

    /// CarPlay's window doesn't redraw SwiftUI by itself after a root-view change (the map stayed
    /// shut when Earth opened it): lay it out now.
    private func flush() {
        host?.view.setNeedsLayout()
        host?.view.layoutIfNeeded()
    }

    /// A rebuild outside observation (ticker, Reduce Motion, appearance); the observation stays armed.
    private func render() {
        guard connected else { return }
        let dark = Self.isDark(window)
        if let window {
            Self.log.notice("CarPlay window bounds=\(NSCoder.string(for: window.bounds), privacy: .public) safe=\(NSCoder.string(for: window.safeAreaInsets), privacy: .public)")
        }
        paint(dark)
        host?.rootView = Self.dashboard(templates: templates, dark: dark, gestures: gestures, motion: motion)
        flush()
    }

    private func paint(_ dark: Bool) {
        host?.view.backgroundColor = dark ? .black : UIColor(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255, alpha: 1)
    }

    /// CarPlay's appearance: night unless the window says light.
    private static func isDark(_ window: UIWindow?) -> Bool {
        if CarPlayDebug.forceDay { return false }
        return window?.traitCollection.userInterfaceStyle != .light
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
    static func dashboard(
        templates: CarPlayTemplates? = nil, dark: Bool = true, gestures: JeepGestures? = nil,
        motion: DashboardMotion? = nil, now: Date = Date()
    ) -> DashboardView {
        let store = AppModel.store
        let roof = AppModel.roof
        // Debug demo first (FORX_CP=demo); then the live snapshot; signed in but the first fetch
        // hasn't landed yet: the one on disk, before falling back to "—".
        let demo = CarPlayDebug.demoSnapshot(now: now)
        let signedIn = demo != nil || !store.needsSignIn
        let snapshot = demo ?? store.snapshot ?? (signedIn ? store.lastKnownSnapshot : nil)
        let climateOn = store.climateOnUntil.map { now < $0 } ?? false
        // read here, under observation: the buttons and the page follow the map and the view
        let mapOpen = motion?.mapOpen ?? false
        let mode = motion?.mode ?? .hero
        let model = CarPlayModel.make(
            snapshot: snapshot, pending: store.pending, climateOn: climateOn, message: store.message,
            signedIn: signedIn, roof: roof, mode: mode, mapOpen: mapOpen, now: now)
        templates?.update(model, dark: dark)
        let state = JeepEmbedState.make(
            snapshot: snapshot, roof: roof, reducedMotion: UIAccessibility.isReduceMotionEnabled, dark: dark,
            mode: mode, charge: model.chargeText, tires: model.tires, tiresAgo: model.tiresAgo)
        var location: CLLocationCoordinate2D? = nil
        if let lat = snapshot?.latitude, let lng = snapshot?.longitude {
            location = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return DashboardView(
            model: model, jeepState: state, location: location, battery: snapshot?.evPercent,
            charging: snapshot?.charging == true, dark: dark, gestures: gestures, motion: motion)
    }
}
